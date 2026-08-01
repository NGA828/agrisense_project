"""Celery tasks for the payments app."""

from datetime import timedelta

from celery import shared_task


@shared_task
def reconcile_payments_task(max_age_minutes=120):
    """Reconcile in-flight payments against their provider.

    Finds payments stuck in ``pending``/``processing`` older than
    ``max_age_minutes`` and asks the gateway for the final state. This catches
    cases where a webhook or polling callback was missed. For the sandbox
    gateway (which finalizes synchronously) there is nothing to reconcile, so
    this is a no-op until a real provider is configured.
    """
    from django.utils import timezone

    from .models import Payment
    from .gateway import get_gateway
    from .services import complete_payment, finalize_payment_failed

    cutoff = timezone.now() - timedelta(minutes=max_age_minutes)
    stale = Payment.objects.filter(
        status__in=('pending', 'processing'), updated_at__lt=cutoff,
    ).select_related('order')

    reconciled = 0
    for payment in stale:
        gateway = get_gateway(payment.payment_method)
        if gateway.provider == 'sandbox':
            continue  # nothing external to reconcile
        try:
            provider_status = gateway.verify_transaction(payment.transaction_id)
        except Exception:
            continue
        if provider_status == 'completed' and payment.status != 'completed':
            complete_payment(payment.pk)
            reconciled += 1
        elif provider_status == 'failed' and payment.status not in ('completed', 'refunded'):
            finalize_payment_failed(payment.pk)
            reconciled += 1
    return reconciled

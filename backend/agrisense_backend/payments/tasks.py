"""Reconcile without confusing an unavailable provider with a rejected charge."""
import logging
from datetime import timedelta
from celery import shared_task

logger = logging.getLogger(__name__)


@shared_task
def reconcile_payments_task(max_age_minutes=1):
    from django.utils import timezone
    from .models import Payment
    from .services import reconcile_payment, FINAL_STATUSES

    cutoff = timezone.now() - timedelta(minutes=max_age_minutes)
    pending = Payment.objects.filter(status='processing', updated_at__lte=cutoff)
    reconciled = 0
    for pk in pending.values_list('pk', flat=True).iterator():
        try:
            if reconcile_payment(pk).status in FINAL_STATUSES:
                reconciled += 1
        except Exception:
            # A broken/misconfigured provider must not stop all other payments
            # from reconciling, and must never mark this attempt failed.
            logger.exception('Could not reconcile payment id=%s', pk)
    return reconciled

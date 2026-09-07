"""One payment state machine shared by checkout, polling, callbacks and jobs."""
from datetime import timedelta
from decimal import Decimal, InvalidOperation

from django.db import transaction
from django.utils import timezone

from ledger import services as ledger
from .gateway import get_gateway, PaymentError, PaymentStatusUnknown

FINAL_STATUSES = ('completed', 'failed', 'refunded', 'review_required')


def _notify(user, title, message, ntype='system', reference_id=''):
    from announcements.models import notify_user
    return notify_user(user, title, message, type=ntype, reference_id=reference_id)


def _lock_payment(payment_id):
    """Always lock parent -> payment -> product, including during callbacks.

    Serialising on the order prevents *different* attempts for one order from
    being submitted/credited concurrently. Premium payments lock their user.
    Must be called inside transaction.atomic().
    """
    from .models import Payment
    from products.models import Order
    from users.models import User

    snapshot = Payment.objects.only('order_id', 'user_id').get(pk=payment_id)
    order = Order.objects.select_for_update().get(pk=snapshot.order_id) if snapshot.order_id else None
    user = None if order else User.objects.select_for_update().get(pk=snapshot.user_id)
    payment = Payment.objects.select_for_update().get(pk=payment_id)
    if order:
        payment.order = order
    if user:
        payment.user = user
    return payment, order


def _premium_months(description):
    import re
    match = re.search(r'\((\d+) month', description or '')
    return min(12, max(1, int(match.group(1)))) if match else 1


def _stock_changed(product):
    from products.views import _push_stock
    transaction.on_commit(lambda: _push_stock(product))


def _mark_collection_for_review(payment):
    payment.status = 'review_required'
    payment.last_error = 'Funds received, but this purchase cannot be automatically confirmed.'
    payment.save(update_fields=['status', 'last_error', 'updated_at'])
    _notify(payment.user, 'Payment needs review',
            'Funds were received but the purchase could not be confirmed. Do not pay '
            'again. Contact support with reference ' + payment.transaction_id,
            ntype='payment', reference_id=payment.order_id or '')
    from users.models import User
    for admin in User.objects.filter(role='admin', is_active=True):
        _notify(admin, 'Payment reconciliation required',
                f'{payment.transaction_id}: collected funds for a closed, released, '
                'missing or already-paid purchase. Review before fulfilment/refund.',
                ntype='payment', reference_id=payment.order_id or '')
    return payment


@transaction.atomic
def complete_payment(payment_id):
    """Record a verified collection once. Only fulfil an eligible unpaid order.

    A late success for a cancelled/released order (or a second paid attempt)
    is held for admin review, not silently shipped without stock or discarded.
    """
    payment, order = _lock_payment(payment_id)
    if payment.status in ('completed', 'refunded', 'review_required'):
        return payment

    if payment.payment_type == 'premium' and payment.user.role == 'dealer':
        user = payment.user
        base = max(timezone.now(), user.premium_expiry) if user.premium_expiry else timezone.now()
        user.is_premium = True
        user.premium_expiry = base + timedelta(days=30 * _premium_months(payment.description))
        user.save(update_fields=['is_premium', 'premium_expiry'])
        ledger.record_premium_income(payment, reference=f'premium:{user.pk}')
        _notify(user, 'Premium activated' + (' [TEST]' if payment.is_test else ''),
                f'Your premium subscription is active until {user.premium_expiry:%d %b %Y}.',
                ntype='premium')
    elif order is not None:
        ledger.record_payment_collected(payment, reference=f'order:{order.pk}')
        if (payment.status == 'failed' or order.status != 'pending' or order.payment_status != 'unpaid'
                or order.reserved_until is None
                or order.total_price != payment.amount or order.farmer_id != payment.user_id):
            return _mark_collection_for_review(payment)
        order.payment_status = 'paid'
        order.payment_method = payment.payment_method
        order.status = 'confirmed'
        order.reserved_until = None
        order.save(update_fields=['payment_status', 'payment_method', 'status', 'reserved_until', 'updated_at'])
        label = ' [TEST — no money transferred]' if payment.is_test else ''
        _notify(payment.user, 'Payment confirmed' + label,
                f'Payment for order #{order.pk} was confirmed. The dealer has been notified.',
                ntype='payment', reference_id=order.pk)
        # This is the ONLY new-order notification, after verified payment.
        _notify(order.product.dealer, 'New paid order' + label,
                f'{payment.user.first_name or payment.user.username} paid '
                f'{payment.amount:.2f} FCFA for {order.quantity} x {order.product.name} '
                f'(order #{order.pk}).', ntype='order', reference_id=order.pk)
    else:
        # A legacy cascade/delete must not discard an authenticated collection.
        ledger.record_payment_collected(payment, reference=f'unassigned:{payment.pk}')
        return _mark_collection_for_review(payment)

    payment.status = 'completed'
    payment.last_error = ''
    payment.save(update_fields=['status', 'last_error', 'updated_at'])
    return payment


@transaction.atomic
def finalize_payment_failed(payment_id, provider_error=''):
    """Definite failure only. Idempotently release the active stock reservation."""
    payment, order = _lock_payment(payment_id)
    if payment.status in FINAL_STATUSES:
        return payment
    payment.status = 'failed'
    payment.last_error = str(provider_error)[:300]
    payment.save(update_fields=['status', 'last_error', 'updated_at'])
    if order is not None and order.payment_status == 'unpaid':
        if order.status == 'pending':
            if order.reserved_until is not None:
                from products.models import Product
                order.product = Product.objects.select_for_update().get(pk=order.product_id)
                order.release_stock()
                _stock_changed(order.product)
            order.status = 'payment_failed'
            order.save(update_fields=['status', 'reserved_until', 'updated_at'])
    _notify(payment.user, 'Payment failed',
            'The payment was not completed. No order was sent to the dealer. '
            'You can retry; stock availability will be checked again.',
            ntype='payment', reference_id=payment.order_id or '')
    return payment


@transaction.atomic
def _remember_pending_error(payment_id, message):
    payment, _ = _lock_payment(payment_id)
    if payment.status not in FINAL_STATUSES:
        payment.last_error = str(message)[:300]
        payment.save(update_fields=['last_error', 'updated_at'])
    return payment


@transaction.atomic
def _begin_collection(payment_id, expected_amount=None):
    payment, order = _lock_payment(payment_id)
    if payment.status in ('processing', 'completed', 'refunded', 'review_required'):
        return payment, None  # idempotent: no second provider request
    if payment.status != 'pending':
        raise ValueError('This attempt has failed. Start a new payment attempt for the same order.')
    if expected_amount is not None:
        try:
            quoted = Decimal(str(expected_amount))
            if not quoted.is_finite() or quoted != payment.amount:
                raise ValueError
        except (InvalidOperation, ValueError, TypeError):
            raise ValueError('The payment total changed. Review the current amount before paying.')
    if order:
        if order.payment_status != 'unpaid' or order.status not in ('pending', 'payment_failed'):
            raise ValueError('This order is closed or already paid.')
        from .models import Payment
        if Payment.objects.filter(order=order, status__in=('processing', 'review_required')).exclude(pk=payment.pk).exists():
            raise ValueError('Another payment is awaiting confirmation. Check that payment instead.')
        if order.status == 'pending' and order.reserved_until is None:
            raise ValueError('This order has no stock reservation. Cancel it and start a new checkout.')
        if order.status == 'pending' and order.reserved_until and order.reserved_until <= timezone.now():
            raise ValueError('The stock reservation expired. Cancel this order and start a new checkout.')

    gateway = get_gateway(payment.payment_method, environment=payment.gateway_environment or None)
    payment.phone_number = gateway.validate_phone(payment.phone_number)
    if order and order.status == 'payment_failed':
        from products.models import Product
        order.product = Product.objects.select_for_update().get(pk=order.product_id)
        order.hold_stock()
        _stock_changed(order.product)
    # Persist BEFORE the external request; concurrent taps/callbacks now see it.
    payment.status = 'processing'
    payment.gateway_environment = gateway.environment
    payment.submitted_at = timezone.now()
    payment.last_error = ''
    payment.save(update_fields=['status', 'gateway_environment', 'submitted_at',
                                'last_error', 'phone_number', 'updated_at'])
    return payment, gateway


def process_collection(payment_id, expected_amount=None):
    """Initiate once outside DB locks; uncertainty is NOT a failed payment."""
    try:
        payment, gateway = _begin_collection(payment_id, expected_amount=expected_amount)
        if gateway is None:
            return payment
        result = gateway.request_payment(
            amount=payment.amount, phone_number=payment.phone_number,
            description=payment.description, transaction_id=payment.transaction_id,
            provider_reference=payment.provider_reference,
        )
    except PaymentStatusUnknown as exc:
        return _remember_pending_error(payment_id, exc)
    except PaymentError as exc:
        return finalize_payment_failed(payment_id, provider_error=str(exc))
    if result.get('status') == 'completed':
        return complete_payment(payment_id)
    if result.get('status') == 'failed':
        return finalize_payment_failed(payment_id, provider_error='The provider declined the payment.')
    # A callback could already have completed it; never overwrite with pending.
    from .models import Payment
    return Payment.objects.get(pk=payment_id)


def reconcile_payment(payment_id):
    from .models import Payment
    payment = Payment.objects.get(pk=payment_id)
    if payment.status in FINAL_STATUSES or (payment.status == 'pending' and not payment.submitted_at):
        return payment
    try:
        gateway = get_gateway(payment.payment_method, environment=payment.gateway_environment or None)
        if gateway.provider == 'sandbox':
            return payment
        state = gateway.verify_transaction(
            payment.transaction_id, provider_reference=payment.provider_reference,
            amount=payment.amount, phone_number=payment.phone_number,
        )
    except PaymentError as exc:
        # Polling errors, including 404, are not proof that no money moved.
        return _remember_pending_error(payment_id, exc)
    if state == 'completed':
        return complete_payment(payment_id)
    if state == 'failed':
        return finalize_payment_failed(payment_id, provider_error='The provider declined the payment.')
    return Payment.objects.get(pk=payment_id)


@transaction.atomic
def refund_payment(payment_id):
    """Simulated refunds only until an actual provider refund adapter is added."""
    payment, order = _lock_payment(payment_id)
    if payment.status not in ('completed', 'review_required'):
        raise ValueError(f'Only collected payments can be refunded (current: {payment.status}).')
    if not payment.is_test:
        raise ValueError('Live refunds must be handled with MTN/support. This endpoint cannot '
                         'transfer funds back, so it will not mark a live payment refunded.')
    if order is None or order.status == 'delivered':
        raise ValueError('This payment requires a coordinated manual refund.')
    was_confirmed = payment.status == 'completed'
    ledger.record_refund(payment, reference=f'payment:{payment.transaction_id}')
    payment.status = 'refunded'
    payment.save(update_fields=['status', 'updated_at'])
    if was_confirmed:
        from products.models import Product
        order.product = Product.objects.select_for_update().get(pk=order.product_id)
        order.release_stock()
        order.payment_status = 'refunded'
        order.status = 'cancelled'
        order.save(update_fields=['payment_status', 'status', 'reserved_until', 'updated_at'])
        _stock_changed(order.product)
        _notify(order.product.dealer, 'Test order refunded', f'Order #{order.pk} was refunded.',
                ntype='payment', reference_id=order.pk)
    _notify(payment.user, 'Test refund recorded', 'This was a test payment. No money was transferred.',
            ntype='payment', reference_id=order.pk)
    return payment

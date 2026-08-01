"""
Payment business-logic service functions.

Shared by the API views, the HMAC webhook and the Celery reconciliation task so
there is a single, tested implementation of "what happens when a payment is
completed / failed / refunded".
"""

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from ledger import services as ledger


def _notify(user, title, message, ntype='system', reference_id=''):
    from announcements.models import notify_user
    return notify_user(user, title, message, type=ntype, reference_id=reference_id)


def _premium_months(description):
    # Extract the number of months from e.g. "Premium (2 month(s))".
    desc = description or ''
    open_idx = desc.find('(')
    if open_idx == -1:
        return 1
    digits = []
    for ch in desc[open_idx + 1:]:
        if ch.isdigit():
            digits.append(ch)
        elif digits:
            break
    return max(1, int(''.join(digits))) if digits else 1


@transaction.atomic
def complete_payment(payment_id):
    """Mark a payment completed and run its side effects (order/premium + ledger).

    Idempotent: completing an already-completed/refunded payment is a no-op.
    Returns the refreshed payment.
    """
    from .models import Payment

    payment = Payment.objects.select_for_update().get(pk=payment_id)
    if payment.status in ('completed', 'refunded'):
        return payment

    if payment.payment_type == 'premium' and payment.user.role == 'dealer':
        months = _premium_months(payment.description)
        user = payment.user
        base = (user.premium_expiry if (user.is_premium and user.premium_expiry and
                                        user.premium_expiry > timezone.now())
                else timezone.now())
        user.is_premium = True
        user.premium_expiry = base + timedelta(days=30 * months)
        user.save(update_fields=['is_premium', 'premium_expiry'])
        ledger.record_premium_income(payment, reference=f'premium:{user.id}')
        _notify(
            user,
            'Premium activated 🚀',
            f'Your premium dealer subscription is active until '
            f'{user.premium_expiry.strftime("%d %b %Y")}. Your products now rank '
            f'higher in farmer searches.',
            ntype='premium',
        )
        payment.status = 'completed'
        payment.save(update_fields=['status'])
        return payment

    if payment.order_id:
        order = payment.order
        order.payment_status = 'paid'
        if order.status == 'pending':
            order.status = 'confirmed'
        order.save(update_fields=['payment_status', 'status'])
        ledger.record_payment_collected(payment, reference=f'order:{order.id}')
        _notify(
            payment.user,
            'Payment successful ✅',
            f'Your payment of {payment.amount:.2f} FCFA for {order.product.name} '
            f'was confirmed. The dealer has been notified.',
            ntype='payment', reference_id=order.id,
        )
        _notify(
            order.product.dealer,
            'Payment confirmed 💰',
            f'{payment.user.first_name or payment.user.username} paid '
            f'{payment.amount:.2f} FCFA for order #{order.id}.',
            ntype='payment', reference_id=order.id,
        )

    payment.status = 'completed'
    payment.save(update_fields=['status'])
    return payment


@transaction.atomic
def finalize_payment_failed(payment_id, provider_error=''):
    """Mark a payment failed and release its order's reserved stock.

    Stock is released only for an order that is still holding it (pending /
    payment_failed) and never once the order is paid.
    Returns the refreshed payment.
    """
    from .models import Payment

    payment = Payment.objects.select_for_update().get(pk=payment_id)
    if payment.status in ('completed', 'refunded'):
        return payment

    payment.status = 'failed'
    payment.save(update_fields=['status'])

    # Release stock only when the order is actively holding it (pending and a
    # reservation window is set). An already-released order (payment_failed) has
    # reserved_until cleared, so repeated finalize calls never double-release.
    if payment.payment_type == 'order' and payment.order_id \
            and payment.order.payment_status != 'paid':
        from products.models import Order, Product
        order = Order.objects.select_for_update().get(id=payment.order_id)
        if order.status == 'pending' and order.reserved_until is not None:
            Product.objects.select_for_update().get(id_product=order.product_id)
            order.release_stock()
            order.status = 'payment_failed'
            order.save(update_fields=['status', 'reserved_until'])

    reason = f' ({provider_error})' if provider_error else ''
    _notify(
        payment.user,
        'Payment failed',
        f'Your payment of {payment.amount:.2f} FCFA could not be processed{reason}. '
        f'You can retry within the reservation window or cancel the order.',
        ntype='payment', reference_id=payment.order_id or '',
    )
    return payment


@transaction.atomic
def refund_payment(payment_id):
    """Refund a completed, unsettled order payment (admin/platform only).

    Raises ValueError for invalid transitions so callers can map to HTTP errors.
    Reverses escrow, marks the payment refunded, releases stock, notifies.
    """
    from .models import Payment

    payment = Payment.objects.select_for_update().get(pk=payment_id)
    if payment.status != 'completed':
        raise ValueError(
            f'Only completed payments can be refunded (current: {payment.status}).')

    order = payment.order if payment.payment_type == 'order' else None
    if order is not None and order.status == 'delivered':
        raise ValueError(
            'Order already settled to the dealer; refund must be coordinated '
            'offline (dealer clawback).')

    ledger.record_refund(payment, reference=f'payment:{payment.transaction_id}')
    payment.status = 'refunded'
    payment.save(update_fields=['status'])

    if order is not None:
        from products.models import Product
        Product.objects.select_for_update().get(id_product=order.product_id)
        order.release_stock()
        order.payment_status = 'refunded'
        order.status = 'cancelled'
        order.save(update_fields=['payment_status', 'status', 'reserved_until'])

    _notify(payment.user, 'Refund issued',
            f'Your payment of {payment.amount:.2f} FCFA was refunded.',
            ntype='payment', reference_id=order.id if order else '')
    if order is not None:
        _notify(order.product.dealer, 'Order refunded',
                f'Order #{order.id} was refunded and its stock released.',
                ntype='payment', reference_id=order.id)
    return payment

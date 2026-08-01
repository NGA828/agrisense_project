"""Celery tasks for the products app."""

from celery import shared_task


@shared_task
def release_stale_reservations_task():
    """Release stock for orders whose reservation window has lapsed.

    See the management command ``release_stale_reservations`` for the shared
    logic and rationale. Returns the number of orders expired.
    """
    from django.db import transaction
    from django.utils import timezone

    from .models import Order, Product

    now = timezone.now()
    stale = Order.objects.filter(
        status='pending', reserved_until__isnull=False,
        reserved_until__lte=now, payment_status='unpaid',
    ).select_related('product', 'product__dealer')

    released = 0
    for order in stale:
        with transaction.atomic():
            order = Order.objects.select_for_update().get(id=order.id)
            if order.status != 'pending' or order.payment_status == 'paid':
                continue
            product = Product.objects.select_for_update().get(id_product=order.product_id)
            product.stock_quantity += order.quantity
            if product.stock_quantity > 0:
                product.is_available = True
            product.save(update_fields=['stock_quantity', 'is_available'])
            order.reserved_until = None
            order.status = 'expired'
            order.save(update_fields=['status', 'reserved_until'])
        released += 1
        from announcements.models import notify_user
        notify_user(
            order.farmer,
            'Order expired',
            f'Your order of {order.product.name} was cancelled because it was '
            f'not paid in time. The stock has been released.',
            type='order_status', reference_id=order.id,
        )
        notify_user(
            order.product.dealer,
            'Order expired',
            f'Order #{order.id} of {order.product.name} was not paid in time '
            f'and has been cancelled.',
            type='order_status', reference_id=order.id,
        )
        from products.views import _push_stock
        _push_stock(product)
    return released

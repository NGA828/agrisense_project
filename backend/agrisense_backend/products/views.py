from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Product, Order, Review, ProductReport
from .serializers import (ProductSerializer, OrderSerializer, ReviewSerializer,
                          ProductReportSerializer)

VALID_ORDER_STATUSES = ['pending', 'payment_failed', 'confirmed', 'shipped',
                        'delivered', 'cancelled', 'expired']


def _push_stock(product):
    """Broadcast a stock/availability change to the dealer and online farmers.

    Delivers a ``stock_update`` event to the product's dealer (keeps their
    inventory dashboard live) and to the ``all_online`` group (keeps the
    farmer marketplace live). Best-effort; never raises.
    """
    try:
        from realtime.services import send_to_user, send_to_all
        payload = {
            'product_id': product.id_product,
            'stock_quantity': product.stock_quantity,
            'is_available': product.is_available,
        }
        send_to_user(product.dealer_id, 'stock_update', **payload)
        send_to_all('stock_update', **payload)
    except Exception:
        pass


def _release_order_stock_locked(order, product):
    """Return reserved stock to the product (assumes a row lock is held)."""
    product.stock_quantity += order.quantity
    if product.stock_quantity > 0:
        product.is_available = True
    product.save(update_fields=['stock_quantity', 'is_available'])
    order.reserved_until = None


def _hold_order_stock_locked(order, product):
    """Re-reserve stock for a payment retry (assumes a row lock is held)."""
    if product.stock_quantity < order.quantity:
        raise ValueError(f'Insufficient stock. Only {product.stock_quantity} left.')
    product.stock_quantity -= order.quantity
    if product.stock_quantity == 0:
        product.is_available = False
    product.save(update_fields=['stock_quantity', 'is_available'])
    order.reserved_until = timezone.now() + timezone.timedelta(
        minutes=settings.ORDER_RESERVATION_MINUTES)


class ProductViewSet(viewsets.ModelViewSet):
    queryset = Product.objects.all()
    serializer_class = ProductSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'dealer':
            return Product.objects.filter(dealer=user).order_by('-created_at')
        elif user.role == 'admin':
            return Product.objects.all().order_by('-created_at')
        return Product.objects.filter(is_available=True).order_by('-created_at')

    # ── Write authorization ───────────────────────────────────────────
    def create(self, request, *args, **kwargs):
        """Only verified dealers (or admins) may list products."""
        if request.user.role == 'dealer' and not request.user.is_verified:
            return Response({'error': 'Your dealer account is pending verification by an '
                                      'administrator before you can list products.'},
                            status=status.HTTP_403_FORBIDDEN)
        if request.user.role not in ('dealer', 'admin'):
            return Response({'error': 'Dealer or admin only'}, status=status.HTTP_403_FORBIDDEN)
        return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(dealer=self.request.user)

    def update(self, request, *args, partial=False, **kwargs):
        product = self.get_object()
        if product.dealer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        return super().update(request, *args, partial=partial, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)

    def destroy(self, request, *args, **kwargs):
        product = self.get_object()
        if product.dealer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)

    # ── Marketplace ───────────────────────────────────────────────────
    @action(detail=False, methods=['get'])
    def marketplace(self, request):
        """Farmer-facing catalog.

        Ranking (the premium value proposition):
        1. premium verified dealers' products first,
        2. then featured products,
        3. then newest.
        """
        from django.db.models import BooleanField, Case, Q, Value, When
        from django.utils import timezone

        # Premium boost respects the subscription window (unexpired premium;
        # a missing expiry means a lifetime grant, e.g. from seed data).
        premium_boost = Case(
            When(
                Q(dealer__is_premium=True) &
                (Q(dealer__premium_expiry__isnull=True) | Q(dealer__premium_expiry__gt=timezone.now())),
                then=Value(True),
            ),
            default=Value(False),
            output_field=BooleanField(),
        )
        products = (
            Product.objects
            .filter(is_available=True, dealer__role='dealer')
            .select_related('dealer')
            .annotate(premium_boost=premium_boost)
            .order_by('-premium_boost', '-is_featured', '-created_at')
        )

        category = request.query_params.get('category')
        search = request.query_params.get('search')
        dealer = request.query_params.get('dealer')

        if category and category.lower() != 'all':
            products = products.filter(category__iexact=category)
        if search:
            products = products.filter(
                Q(name__icontains=search) | Q(description__icontains=search) |
                Q(dealer__first_name__icontains=search) | Q(dealer__last_name__icontains=search)
            )
        if dealer:
            products = products.filter(dealer_id=dealer)

        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def my_products(self, request):
        if request.user.role != 'dealer':
            return Response({'error': 'Dealer only'}, status=status.HTTP_403_FORBIDDEN)
        products = Product.objects.filter(dealer=request.user).order_by('-created_at')
        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def toggle_availability(self, request, pk=None):
        product = self.get_object()
        if product.dealer != request.user and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        product.is_available = not product.is_available
        product.save(update_fields=['is_available'])
        return Response({'is_available': product.is_available})


class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.all()
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'farmer':
            return Order.objects.filter(farmer=user).select_related('product', 'farmer').order_by('-created_at')
        elif user.role == 'dealer':
            return Order.objects.filter(product__dealer=user).select_related('product', 'farmer').order_by('-created_at')
        return Order.objects.all().select_related('product', 'farmer').order_by('-created_at')

    def create(self, request, *args, **kwargs):
        """Farmer places an order. Stock is decremented atomically."""
        if request.user.role != 'farmer':
            return Response({'error': 'Only farmers can place orders'},
                            status=status.HTTP_403_FORBIDDEN)

        try:
            product_id = int(request.data.get('product'))
            quantity = int(request.data.get('quantity', 1))
        except (TypeError, ValueError):
            return Response({'error': 'product (id) and quantity (int) are required'},
                            status=status.HTTP_400_BAD_REQUEST)
        if quantity <= 0:
            return Response({'error': 'Quantity must be at least 1'}, status=status.HTTP_400_BAD_REQUEST)
        if quantity > 50:
            return Response({'error': 'Maximum 50 units per order'}, status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            product = Product.objects.select_for_update().filter(id_product=product_id).first()
            if not product:
                return Response({'error': 'Product not found'}, status=status.HTTP_404_NOT_FOUND)
            if not product.is_available:
                return Response({'error': f'"{product.name}" is currently unavailable'},
                                status=status.HTTP_400_BAD_REQUEST)
            if product.stock_quantity < quantity:
                return Response({'error': f'Insufficient stock. Only {product.stock_quantity} left.'},
                                status=status.HTTP_400_BAD_REQUEST)

            total_price = product.price * quantity
            product.stock_quantity -= quantity
            if product.stock_quantity == 0:
                product.is_available = False
            product.save(update_fields=['stock_quantity', 'is_available'])

            order = Order.objects.create(
                farmer=request.user,
                product=product,
                quantity=quantity,
                total_price=total_price,
                shipping_address=str(request.data.get('shipping_address') or ''),
                payment_method=str(request.data.get('payment_method') or ''),
                reserved_until=timezone.now() + timezone.timedelta(
                    minutes=settings.ORDER_RESERVATION_MINUTES),
            )

        # Real-time order notification for the dealer (surfaced in-app).
        from announcements.models import notify_user
        notify_user(
            product.dealer,
            'New order received 🎉',
            f'{request.user.first_name or request.user.username} ordered {quantity} x '
            f'{product.name} ({total_price:.2f} FCFA).',
            type='order',
            reference_id=order.id,
        )
        # Live stock push so the marketplace + dealer inventory update instantly.
        _push_stock(product)

        serializer = self.get_serializer(order)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        """Cancel an unpaid (pending / payment_failed / expired) order.

        Allowed for the order's farmer, the product's dealer, or an admin.
        Stock reserved for the order is returned to the product. Paid orders
        cannot be cancelled here — they go through the refund workflow instead.
        """
        order = self.get_object()
        if (order.farmer_id != request.user.id
                and order.product.dealer_id != request.user.id
                and request.user.role != 'admin'):
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        if order.payment_status == 'paid':
            return Response(
                {'error': 'This order is already paid. Cancel it via the refund workflow.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if order.status not in Order.CANCEL_NO_REFUND_STATUSES:
            return Response(
                {'error': f'Order is {order.status} and cannot be cancelled.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        with transaction.atomic():
            order = Order.objects.select_for_update().get(id=order.id)
            if order.status not in Order.CANCEL_NO_REFUND_STATUSES:
                return Response(
                    {'error': f'Order is {order.status} and cannot be cancelled.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            product = Product.objects.select_for_update().get(id_product=order.product_id)
            _release_order_stock_locked(order, product)
            order.status = 'cancelled'
            order.save(update_fields=['status', 'reserved_until'])

        from announcements.models import notify_user
        dealer = order.product.dealer
        if order.farmer_id != request.user.id:
            notify_user(order.farmer, 'Order cancelled',
                        f'Your order of {order.product.name} was cancelled.',
                        type='order_status', reference_id=order.id)
        if dealer.id != request.user.id:
            notify_user(dealer, 'Order cancelled',
                        f'Order #{order.id} of {order.product.name} was cancelled '
                        f'and stock released.',
                        type='order_status', reference_id=order.id)
        _push_stock(product)

        return Response({'status': 'cancelled',
                         'message': 'Order cancelled and stock released.'})

    @action(detail=True, methods=['post'])
    def update_status(self, request, pk=None):
        """Dealer/admin moves a (paid) order through fulfilment.

        Allowed transitions (validated so an order cannot regress):
            confirmed -> shipped -> delivered
            delivered  → triggers settlement (funds released to the dealer).
        Unpaid orders are cancelled via the dedicated ``cancel`` / refund flows.
        """
        order = self.get_object()
        if order.product.dealer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        new_status = request.data.get('status')
        if new_status not in VALID_ORDER_STATUSES:
            return Response({'error': f'Invalid status. Must be one of: {VALID_ORDER_STATUSES}'},
                            status=status.HTTP_400_BAD_REQUEST)

        # Only the fulfilment/cancel transitions are dealer-driven.
        if new_status not in ('shipped', 'delivered', 'cancelled'):
            return Response(
                {'error': f'"{new_status}" cannot be set directly. Use the dedicated flows.'},
                status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            order = Order.objects.select_for_update().get(id=order.id)

            # Fulfilment path requires the order to be paid and to move forward.
            if new_status in ('shipped', 'delivered'):
                if order.payment_status != 'paid':
                    return Response(
                        {'error': 'This order is not paid yet; it cannot be shipped or delivered.'},
                        status=status.HTTP_400_BAD_REQUEST)
                allowed_from = {'shipped': {'confirmed'}, 'delivered': {'shipped', 'confirmed'}}
                if order.status not in allowed_from[new_status]:
                    return Response(
                        {'error': f'Cannot move from "{order.status}" to "{new_status}".'},
                        status=status.HTTP_400_BAD_REQUEST)

            if new_status == 'cancelled':
                # Cancellation of an unpaid order restores stock.
                if order.payment_status == 'paid':
                    return Response(
                        {'error': 'Paid orders must be cancelled through the refund workflow.'},
                        status=status.HTTP_400_BAD_REQUEST)
                if order.status not in Order.CANCEL_NO_REFUND_STATUSES:
                    return Response({'error': f'Order is {order.status} and cannot be cancelled.'},
                                    status=status.HTTP_400_BAD_REQUEST)
                product = Product.objects.select_for_update().get(id_product=order.product_id)
                _release_order_stock_locked(order, product)

            if new_status == 'delivered':
                # Settles funds to the dealer exactly once (idempotent).
                order.mark_delivered()
            else:
                order.status = new_status
                order.save(update_fields=['status', 'reserved_until'])
            released_product = product if new_status == 'cancelled' else None

        if released_product is not None:
            _push_stock(released_product)

        from announcements.models import notify_user
        notify_user(
            order.farmer,
            'Order status updated',
            f'Your order of {order.product.name} is now "{new_status}".',
            type='order_status',
            reference_id=order.id,
        )

        return Response({'status': order.status, 'message': f'Order status updated to {new_status}'})

    @action(detail=False, methods=['get'])
    def order_history(self, request):
        orders = self.get_queryset()
        serializer = self.get_serializer(orders, many=True)
        return Response(serializer.data)


class ReviewViewSet(viewsets.ModelViewSet):
    """Farmer reviews of products (one per farmer+product, verified purchase)."""

    queryset = Review.objects.select_related('product', 'farmer')
    serializer_class = ReviewSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        qs = Review.objects.select_related('product', 'farmer')
        product = self.request.query_params.get('product')
        if product:
            qs = qs.filter(product_id=product)
        return qs

    def create(self, request, *args, **kwargs):
        """A farmer may review a product they have actually purchased."""
        if request.user.role != 'farmer':
            return Response({'error': 'Only farmers can leave reviews'},
                            status=status.HTTP_403_FORBIDDEN)

        product_id = request.data.get('product')
        if not product_id:
            return Response({'error': 'product is required'}, status=status.HTTP_400_BAD_REQUEST)

        from .models import Order
        purchased = Order.objects.filter(
            farmer=request.user, product_id=product_id,
            payment_status='paid', status__in=['delivered', 'shipped', 'confirmed'],
        ).exists()
        if not purchased:
            return Response(
                {'error': 'You can only review a product you have purchased and paid for.'},
                status=status.HTTP_400_BAD_REQUEST)

        if Review.objects.filter(product_id=product_id, farmer=request.user).exists():
            return Response({'error': 'You have already reviewed this product.'},
                            status=status.HTTP_400_BAD_REQUEST)

        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(farmer=request.user)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    def update(self, request, *args, partial=False, **kwargs):
        review = self.get_object()
        if review.farmer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        return super().update(request, *args, partial=partial, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)

    def destroy(self, request, *args, **kwargs):
        review = self.get_object()
        if review.farmer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)


class ProductReportViewSet(viewsets.ModelViewSet):
    """Product reporting (any user) + admin moderation queue."""

    queryset = ProductReport.objects.select_related('product', 'reporter')
    serializer_class = ProductReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            qs = ProductReport.objects.all()
            status_filter = self.request.query_params.get('status')
            if status_filter:
                qs = qs.filter(status=status_filter)
            return qs
        # Non-admins see only their own reports.
        return ProductReport.objects.filter(reporter=user)

    def create(self, request, *args, **kwargs):
        product_id = request.data.get('product')
        if not product_id:
            return Response({'error': 'product is required'}, status=status.HTTP_400_BAD_REQUEST)
        reason = str(request.data.get('reason') or '').strip()
        if not reason:
            return Response({'error': 'reason is required'}, status=status.HTTP_400_BAD_REQUEST)
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        serializer.save(reporter=request.user, status='pending')
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def resolve(self, request, pk=None):
        """Admin resolves a report: dismissed or removed (product hidden)."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

        report = self.get_object()
        decision = str(request.data.get('decision') or '').lower()
        if decision not in ('dismissed', 'removed'):
            return Response({'error': "decision must be 'dismissed' or 'removed'"},
                            status=status.HTTP_400_BAD_REQUEST)

        report.status = 'removed' if decision == 'removed' else 'dismissed'
        report.save(update_fields=['status'])

        if decision == 'removed':
            # Hide the product from the marketplace (soft takedown).
            product = report.product
            product.is_available = False
            product.save(update_fields=['is_available'])
            _push_stock(product)

        from auditlog.services import log_action
        log_action(
            request.user, 'resolve_report', category='product',
            target_type='report', target_id=report.id,
            description=f'{decision} report for product "{report.product.name}"',
            metadata={'decision': decision, 'product_id': report.product_id},
            request=request,
        )

        return Response({'status': report.status, 'message': f'Report {report.status}.'})

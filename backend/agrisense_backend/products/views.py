from django.db import transaction
from django.db.models import Q
from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Product, Order
from .serializers import ProductSerializer, OrderSerializer

VALID_ORDER_STATUSES = ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled']


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

        serializer = self.get_serializer(order)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

    @action(detail=True, methods=['post'])
    def update_status(self, request, pk=None):
        """Dealer updates order status (and can cancel, restoring stock)."""
        order = self.get_object()
        if order.product.dealer_id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        new_status = request.data.get('status')
        if new_status not in VALID_ORDER_STATUSES:
            return Response({'error': f'Invalid status. Must be one of: {VALID_ORDER_STATUSES}'},
                            status=status.HTTP_400_BAD_REQUEST)

        with transaction.atomic():
            order = Order.objects.select_for_update().get(id=order.id)
            if order.status == 'cancelled':
                return Response({'error': 'Order is already cancelled'},
                                status=status.HTTP_400_BAD_REQUEST)

            if new_status == 'cancelled' and order.status != 'cancelled':
                # Restore stock when an order is cancelled before fulfilment.
                product = Product.objects.select_for_update().get(id_product=order.product_id)
                product.stock_quantity += order.quantity
                if product.stock_quantity > 0:
                    product.is_available = True
                product.save(update_fields=['stock_quantity', 'is_available'])

            order.status = new_status
            order.save(update_fields=['status'])

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

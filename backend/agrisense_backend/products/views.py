from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import Product, Order
from .serializers import ProductSerializer, OrderSerializer


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

    @action(detail=False, methods=['get'])
    def marketplace(self, request):
        """Public marketplace for farmers"""
        products = Product.objects.filter(is_available=True, dealer__role='dealer')
        category = request.query_params.get('category')
        search = request.query_params.get('search')

        if category and category != 'All':
            products = products.filter(category__icontains=category.lower())
        if search:
            products = products.filter(name__icontains=search)

        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def my_products(self, request):
        """Get products for the current dealer"""
        if request.user.role != 'dealer':
            return Response({'error': 'Dealer only'}, status=status.HTTP_403_FORBIDDEN)
        products = Product.objects.filter(dealer=request.user).order_by('-created_at')
        serializer = self.get_serializer(products, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def toggle_availability(self, request, pk=None):
        """Toggle product availability"""
        product = self.get_object()
        if product.dealer != request.user and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)
        product.is_available = not product.is_available
        product.save()
        return Response({'is_available': product.is_available})

    def perform_update(self, serializer):
        product = self.get_object()
        if product.dealer != self.request.user and self.request.user.role != 'admin':
            raise permissions.PermissionDenied('Not authorized')
        serializer.save()


class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.all()
    serializer_class = OrderSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'farmer':
            return Order.objects.filter(farmer=user).order_by('-created_at')
        elif user.role == 'dealer':
            return Order.objects.filter(product__dealer=user).order_by('-created_at')
        return Order.objects.all().order_by('-created_at')

    def perform_create(self, serializer):
        product = serializer.validated_data['product']
        quantity = serializer.validated_data['quantity']
        total_price = product.price * quantity

        # Reduce stock
        product.stock_quantity = max(0, product.stock_quantity - quantity)
        if product.stock_quantity == 0:
            product.is_available = False
        product.save()

        serializer.save(
            farmer=self.request.user,
            total_price=total_price
        )

    @action(detail=True, methods=['post'])
    def update_status(self, request, pk=None):
        """Dealer updates order status"""
        order = self.get_object()
        if order.product.dealer != request.user and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        new_status = request.data.get('status')
        valid_statuses = ['pending', 'confirmed', 'shipped', 'delivered', 'cancelled']
        if new_status not in valid_statuses:
            return Response({'error': f'Invalid status. Must be one of: {valid_statuses}'},
                          status=status.HTTP_400_BAD_REQUEST)

        order.status = new_status
        order.save()
        return Response({'status': order.status, 'message': f'Order status updated to {new_status}'})

    @action(detail=False, methods=['get'])
    def order_history(self, request):
        """Get order history for the current user"""
        orders = self.get_queryset()
        serializer = self.get_serializer(orders, many=True)
        return Response(serializer.data)

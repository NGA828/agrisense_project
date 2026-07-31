from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action, api_view, permission_classes
from .models import User
from .serializers import UserSerializer, FarmerSerializer, DealerSerializer


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def register_view(request):
    data = request.data
    required = ['username', 'password', 'first_name', 'last_name', 'email', 'phone_number']
    for field in required:
        if field not in data:
            return Response({'error': f'{field} is required'}, status=status.HTTP_400_BAD_REQUEST)

    if User.objects.filter(username=data['username']).exists():
        return Response({'error': 'Username already exists'}, status=status.HTTP_400_BAD_REQUEST)

    if User.objects.filter(email=data['email']).exists():
        return Response({'error': 'Email already exists'}, status=status.HTTP_400_BAD_REQUEST)

    user = User.objects.create_user(
        username=data['username'],
        password=data['password'],
        first_name=data['first_name'],
        last_name=data['last_name'],
        email=data['email'],
        phone_number=data['phone_number'],
        role=data.get('role', 'farmer'),
    )
    return Response({'message': 'User created successfully'}, status=status.HTTP_201_CREATED)


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return User.objects.all().order_by('-date_joined')
        return User.objects.filter(id=user.id)

    @action(detail=False, methods=['get'])
    def me(self, request):
        serializer = UserSerializer(request.user)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def farmers(self, request):
        farmers = User.objects.filter(role='farmer').order_by('-date_joined')
        serializer = FarmerSerializer(farmers, many=True)
        return Response(serializer.data)

    @action(detail=False, methods=['get'])
    def dealers(self, request):
        dealers = User.objects.filter(role='dealer').order_by('-date_joined')
        serializer = DealerSerializer(dealers, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def suspend(self, request, pk=None):
        """Admin can suspend a user"""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        user.is_active = False
        user.save()
        return Response({'message': f'User {user.username} has been suspended'})

    @action(detail=True, methods=['post'])
    def activate(self, request, pk=None):
        """Admin can activate a suspended user"""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        user.is_active = True
        user.save()
        return Response({'message': f'User {user.username} has been activated'})

    @action(detail=True, methods=['post'])
    def verify_dealer(self, request, pk=None):
        """Admin can verify a dealer application"""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        if user.role != 'dealer':
            return Response({'error': 'User is not a dealer'}, status=status.HTTP_400_BAD_REQUEST)
        approve = request.data.get('approve', True)
        user.is_verified = approve
        user.save()
        return Response({'message': f'Dealer {user.username} {"verified" if approve else "rejected"}', 'is_verified': user.is_verified})

    @action(detail=True, methods=['post'])
    def upgrade_premium(self, request, pk=None):
        """Dealer can upgrade to premium"""
        if request.user.role != 'dealer' and request.user.role != 'admin':
            return Response({'error': 'Dealer or Admin only'}, status=status.HTTP_403_FORBIDDEN)
        
        user = self.get_object()
        if user.role != 'dealer':
            return Response({'error': 'Only dealers can be premium'}, status=status.HTTP_400_BAD_REQUEST)
        
        from datetime import datetime, timedelta
        duration_months = request.data.get('duration_months', 1)
        user.is_premium = True
        user.premium_expiry = datetime.now() + timedelta(days=30 * duration_months)
        user.save()
        
        return Response({
            'message': f'User {user.username} upgraded to premium for {duration_months} month(s)',
            'premium_expiry': user.premium_expiry
        })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_stats(request):
    """Admin dashboard statistics"""
    if request.user.role != 'admin':
        return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

    from products.models import Product, Order
    from diagnosis.models import Diagnosis
    from payments.models import Payment
    from chat.models import ChatRoom

    total_farmers = User.objects.filter(role='farmer').count()
    total_dealers = User.objects.filter(role='dealer').count()
    total_users = User.objects.filter(role__in=['farmer', 'dealer']).count()
    total_products = Product.objects.count()
    total_orders = Order.objects.count()
    total_diagnoses = Diagnosis.objects.count()
    total_payments = Payment.objects.count()
    total_revenue = sum(p.amount for p in Payment.objects.filter(status='completed'))
    total_chats = ChatRoom.objects.count()
    active_users = User.objects.filter(is_active=True, role__in=['farmer', 'dealer']).count()
    suspended_users = User.objects.filter(is_active=False).count()

    # Recent orders
    recent_orders = Order.objects.select_related('farmer', 'product').order_by('-created_at')[:10]
    recent_orders_data = [{
        'id': o.id,
        'farmer': f'{o.farmer.first_name} {o.farmer.last_name}',
        'product': o.product.name,
        'amount': float(o.total_price),
        'status': o.status,
        'date': o.created_at.strftime('%Y-%m-%d'),
    } for o in recent_orders]

    return Response({
        'total_users': total_users,
        'total_farmers': total_farmers,
        'total_dealers': total_dealers,
        'total_products': total_products,
        'total_orders': total_orders,
        'total_diagnoses': total_diagnoses,
        'total_payments': total_payments,
        'total_revenue': float(total_revenue),
        'total_chats': total_chats,
        'active_users': active_users,
        'suspended_users': suspended_users,
        'recent_orders': recent_orders_data,
    })

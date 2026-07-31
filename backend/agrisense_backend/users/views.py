from datetime import datetime, timedelta

from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db.models import Count, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action, api_view, permission_classes, throttle_classes
from rest_framework.throttling import ScopedRateThrottle

from .models import User
from .serializers import UserSerializer, FarmerSerializer, DealerSerializer

# Roles that may be self-assigned at registration. Administrators can only be
# created by an existing admin (or via `createsuperuser`).
SELF_REGISTERABLE_ROLES = ('farmer', 'dealer')


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
@throttle_classes([ScopedRateThrottle])
def register_view(request):
    """Register a farmer or dealer account. Admins cannot self-register."""
    data = request.data
    required = ['username', 'password', 'first_name', 'last_name', 'email', 'phone_number']
    for field in required:
        if field not in data or not str(data[field]).strip():
            return Response({'error': f'{field} is required'}, status=status.HTTP_400_BAD_REQUEST)

    role = data.get('role', 'farmer')
    if role not in SELF_REGISTERABLE_ROLES:
        return Response(
            {'error': "Only 'farmer' or 'dealer' roles can self-register. "
                      "Administrator accounts are provisioned by platform staff."},
            status=status.HTTP_400_BAD_REQUEST,
        )

    if User.objects.filter(username=data['username']).exists():
        return Response({'error': 'Username already exists'}, status=status.HTTP_400_BAD_REQUEST)

    if User.objects.filter(email=data['email']).exists():
        return Response({'error': 'Email already exists'}, status=status.HTTP_400_BAD_REQUEST)

    # Enforce Django password policy at registration time.
    try:
        validate_password(data['password'])
    except ValidationError as exc:
        return Response({'error': 'Weak password', 'details': list(exc.messages)},
                        status=status.HTTP_400_BAD_REQUEST)

    # Dealer accounts start unverified and must be approved by an admin.
    user = User.objects.create_user(
        username=data['username'],
        password=data['password'],
        first_name=data['first_name'],
        last_name=data['last_name'],
        email=data['email'],
        phone_number=data['phone_number'],
        role=role,
        is_verified=False,
    )
    return Response({
        'message': 'Account created successfully',
        'role': user.role,
        'is_verified': user.is_verified,
        'note': 'Dealer accounts require admin verification before listing products.' if role == 'dealer' else '',
    }, status=status.HTTP_201_CREATED)


class UserViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    serializer_class = UserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if user.role == 'admin':
            return User.objects.all().order_by('-date_joined')
        return User.objects.filter(id=user.id)

    # ── Write protection ──────────────────────────────────────────────
    def create(self, request, *args, **kwargs):
        """Only admins may create users through the API (registration is separate)."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        return super().create(request, *args, **kwargs)

    def update(self, request, *args, partial=False, **kwargs):
        """Users may update their own profile; only admins may change role/privileges."""
        user = self.get_object()
        if user.id != request.user.id and request.user.role != 'admin':
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        privileged = {'role', 'is_staff', 'is_superuser', 'is_verified', 'is_active',
                      'is_premium', 'premium_expiry'}
        if request.user.role != 'admin' and privileged.intersection(request.data.keys()):
            return Response({'error': 'Changing privileged fields requires admin rights'},
                            status=status.HTTP_403_FORBIDDEN)
        return super().update(request, *args, partial=partial, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        return self.update(request, *args, partial=True, **kwargs)

    def destroy(self, request, *args, **kwargs):
        """Only admins may delete accounts (fraud moderation)."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        return super().destroy(request, *args, **kwargs)

    # ── Reads ─────────────────────────────────────────────────────────
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

    @action(detail=False, methods=['get'])
    def dealer_requests(self, request):
        """Pending dealer verification queue (admin only)."""
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        dealers = User.objects.filter(role='dealer', is_verified=False).order_by('date_joined')
        serializer = DealerSerializer(dealers, many=True)
        return Response(serializer.data)

    # ── Moderation (admin only) ───────────────────────────────────────
    @action(detail=True, methods=['post'])
    def suspend(self, request, pk=None):
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        user.is_active = False
        user.save(update_fields=['is_active'])
        return Response({'message': f'User {user.username} has been suspended'})

    @action(detail=True, methods=['post'])
    def activate(self, request, pk=None):
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        user.is_active = True
        user.save(update_fields=['is_active'])
        return Response({'message': f'User {user.username} has been activated'})

    @action(detail=True, methods=['post'])
    def verify_dealer(self, request, pk=None):
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        if user.role != 'dealer':
            return Response({'error': 'User is not a dealer'}, status=status.HTTP_400_BAD_REQUEST)
        approve = request.data.get('approve', True)
        if isinstance(approve, str):
            approve = approve.lower() in ('1', 'true', 'yes')
        user.is_verified = approve
        user.save(update_fields=['is_verified'])
        return Response({
            'message': f'Dealer {user.username} {"verified" if approve else "rejected"}',
            'is_verified': user.is_verified,
        })

    @action(detail=True, methods=['post'])
    def upgrade_premium(self, request, pk=None):
        """Dealer upgrades to premium (duration in months).

        Requires an associated completed payment unless the caller is an admin
        (admin can grant premium directly). The payment is created with the
        premium subscription package price and must be processed to take effect.
        """
        user = self.get_object()
        if user.role != 'dealer':
            return Response({'error': 'Only dealers can be premium'}, status=status.HTTP_400_BAD_REQUEST)

        is_admin = request.user.role == 'admin'
        if request.user.role != 'admin' and request.user.id != user.id:
            return Response({'error': 'Not authorized'}, status=status.HTTP_403_FORBIDDEN)

        try:
            duration_months = int(request.data.get('duration_months', 1))
        except (TypeError, ValueError):
            return Response({'error': 'duration_months must be an integer'},
                            status=status.HTTP_400_BAD_REQUEST)
        if duration_months < 1 or duration_months > 12:
            return Response({'error': 'duration_months must be between 1 and 12'},
                            status=status.HTTP_400_BAD_REQUEST)

        from payments.models import Payment
        from payments.gateway import PREMIUM_PRICE_PER_MONTH

        # Direct grant by admin: no payment required.
        if is_admin and request.data.get('skip_payment', False):
            user.is_premium = True
            user.premium_expiry = timezone.now() + timedelta(days=30 * duration_months)
            user.save(update_fields=['is_premium', 'premium_expiry'])
            return Response({
                'message': f'{user.username} upgraded to premium for {duration_months} month(s)',
                'premium_expiry': user.premium_expiry,
            })

        # Self-service: create a payment that must be processed before premium
        # becomes active. `activate_premium` is idempotent and safe to re-call.
        total = PREMIUM_PRICE_PER_MONTH * duration_months
        phone = str(request.data.get('phone_number') or '').strip() or user.phone_number or ''
        payment, created = Payment.objects.get_or_create(
            user=user,
            order=None,
            payment_method='MTN_MOMO',
            status='pending',
            description=f'Premium dealer subscription ({duration_months} month(s))',
            defaults={
                'amount': total,
                'phone_number': phone,
                'transaction_id': f'PREM-{user.id}-{timezone.now().strftime("%Y%m%d%H%M%S")}',
                'payment_type': 'premium',
            },
        )
        if created:
            payment.save()

        return Response({
            'message': f'Premium upgrade initiated. Complete the payment of {total} FCFA to activate.',
            'payment_id': payment.id,
            'amount': float(total),
            'status': 'payment_required',
            'activate_premium': True,
        })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_stats(request):
    """Admin dashboard headline statistics."""
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
    total_revenue = Payment.objects.filter(status='completed').aggregate(total=Sum('amount'))['total'] or 0
    total_chats = ChatRoom.objects.count()
    active_users = User.objects.filter(is_active=True, role__in=['farmer', 'dealer']).count()
    suspended_users = User.objects.filter(is_active=False).count()
    pending_dealer_requests = User.objects.filter(role='dealer', is_verified=False).count()
    premium_dealers = User.objects.filter(role='dealer', is_premium=True).count()
    low_stock_products = Product.objects.filter(stock_quantity__lte=5).count()

    recent_orders = Order.objects.select_related('farmer', 'product').order_by('-created_at')[:10]
    recent_orders_data = [{
        'id': o.id,
        'farmer': f'{o.farmer.first_name} {o.farmer.last_name}',
        'farmer_phone': o.farmer.phone_number,
        'product': o.product.name,
        'quantity': o.quantity,
        'amount': float(o.total_price),
        'status': o.status,
        'payment_status': o.payment_status,
        'date': o.created_at.strftime('%Y-%m-%d %H:%M'),
    } for o in recent_orders]

    recent_diagnoses = Diagnosis.objects.select_related('user').order_by('-created_at')[:5]
    recent_diagnoses_data = [{
        'id': d.id,
        'crop': d.crop_type,
        'disease': d.disease_name,
        'confidence': float(d.confidence),
        'user': f'{d.user.first_name} {d.user.last_name}',
        'date': d.created_at.strftime('%Y-%m-%d %H:%M'),
    } for d in recent_diagnoses]

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
        'pending_dealer_requests': pending_dealer_requests,
        'premium_dealers': premium_dealers,
        'low_stock_products': low_stock_products,
        'recent_orders': recent_orders_data,
        'recent_diagnoses': recent_diagnoses_data,
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_analytics(request):
    """Time-series analytics for the admin dashboard charts.

    Query params:
        period: 7d | 30d | 90d | 1y   (default 30d)
    Returns daily aggregates for user growth, orders/revenue, and diagnoses,
    plus top-selling products and top dealers.
    """
    if request.user.role != 'admin':
        return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

    from products.models import Product, Order
    from diagnosis.models import Diagnosis
    from payments.models import Payment

    period = request.query_params.get('period', '30d')
    days = {'7d': 7, '30d': 30, '90d': 90, '1y': 365}.get(period, 30)
    since = timezone.now() - timedelta(days=days)

    def series(queryset, value=None):
        qs = queryset.filter(created_at__gte=since).annotate(day=TruncDate('created_at'))
        if value:
            # annotate AFTER values() so the aggregation survives the field projection.
            qs = qs.values('day').annotate(total=Sum(value)).order_by('day')
            return {str(item['day']): float(item['total'] or 0) for item in qs}
        qs = qs.values('day').annotate(count=Count('id')).order_by('day')
        return {str(item['day']): item['count'] for item in qs}

    user_growth = series(User.objects.filter(role__in=['farmer', 'dealer']))
    diagnoses = series(Diagnosis.objects.all())
    order_volume = series(Order.objects.all(), 'total_price')
    revenue = series(Payment.objects.filter(status='completed'), 'amount')

    top_products = (
        Order.objects.filter(created_at__gte=since)
        .values('product__id_product', 'product__name')
        .annotate(units=Sum('quantity'), revenue=Sum('total_price'))
        .order_by('-revenue')[:10]
    )
    top_dealers = (
        Order.objects.filter(created_at__gte=since)
        .values('product__dealer__id', 'product__dealer__first_name', 'product__dealer__last_name')
        .annotate(orders=Count('id'), revenue=Sum('total_price'))
        .order_by('-revenue')[:10]
    )

    return Response({
        'period': period,
        'days': days,
        'user_growth': user_growth,
        'diagnoses': diagnoses,
        'order_volume': order_volume,
        'revenue': revenue,
        'top_products': [
            {'id': p['product__id_product'], 'name': p['product__name'],
             'units': p['units'], 'revenue': float(p['revenue'] or 0)}
            for p in top_products
        ],
        'top_dealers': [
            {'id': d['product__dealer__id'],
             'name': f"{d['product__dealer__first_name']} {d['product__dealer__last_name']}",
             'orders': d['orders'], 'revenue': float(d['revenue'] or 0)}
            for d in top_dealers
        ],
    })

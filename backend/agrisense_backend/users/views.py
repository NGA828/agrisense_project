from datetime import datetime, timedelta

from django.conf import settings
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db.models import Count, Sum
from django.db.models.functions import TruncDate
from django.utils import timezone
from rest_framework import viewsets, status, permissions
from rest_framework.response import Response
from rest_framework.decorators import action, api_view, permission_classes, throttle_classes
from rest_framework.throttling import ScopedRateThrottle
from django.db.models import Q as models_Q

from .models import User
from .serializers import UserSerializer, FarmerSerializer, DealerSerializer

# Roles that may be self-assigned at registration. Administrators can only be
# created by an existing admin (or via `createsuperuser`).
SELF_REGISTERABLE_ROLES = ('farmer', 'dealer')


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
@throttle_classes([ScopedRateThrottle])
def request_otp(request):
    """Request a one-time-password for a phone number (registration / reset).

    Body: {phone_number, purpose: 'register'|'password_reset'}
    Returns ``debug_code`` (the plaintext code) ONLY when DEBUG is on.
    """
    from .otp_service import send_otp

    phone = str(request.data.get('phone_number') or '').strip()
    purpose = str(request.data.get('purpose') or 'register').lower()
    if purpose not in ('register', 'password_reset'):
        return Response({'error': "purpose must be 'register' or 'password_reset'"},
                        status=status.HTTP_400_BAD_REQUEST)
    if len(phone) < 7:
        return Response({'error': 'A valid phone number is required'},
                        status=status.HTTP_400_BAD_REQUEST)

    code = send_otp(phone, purpose)
    resp = {'message': 'Verification code sent to your phone.'}
    if code is not None:
        resp['debug_code'] = code  # DEBUG only (dev/demo)
    return Response(resp, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
@throttle_classes([ScopedRateThrottle])
def verify_otp_view(request):
    """Verify an OTP code. Body: {phone_number, purpose, code}."""
    from .otp_service import verify_otp

    phone = str(request.data.get('phone_number') or '').strip()
    purpose = str(request.data.get('purpose') or 'register').lower()
    code = str(request.data.get('code') or '').strip()
    if not phone or not code:
        return Response({'error': 'phone_number and code are required'},
                        status=status.HTTP_400_BAD_REQUEST)

    ok, error = verify_otp(phone, purpose, code)
    if not ok:
        return Response({'error': error}, status=status.HTTP_400_BAD_REQUEST)
    return Response({'message': 'Verified successfully.'})


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

    # Optional phone OTP verification before creating the account.
    if settings.OTP_REQUIRED_FOR_REGISTRATION:
        from .otp_service import verify_otp
        ok, error = verify_otp(data['phone_number'], 'register', data.get('otp_code', ''))
        if not ok:
            return Response({'error': error}, status=status.HTTP_400_BAD_REQUEST)

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
        user = self.get_object()
        from auditlog.services import log_action
        log_action(request.user, 'delete_user', target_type='user', target_id=user.id,
                   description=f'Deleted account {user.username}',
                   metadata={'email': user.email}, request=request)
        return super().destroy(request, *args, **kwargs)

    # ── Reads / self-service update ───────────────────────────────────
    @action(detail=False, methods=['get', 'patch', 'put'])
    def me(self, request):
        """Current profile. GET returns it; PATCH/PUT update it.

        PATCH (and PUT) must be accepted here because the mobile clients
        call ``PATCH /api/users/me/`` (multipart) to upload a profile photo.
        Before this fix the action only allowed GET, so profile-picture
        uploads failed with HTTP 405.
        """
        if request.method in ('PATCH', 'PUT'):
            privileged = {'role', 'is_staff', 'is_superuser', 'is_verified', 'is_active',
                          'is_premium', 'premium_expiry'}
            if request.user.role != 'admin' and privileged.intersection(request.data.keys()):
                return Response({'error': 'Changing privileged fields requires admin rights'},
                                status=status.HTTP_403_FORBIDDEN)
            serializer = UserSerializer(
                request.user,
                data=request.data,
                partial=(request.method == 'PATCH'),
            )
            serializer.is_valid(raise_exception=True)
            serializer.save()
            return Response(serializer.data)
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
        from auditlog.services import log_action
        log_action(request.user, 'suspend_user', target_type='user', target_id=user.id,
                   description=f'Suspended account {user.username}',
                   metadata={'reason': request.data.get('reason', '')}, request=request)
        return Response({'message': f'User {user.username} has been suspended'})

    @action(detail=True, methods=['post'])
    def activate(self, request, pk=None):
        if request.user.role != 'admin':
            return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)
        user = self.get_object()
        user.is_active = True
        user.save(update_fields=['is_active'])
        from auditlog.services import log_action
        log_action(request.user, 'activate_user', target_type='user', target_id=user.id,
                   description=f'Reactivated account {user.username}', request=request)
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
        from auditlog.services import log_action
        log_action(request.user, 'verify_dealer', target_type='user', target_id=user.id,
                   description=f'{"Verified" if approve else "Rejected"} dealer {user.username}',
                   metadata={'approve': approve}, request=request)
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
            from auditlog.services import log_action
            log_action(request.user, 'grant_premium', target_type='user', target_id=user.id,
                       description=f'Granted premium to {user.username} for {duration_months} month(s)',
                       metadata={'duration_months': duration_months, 'skip_payment': True},
                       request=request)
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


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
@throttle_classes([ScopedRateThrottle])
def password_reset_view(request):
    """Self-service password reset verified by the registered phone number.

    Body: {username, phone_number, new_password}
    This mirrors real-world flows in the region where the SIM-linked mobile
    number is the recovery channel (no e-mail infrastructure required).
    """
    username = str(request.data.get('username') or '').strip()
    phone = str(request.data.get('phone_number') or '').strip()
    new_password = request.data.get('new_password') or ''

    if not username or not phone or not new_password:
        return Response({'error': 'username, phone_number and new_password are required'},
                        status=status.HTTP_400_BAD_REQUEST)

    try:
        user = User.objects.get(username=username)
    except User.DoesNotExist:
        # Do not leak whether the username exists.
        return Response({'error': 'Verification failed. Check the username and phone number.'},
                        status=status.HTTP_400_BAD_REQUEST)

    # Compare digits only so formatting differences (+237, spaces) don't break it.
    normalized = ''.join(ch for ch in phone if ch.isdigit())
    user_phone = ''.join(ch for ch in (user.phone_number or '') if ch.isdigit())
    if not normalized or normalized != user_phone:
        return Response({'error': 'Verification failed. Check the username and phone number.'},
                        status=status.HTTP_400_BAD_REQUEST)

    # Optional phone OTP verification before resetting the password.
    if settings.OTP_REQUIRED_FOR_PASSWORD_RESET:
        from .otp_service import verify_otp
        ok, error = verify_otp(phone, 'password_reset', request.data.get('otp_code', ''))
        if not ok:
            return Response({'error': error}, status=status.HTTP_400_BAD_REQUEST)

    try:
        validate_password(new_password, user=user)
    except ValidationError as exc:
        return Response({'error': 'Weak password', 'details': list(exc.messages)},
                        status=status.HTTP_400_BAD_REQUEST)

    user.set_password(new_password)
    user.save(update_fields=['password'])
    return Response({'message': 'Password reset successfully. You can now log in.'})


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def dealer_analytics(request):
    """Sales analytics for the authenticated dealer (Phase D).

    Query params:
        period: 7d | 30d | 90d | 1y   (default 30d)
    Returns revenue/order time-series plus top products and recent orders scoped
    to the dealer's own products.
    """
    from products.models import Product, Order

    if request.user.role != 'dealer':
        return Response({'error': 'Dealer only'}, status=status.HTTP_403_FORBIDDEN)

    period = request.query_params.get('period', '30d')
    days = {'7d': 7, '30d': 30, '90d': 90, '1y': 365}.get(period, 30)
    since = timezone.now() - timedelta(days=days)

    my_orders = Order.objects.filter(product__dealer=request.user)

    # Revenue time-series (only paid/fulfilled orders count as revenue).
    revenue_qs = my_orders.filter(
        created_at__gte=since, payment_status='paid',
    ).annotate(day=TruncDate('created_at')).values('day').annotate(
        total=Sum('total_price')).order_by('day')
    revenue = {str(item['day']): float(item['total'] or 0) for item in revenue_qs}

    # Order volume time-series.
    vol_qs = my_orders.filter(created_at__gte=since).annotate(
        day=TruncDate('created_at')).values('day').annotate(count=Count('id')).order_by('day')
    order_volume = {str(item['day']): item['count'] for item in vol_qs}

    # Product-level performance.
    top_products = (
        my_orders.filter(created_at__gte=since)
        .values('product__id_product', 'product__name')
        .annotate(units=Sum('quantity'), revenue=Sum('total_price'))
        .order_by('-revenue')[:10]
    )

    summary = my_orders.aggregate(
        total_orders=Count('id'),
        total_revenue=Sum('total_price', filter=models_Q(payment_status='paid')),
    )

    # Stock health.
    low_stock = Product.objects.filter(dealer=request.user, stock_quantity__lte=5).count()

    recent = my_orders.select_related('farmer', 'product').order_by('-created_at')[:10]
    recent_data = [{
        'id': o.id,
        'farmer': f'{o.farmer.first_name} {o.farmer.last_name}',
        'product': o.product.name,
        'quantity': o.quantity,
        'amount': float(o.total_price),
        'status': o.status,
        'payment_status': o.payment_status,
        'date': o.created_at.strftime('%Y-%m-%d %H:%M'),
    } for o in recent]

    return Response({
        'period': period,
        'days': days,
        'revenue': revenue,
        'order_volume': order_volume,
        'top_products': [
            {'id': p['product__id_product'], 'name': p['product__name'],
             'units': p['units'], 'revenue': float(p['revenue'] or 0)}
            for p in top_products
        ],
        'total_orders': summary['total_orders'] or 0,
        'total_revenue': float(summary['total_revenue'] or 0),
        'low_stock_products': low_stock,
        'recent_orders': recent_data,
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
def admin_regional_analytics(request):
    """Regional disease analytics (admin).

    Aggregates diagnoses geographically so admins can spot outbreak clusters.
    Returns disease counts by crop, by region (bucketed lat/lon grid), and the
    most-affected crops/diseases. Query params:
        period: 7d | 30d | 90d | 1y   (default 90d)
    """
    if request.user.role != 'admin':
        return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

    from diagnosis.models import Diagnosis
    from django.db.models import Count

    period = request.query_params.get('period', '90d')
    days = {'7d': 7, '30d': 30, '90d': 90, '1y': 365}.get(period, 90)
    since = timezone.now() - timedelta(days=days)

    qs = Diagnosis.objects.filter(created_at__gte=since)

    # Disease counts by crop.
    by_crop_rows = qs.values('crop_type', 'disease_name').annotate(
        count=Count('id')).order_by('-count')
    by_crop = {}
    for row in by_crop_rows:
        by_crop.setdefault(row['crop_type'], {})[row['disease_name']] = row['count']

    # Geo clusters: bucket lat/lon onto a ~0.4 degree grid so nearby diagnoses
    # (same village/area) cluster into a single outbreak point.
    grid = {}
    for d in qs.select_related('location').filter(location__isnull=False).iterator():
        if d.location is None:
            continue
        lat = round(d.location.latitude / 0.4) * 0.4
        lon = round(d.location.longitude / 0.4) * 0.4
        key = (lat, lon)
        bucket = grid.setdefault(key, {'lat': lat, 'lon': lon, 'total': 0, 'diseases': {}})
        bucket['total'] += 1
        bucket['diseases'][d.disease_name] = bucket['diseases'].get(d.disease_name, 0) + 1

    geo_points = sorted(
        ({'lat': b['lat'], 'lon': b['lon'], 'total': b['total'],
          'top_disease': max(b['diseases'], key=b['diseases'].get),
          'diseases': b['diseases']} for b in grid.values()),
        key=lambda p: p['total'], reverse=True,
    )[:50]

    return Response({
        'period': period,
        'days': days,
        'total_diagnoses': qs.count(),
        'by_crop': by_crop,
        'geo_points': geo_points,
    })


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def admin_outbreaks(request):
    """Admin outbreak console: list detected outbreak alerts.

    Query params:
        status: active | notified | expired  (default: all)
        q: filter by disease name (optional)
    """
    if request.user.role != 'admin':
        return Response({'error': 'Admin only'}, status=status.HTTP_403_FORBIDDEN)

    from diagnosis.models import OutbreakAlert

    qs = OutbreakAlert.objects.all()
    status_filter = request.query_params.get('status')
    if status_filter:
        qs = qs.filter(status=status_filter)
    search = request.query_params.get('q')
    if search:
        qs = qs.filter(disease_name__icontains=search)

    alerts = [{
        'id': a.id,
        'disease_name': a.disease_name,
        'crop_name': a.crop_name,
        'latitude': a.latitude,
        'longitude': a.longitude,
        'radius_km': a.radius_km,
        'cluster_size': a.cluster_size,
        'previous_size': a.previous_size,
        'notified_users': a.notified_users,
        'status': a.status,
        'cooldown_until': a.cooldown_until,
        'created_at': a.created_at,
    } for a in qs]

    return Response({'count': len(alerts), 'alerts': alerts})


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

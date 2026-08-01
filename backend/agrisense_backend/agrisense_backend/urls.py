from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from users.views import (UserViewSet, register_view, password_reset_view,
                         admin_stats, admin_analytics, admin_regional_analytics,
                         admin_outbreaks, dealer_analytics, request_otp,
                         verify_otp_view)
from diagnosis.views import DiagnosisViewSet, DiseaseDatabaseViewSet
from products.views import ProductViewSet, OrderViewSet, ReviewViewSet, ProductReportViewSet
from sensors.views import SensorDeviceViewSet
from ussd.views import ussd_handler
from chat.views import ChatRoomViewSet
from payments.views import PaymentViewSet, payment_webhook
from weather.views import get_weather
from announcements.views import AnnouncementViewSet, NotificationViewSet
from realtime.views import register_push_token, unregister_push_token
from auditlog.views import AuditLogViewSet
from system.views import health_check

router = DefaultRouter()
router.register(r'users', UserViewSet, basename='user')
router.register(r'diagnosis', DiagnosisViewSet, basename='diagnosis')
router.register(r'products', ProductViewSet, basename='product')
router.register(r'orders', OrderViewSet, basename='order')
router.register(r'chat', ChatRoomViewSet, basename='chat')
router.register(r'payments', PaymentViewSet, basename='payment')
router.register(r'diseases', DiseaseDatabaseViewSet, basename='disease-db')
router.register(r'announcements', AnnouncementViewSet, basename='announcement')
router.register(r'notifications', NotificationViewSet, basename='notification')
router.register(r'reviews', ReviewViewSet, basename='review')
router.register(r'product_reports', ProductReportViewSet, basename='product-report')
router.register(r'audit_logs', AuditLogViewSet, basename='audit-log')
router.register(r'sensors', SensorDeviceViewSet, basename='sensor')

urlpatterns = [
    path('admin/', admin.site.urls),
    # Auth
    path('api/auth/login/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/register/', register_view, name='register'),
    path('api/auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/password_reset/', password_reset_view, name='password_reset'),
    # Phone OTP verification (registration / password reset)
    path('api/auth/otp/send/', request_otp, name='request_otp'),
    path('api/auth/otp/verify/', verify_otp_view, name='verify_otp'),
    # Dealer sales analytics (scoped to the authenticated dealer)
    path('api/dealers/analytics/', dealer_analytics, name='dealer_analytics'),
    # Weather
    path('api/weather/', get_weather, name='get_weather'),
    # Admin stats & analytics
    path('api/admin/stats/', admin_stats, name='admin_stats'),
    path('api/admin/analytics/', admin_analytics, name='admin_analytics'),
    path('api/admin/regional/', admin_regional_analytics, name='admin_regional_analytics'),
    path('api/admin/outbreaks/', admin_outbreaks, name='admin_outbreaks'),
    # Payment provider webhook (HMAC-signed, idempotent)
    path('api/payments/webhook/', payment_webhook, name='payment_webhook'),
    # Push-token registration (FCM/APNs device tokens)
    path('api/push/register/', register_push_token, name='register_push_token'),
    path('api/push/unregister/', unregister_push_token, name='unregister_push_token'),
    # USSD / SMS companion callback (feature phones)
    path('api/ussd/', ussd_handler, name='ussd_handler'),
    # Health check (unauthenticated for orchestrator probes)
    path('api/health/', health_check, name='health_check'),
    # All API routes
    path('api/', include(router.urls)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

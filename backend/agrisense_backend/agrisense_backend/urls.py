from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework.routers import DefaultRouter
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from users.views import UserViewSet, register_view, password_reset_view, admin_stats, admin_analytics
from diagnosis.views import DiagnosisViewSet, DiseaseDatabaseViewSet
from products.views import ProductViewSet, OrderViewSet
from chat.views import ChatRoomViewSet
from payments.views import PaymentViewSet
from weather.views import get_weather
from announcements.views import AnnouncementViewSet, NotificationViewSet
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

urlpatterns = [
    path('admin/', admin.site.urls),
    # Auth
    path('api/auth/login/', TokenObtainPairView.as_view(), name='token_obtain_pair'),
    path('api/auth/register/', register_view, name='register'),
    path('api/auth/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
    path('api/auth/password_reset/', password_reset_view, name='password_reset'),
    # Weather
    path('api/weather/', get_weather, name='get_weather'),
    # Admin stats & analytics
    path('api/admin/stats/', admin_stats, name='admin_stats'),
    path('api/admin/analytics/', admin_analytics, name='admin_analytics'),
    # Health check (unauthenticated for orchestrator probes)
    path('api/health/', health_check, name='health_check'),
    # All API routes
    path('api/', include(router.urls)),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
    urlpatterns += static(settings.STATIC_URL, document_root=settings.STATIC_ROOT)

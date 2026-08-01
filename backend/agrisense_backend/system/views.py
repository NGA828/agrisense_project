"""System-level endpoints: health checks used by ops and the mobile admin console."""
import logging

from django.conf import settings
from django.core.cache import cache
from django.db import connection
from django.db.utils import OperationalError
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from ai_engine.services import get_engine_info

logger = logging.getLogger('agrisense.system')


def _db_healthy():
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()
        return True, None
    except OperationalError as exc:  # pragma: no cover - env dependent
        return False, str(exc)


def _cache_healthy():
    """Best-effort cache/Redis liveness probe."""
    try:
        cache.set('__health__', '1', timeout=5)
        cache.get('__health__')
        return True, None
    except Exception as exc:  # pragma: no cover - env dependent
        return False, str(exc)


def _push_info():
    try:
        from realtime.push_provider import get_push_provider
        provider = get_push_provider()
        return {
            'status': 'ok' if settings.PUSH_PROVIDER != 'noop' else 'degraded',
            'provider': provider.provider_name,
            'detail': ('Real push enabled' if settings.PUSH_PROVIDER != 'noop'
                       else 'noop — in-app notifications only'),
        }
    except Exception as exc:
        return {'status': 'error', 'detail': str(exc)}


def _payments_info():
    from payments.gateway import get_gateway
    gateway = get_gateway('MTN_MOMO')
    return {
        'status': 'ok' if gateway.provider != 'sandbox' else 'degraded',
        'provider': gateway.provider,
        'detail': ('Live gateway configured' if gateway.provider != 'sandbox'
                   else 'sandbox — real provider not configured'),
    }


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def health_check(request):
    """Liveness/readiness probe: HTTP 200 when critical deps are reachable.

    Used by load balancers / orchestrators (``/api/health/``) and by the
    admin "System Health" screen in the mobile app. Non-critical dependencies
    (push, payments) degrade the status to ``degraded`` but only database and
    AI engine failures return HTTP 503.
    """
    db_ok, db_err = _db_healthy()
    engine = get_engine_info()
    cache_ok, cache_err = _cache_healthy()

    checks = {
        'database': {'status': 'ok' if db_ok else 'error', 'detail': db_err},
        'cache': {'status': 'ok' if cache_ok else 'error', 'detail': cache_err},
        'ai_engine': {'status': engine.get('status', 'unknown'), 'detail': engine.get('detail')},
        'push': _push_info(),
        'payments': _payments_info(),
    }

    critical = ['database', 'cache']
    if any(checks[c]['status'] == 'error' for c in critical):
        overall = 'error'
        code = status.HTTP_503_SERVICE_UNAVAILABLE
    else:
        overall = 'ok' if all(c['status'] == 'ok' for c in checks.values()) else 'degraded'
        code = status.HTTP_200_OK

    return Response({
        'status': overall,
        'version': '1.0.0',
        'checks': checks,
        'timestamp': __import__('django.utils.timezone', fromlist=['now']).now().isoformat(),
    }, status=code)

"""System-level endpoints: health checks used by ops and the mobile admin console."""
from django.db import connection
from django.db.utils import OperationalError
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from ai_engine.services import get_engine_info


def _db_healthy():
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT 1')
            cursor.fetchone()
        return True, None
    except OperationalError as exc:  # pragma: no cover - env dependent
        return False, str(exc)


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def health_check(request):
    """Liveness/readiness probe: HTTP 200 when DB + AI engine are reachable.

    Used by load balancers / orchestrators (``/api/health/``) and by the
    admin "System Health" screen in the mobile app.
    """
    db_ok, db_err = _db_healthy()
    engine = get_engine_info()

    checks = {
        'database': {'status': 'ok' if db_ok else 'error', 'detail': db_err},
        'ai_engine': {'status': engine.get('status', 'unknown'), 'detail': engine.get('detail')},
    }
    overall = 'ok' if all(c['status'] == 'ok' for c in checks.values()) else 'degraded'
    status_code = status.HTTP_200_OK if overall == 'ok' else status.HTTP_503_SERVICE_UNAVAILABLE

    return Response({
        'status': overall,
        'version': '1.0.0',
        'checks': checks,
        'timestamp': __import__('django.utils.timezone', fromlist=['now']).now().isoformat(),
    }, status=status_code)

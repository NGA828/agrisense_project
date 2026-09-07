"""Private, retryable responses for a failed shared cache (including throttles)."""
import logging

from django_redis.exceptions import ConnectionInterrupted
from redis.exceptions import RedisError
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler, set_rollback

logger = logging.getLogger('agrisense.api')


def exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is not None:
        return response
    if isinstance(exc, (RedisError, ConnectionInterrupted)):
        # Throttling happens before a view. Fail closed, rather than bypassing
        # scan limits or returning an HTML 500 with connection credentials.
        logger.warning('A shared-cache operation was unavailable; request returned 503.')
        view = context.get('view')
        is_scan = getattr(view, 'throttle_scope', None) == 'ai'
        set_rollback()
        message = ('Crop analysis is temporarily unavailable. Please try again shortly.'
                   if is_scan else
                   'The service is temporarily unavailable. Please try again shortly. '
                   'If you started a payment, check its status before paying again.')
        return Response({
            'error': message,
            'code': 'ai_cache_unavailable' if is_scan else 'cache_unavailable',
            'retry_after': 5,
        }, status=503, headers={'Retry-After': '5'})
    return None  # Unrelated programming errors must not be concealed as cache faults.

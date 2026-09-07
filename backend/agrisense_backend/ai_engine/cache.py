"""User-scoped scan reuse and ownership-safe leases.

Redis shares coordination across production workers. Locmem uses an additional
process mutex to make its compare/delete atomic relative to lease acquisition.
No image, phone number or credential is used as a cache key.
"""
import hashlib
import json
import logging
import threading
import uuid

from django.core.cache import caches
from django.core.cache.backends.locmem import LocMemCache
from django_redis.cache import RedisCache

from .services import AIEngineUnavailable, _engine_cache_key, crop_key

logger = logging.getLogger('agrisense.ai')
_local_lease_mutex = threading.Lock()


def _unavailable():
    return AIEngineUnavailable(
        'Scan coordination is temporarily unavailable. No model request was submitted.',
        code='ai_cache_unavailable', retry_after=5,
    )


def analysis_cache_key(user_id, image, crop):
    from diagnosis.models import Disease

    image.seek(0)
    image_hash = hashlib.sha256(image.read()).hexdigest()
    image.seek(0)
    # Include the reviewed data itself, so edits/deletions immediately invalidate
    # results, even when a bulk update doesn't advance updated_at.
    reviewed = list(Disease.objects.filter(crop_name__iexact=crop)
                    .order_by('pk').values())
    revision = json.dumps(
        ['screening-v3', str(user_id), crop_key(crop), image_hash,
         _engine_cache_key(), reviewed], sort_keys=True, default=str,
    )
    return 'ai:scan:' + hashlib.sha256(revision.encode()).hexdigest()


def get_cached_result_id(key):
    """Fail closed before inference if scan deduplication cannot be checked."""
    try:
        return caches['default'].get(key)
    except Exception:
        # Exception messages can contain the Redis URL/password. Never log them.
        logger.warning('Could not read the scan cache; inference was not started.')
        raise _unavailable() from None


def cache_result(key, diagnosis_id, timeout):
    """A cache write must never turn an already-saved diagnosis into a failure."""
    if timeout <= 0:
        return
    try:
        caches['default'].set(key, diagnosis_id, timeout=timeout)
    except Exception:
        logger.warning('Diagnosis was saved, but its scan cache could not be updated.')


class AnalysisLease:
    def __init__(self, key, timeout, *, backend=None):
        self.key = key
        self.timeout = timeout
        self.backend = backend if backend is not None else caches['default']
        self.token = uuid.uuid4().hex
        self._redis_lock = None
        self._acquired = False

    def acquire(self):
        try:
            if isinstance(self.backend, RedisCache):
                # redis-py's release uses an atomic token comparison + delete
                # script. A stale owner cannot delete a replacement lease.
                self._redis_lock = self.backend.lock(
                    self.key, timeout=self.timeout, blocking_timeout=0,
                    thread_local=False,
                )
                self._acquired = self._redis_lock.acquire(blocking=False)
            elif isinstance(self.backend, LocMemCache):
                with _local_lease_mutex:
                    self._acquired = self.backend.add(
                        self.key, self.token, timeout=self.timeout)
            else:
                raise _unavailable()
            return self._acquired
        except Exception:
            logger.warning('Could not acquire a scan lease; inference was not started.')
            raise _unavailable() from None

    def release(self):
        if not self._acquired:
            return
        self._acquired = False
        try:
            if self._redis_lock is not None:
                self._redis_lock.release()
            else:
                with _local_lease_mutex:
                    if self.backend.get(self.key) == self.token:
                        self.backend.delete(self.key)
        except Exception:
            # The lease has a TTL. A lost connection or an expired/replaced
            # lease must not mask either a successful result or a crop rejection.
            logger.warning('Scan lease cleanup was unavailable; its TTL remains the fallback.')

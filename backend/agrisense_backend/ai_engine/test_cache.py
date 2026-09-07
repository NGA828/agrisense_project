from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.core.cache import caches
from django.core.cache.backends.dummy import DummyCache
from django.test import SimpleTestCase, override_settings
from django_redis.cache import RedisCache
from redis.exceptions import ConnectionError as RedisConnectionError, LockNotOwnedError
from rest_framework.exceptions import NotFound

from agrisense_backend.api_errors import exception_handler
from .cache import AnalysisLease, cache_result, get_cached_result_id
from .services import AIEngineUnavailable


@override_settings(CACHES={'default': {
    'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
    'LOCATION': 'scan-lease-regressions',
}})
class AnalysisCacheTests(SimpleTestCase):
    def setUp(self):
        self.backend = caches['default']
        self.backend.clear()
        self.key = 'ai:test:lease'

    def test_concurrent_local_acquisition_has_one_owner(self):
        leases = [AnalysisLease(self.key, 30, backend=self.backend) for _ in range(8)]
        with ThreadPoolExecutor(max_workers=8) as workers:
            acquired = list(workers.map(lambda lease: lease.acquire(), leases))
        self.assertEqual(sum(acquired), 1)
        owner = leases[acquired.index(True)]
        for lease in leases:
            if lease is not owner:
                lease.release()
        self.assertEqual(self.backend.get(self.key), owner.token)
        owner.release()
        self.assertIsNone(self.backend.get(self.key))

    def test_expired_owner_cannot_release_a_replacement_lease(self):
        old = AnalysisLease(self.key, 30, backend=self.backend)
        self.assertTrue(old.acquire())
        self.backend.delete(self.key)  # deterministic expiry, without a timing-dependent sleep
        replacement = AnalysisLease(self.key, 30, backend=self.backend)
        self.assertTrue(replacement.acquire())
        old.release()
        self.assertEqual(self.backend.get(self.key), replacement.token)
        replacement.release()

    def test_cleanup_failure_is_private_and_does_not_raise(self):
        lease = AnalysisLease(self.key, 30, backend=self.backend)
        lease.acquire()
        with patch.object(self.backend, 'get', side_effect=RedisConnectionError('private-cache-password')):
            with self.assertLogs('agrisense.ai', level='WARNING') as logs:
                lease.release()
        self.assertNotIn('private-cache-password', str(logs.output))
        self.assertEqual(self.backend.get(self.key), lease.token)

    def test_redis_uses_nonblocking_native_ownership_checked_lock(self):
        backend = Mock(spec=RedisCache)
        backend.lock.return_value.acquire.return_value = True
        lease = AnalysisLease(self.key, 55, backend=backend)
        self.assertTrue(lease.acquire())
        backend.lock.assert_called_once_with(self.key, timeout=55, blocking_timeout=0, thread_local=False)
        backend.lock.return_value.acquire.assert_called_once_with(blocking=False)
        lease.release()
        backend.lock.return_value.release.assert_called_once_with()
        backend.delete.assert_not_called()

    def test_failed_redis_acquisition_must_not_release_someone_elses_lock(self):
        backend = Mock(spec=RedisCache)
        backend.lock.return_value.acquire.return_value = False
        lease = AnalysisLease(self.key, 55, backend=backend)
        self.assertFalse(lease.acquire())
        lease.release()
        backend.lock.return_value.release.assert_not_called()
        backend.delete.assert_not_called()

    def test_lost_redis_lease_does_not_mask_the_scan_response(self):
        backend = Mock(spec=RedisCache)
        backend.lock.return_value.acquire.return_value = True
        backend.lock.return_value.release.side_effect = LockNotOwnedError('lost lease')
        lease = AnalysisLease(self.key, 55, backend=backend)
        lease.acquire()
        lease.release()
        backend.delete.assert_not_called()

    def test_redis_outage_before_acquiring_lease_fails_closed(self):
        backend = Mock(spec=RedisCache)
        backend.lock.return_value.acquire.side_effect = RedisConnectionError('private-cache-password')
        with self.assertRaises(AIEngineUnavailable) as caught:
            AnalysisLease(self.key, 55, backend=backend).acquire()
        self.assertEqual(caught.exception.code, 'ai_cache_unavailable')
        self.assertEqual(caught.exception.retry_after, 5)
        self.assertNotIn('private-cache-password', str(caught.exception))
        backend.lock.return_value.release.assert_not_called()

    def test_unsupported_cache_cannot_pretend_to_coordinate_scans(self):
        with self.assertRaises(AIEngineUnavailable):
            AnalysisLease(self.key, 30, backend=DummyCache('dummy', {})).acquire()

    def test_cache_read_outage_is_a_private_retryable_inference_error(self):
        with patch.object(self.backend, 'get', side_effect=RedisConnectionError('private-cache-password')):
            with self.assertRaises(AIEngineUnavailable) as caught:
                get_cached_result_id(self.key)
        self.assertEqual(caught.exception.code, 'ai_cache_unavailable')
        self.assertNotIn('private-cache-password', str(caught.exception))

    def test_cache_write_outage_does_not_turn_saved_result_into_failure(self):
        with patch.object(self.backend, 'set', side_effect=RedisConnectionError('private-cache-password')):
            with self.assertLogs('agrisense.ai', level='WARNING') as logs:
                cache_result(self.key, 'saved-diagnosis-id', 600)
        self.assertNotIn('private-cache-password', str(logs.output))

    def test_disabled_cache_timeout_does_not_write(self):
        with patch.object(self.backend, 'set') as store:
            cache_result(self.key, 'saved-diagnosis-id', 0)
        store.assert_not_called()


class CacheExceptionHandlerTests(SimpleTestCase):
    def test_throttle_cache_outage_returns_json_503_without_private_connection_details(self):
        context = {'view': SimpleNamespace(throttle_scope='ai')}
        with patch('agrisense_backend.api_errors.set_rollback') as rollback:
            response = exception_handler(RedisConnectionError('redis://:private-password@host'), context)
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'ai_cache_unavailable')
        self.assertEqual(response['Retry-After'], '5')
        self.assertNotIn('private-password', str(response.data))
        rollback.assert_called_once_with()

    def test_payment_cache_error_never_claims_payment_failed(self):
        response = exception_handler(RedisConnectionError('private details'), {})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'cache_unavailable')
        self.assertIn('check its status', response.data['error'])
        self.assertNotIn('failed', response.data['error'])

    def test_existing_api_errors_keep_their_original_status(self):
        self.assertEqual(exception_handler(NotFound(), {}).status_code, 404)

    def test_unrelated_programming_errors_are_not_hidden(self):
        self.assertIsNone(exception_handler(ValueError('programming error'), {}))

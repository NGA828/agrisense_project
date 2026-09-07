import io
import tempfile
from unittest.mock import patch

from django.core.cache import cache, caches
from django.test import override_settings
from django.urls import reverse
from PIL import Image
from rest_framework.test import APITestCase
from rest_framework.throttling import SimpleRateThrottle, UserRateThrottle
from redis.exceptions import ConnectionError as RedisConnectionError

from ai_engine.cache import analysis_cache_key
from ai_engine.services import AIEngineUnavailable, AIImageRejected, reset_engine_cache
from diagnosis.models import Disease, Diagnosis, TreatmentPlan
from users.models import User


def image_bytes(color=(80, 130, 70)):
    image = io.BytesIO()
    Image.new('RGB', (64, 64), color).save(image, 'PNG')
    image.seek(0)
    return image


def safe_result(crop='Tomato'):
    return {'disease_name': 'Healthy', 'confidence': 88, 'severity': 'low',
            'is_healthy': True, 'symptoms': 'No clear disease symptoms.',
            'causes': '', 'prevention': 'Monitor regularly.', 'duration': 0,
            'engine': 'openrouter-vision', 'trained_model': True,
            'detected_crop': crop, 'crop_confidence': 94,
            'visual_evidence': ['Leaf shape consistent with tomato.']}


@override_settings(AI_ENGINE='openrouter', OPENROUTER_API_KEY='test-only',
                   OPENROUTER_MODEL='openrouter/free', OPENROUTER_FALLBACK_MODELS=[],
                   AI_ANALYSIS_CACHE_SECONDS=600)
class DiagnosisReliabilityTests(APITestCase):
    def setUp(self):
        cache.clear()
        reset_engine_cache()
        self.addCleanup(reset_engine_cache)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.media_settings = override_settings(MEDIA_ROOT=self.temp.name)
        self.media_settings.enable()
        self.addCleanup(self.media_settings.disable)
        self.user = User.objects.create_user(username='scanner', email='scanner@test.com', role='farmer')
        self.client.force_authenticate(self.user)
        self.disease = Disease.objects.create(crop_name='Tomato', disease_name='Tomato Blight')
        Disease.objects.create(crop_name='Maize', disease_name='Maize Rust')
        self.url = reverse('diagnosis-analyze')
        self.mock = patch('diagnosis.views.analyze_disease', return_value=safe_result()).start()
        self.addCleanup(patch.stopall)

    def scan(self, crop='Tomato', color=(80, 130, 70)):
        return self.client.post(self.url, {'image': image_bytes(color), 'crop_type': crop}, format='multipart')

    def test_non_crop_and_wrong_crop_never_create_diagnosis_or_treatment(self):
        for code in ('not_a_crop', 'crop_mismatch', 'crop_uncertain'):
            self.mock.side_effect = AIImageRejected('Please check the photo.', code, 'Maize')
            response = self.scan()
            self.assertEqual(response.status_code, 422)
            self.assertEqual(response.data['code'], code)
            self.assertEqual(response.data['selected_crop'], 'Tomato')
            self.assertFalse(Diagnosis.objects.exists())
            self.assertFalse(TreatmentPlan.objects.exists())
        from pathlib import Path
        self.assertEqual(list(Path(self.temp.name).rglob('*')), [])

    def test_duplicate_photo_reuses_result_without_spending_another_request(self):
        first, second = self.scan(), self.scan()
        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.data['id'], second.data['id'])
        self.assertEqual(second['X-Analysis-Cached'], 'true')
        self.assertEqual(self.mock.call_count, 1)
        self.assertEqual(Diagnosis.objects.count(), 1)

    def test_cache_read_outage_does_not_start_inference_or_expose_credentials(self):
        backend = caches['default']
        original_get = backend.get
        def unavailable(key, *args, **kwargs):
            if str(key).startswith('ai:scan:'):
                raise RedisConnectionError('redis://:private-password@cache')
            return original_get(key, *args, **kwargs)
        with patch.object(backend, 'get', side_effect=unavailable):
            response = self.scan()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'ai_cache_unavailable')
        self.assertEqual(response['Retry-After'], '5')
        self.assertNotIn('private-password', str(response.data))
        self.mock.assert_not_called()
        self.assertFalse(Diagnosis.objects.exists())

    def test_lock_storage_outage_does_not_spend_a_model_request(self):
        with patch.object(caches['default'], 'add', side_effect=RedisConnectionError('cache unavailable')):
            response = self.scan()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'ai_cache_unavailable')
        self.mock.assert_not_called()
        self.assertFalse(Diagnosis.objects.exists())

    def test_cache_write_error_cannot_hide_a_saved_success(self):
        backend = caches['default']
        original_set = backend.set
        def unavailable(key, *args, **kwargs):
            if str(key).startswith('ai:scan:'):
                raise RedisConnectionError('private-cache-details')
            return original_set(key, *args, **kwargs)
        with patch.object(backend, 'set', side_effect=unavailable):
            response = self.scan()
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Diagnosis.objects.get().pk, response.data['id'])
        self.assertEqual(TreatmentPlan.objects.count(), 1)
        self.assertEqual(self.mock.call_count, 1)

    def test_cleanup_error_cannot_hide_a_saved_success(self):
        with patch.object(caches['default'], 'delete', side_effect=RedisConnectionError('cache unavailable')):
            response = self.scan()
        self.assertEqual(response.status_code, 201)
        self.assertEqual(Diagnosis.objects.get().pk, response.data['id'])

    def test_cleanup_error_cannot_turn_crop_rejection_into_server_error(self):
        self.mock.side_effect = AIImageRejected('Wrong crop.', 'crop_mismatch', 'Maize')
        with patch.object(caches['default'], 'delete', side_effect=RedisConnectionError('cache unavailable')):
            response = self.scan()
        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.data['code'], 'crop_mismatch')
        self.assertFalse(Diagnosis.objects.exists())
        self.assertFalse(TreatmentPlan.objects.exists())

    def test_completion_between_cache_read_and_lock_does_not_spend_second_scan(self):
        first = self.scan()
        # Simulates another worker finishing after our first read but before
        # acquisition. The result must be rechecked after obtaining the lease.
        with patch('ai_engine.cache.get_cached_result_id', side_effect=[None, first.data['id']]):
            second = self.scan()
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.data['id'], first.data['id'])
        self.assertEqual(self.mock.call_count, 1)

    def test_throttle_cache_failure_is_retryable_not_a_limit_bypass(self):
        with patch.object(UserRateThrottle, 'cache') as throttle_cache:
            throttle_cache.get.side_effect = RedisConnectionError('private-cache-password')
            response = self.scan()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'ai_cache_unavailable')
        self.assertNotIn('private-cache-password', str(response.data))
        self.mock.assert_not_called()
        self.assertFalse(Diagnosis.objects.exists())

    def test_cache_is_bound_to_crop_and_user(self):
        self.mock.side_effect = lambda image, crop: safe_result(crop)
        first = self.scan()
        different_crop = self.scan(crop='Maize')
        other = User.objects.create_user(username='other', email='other@test.com', role='farmer')
        self.client.force_authenticate(other)
        different_user = self.scan()
        self.assertEqual(self.mock.call_count, 3)
        self.assertNotEqual(first.data['id'], different_crop.data['id'])
        self.assertNotEqual(first.data['id'], different_user.data['id'])
        self.assertEqual(different_crop.data['crop_type'], 'Maize')

    def test_reviewed_data_edits_invalidate_cached_treatment(self):
        first = self.scan()
        Disease.objects.filter(pk=self.disease.pk).update(medication='New reviewed treatment')
        second = self.scan()
        self.assertEqual(self.mock.call_count, 2)
        self.assertNotEqual(first.data['id'], second.data['id'])

    def test_provider_failure_is_not_cached_or_stored(self):
        self.mock.side_effect = [AIEngineUnavailable('Provider timeout', code='ai_timeout'), safe_result()]
        first, second = self.scan(), self.scan()
        self.assertEqual(first.status_code, 503)
        self.assertEqual(first.data['code'], 'ai_timeout')
        self.assertEqual(second.status_code, 201)
        self.assertEqual(self.mock.call_count, 2)
        self.assertEqual(Diagnosis.objects.count(), 1)

    def test_inflight_duplicate_does_not_call_model(self):
        key = analysis_cache_key(self.user.pk, image_bytes(), 'Tomato')
        cache.add(key + ':lock', 'another-request', 30)
        response = self.scan()
        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'analysis_in_progress')
        self.mock.assert_not_called()

    def test_empty_knowledge_base_is_reported_without_model_request(self):
        Disease.objects.all().delete()
        response = self.scan()
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'ai_knowledge_base_empty')
        self.mock.assert_not_called()

    def test_fifty_distinct_analyses_per_day_are_not_blocked_by_app(self):
        # Simulate one scan every four seconds: below the 20/min burst limit.
        # This tests OUR allowance, not a promise about a provider's free quota.
        clock = [100000.0]
        with patch.object(SimpleRateThrottle, 'timer', staticmethod(lambda: clock[0])):
            for index in range(50):
                clock[0] += 4
                response = self.scan(color=(80, 130, index))
                self.assertEqual(response.status_code, 201, response.data)
        self.assertEqual(Diagnosis.objects.count(), 50)
        self.assertEqual(self.mock.call_count, 50)

    @override_settings(DEBUG=False)
    def test_provider_quota_error_is_actionable_and_private(self):
        self.mock.side_effect = AIEngineUnavailable('internal provider diagnostics', code='ai_rate_limited', retry_after=70)
        response = self.scan()
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response['Retry-After'], '70')
        self.assertNotIn('detail', response.data)
        self.assertNotIn('internal provider', str(response.data))

    @override_settings(AI_MAX_UPLOAD_BYTES=20)
    def test_oversized_images_rejected_before_network(self):
        response = self.scan()
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.data['code'], 'image_too_large')
        self.mock.assert_not_called()

    def test_diagnosis_cannot_be_relabelled_after_scanning(self):
        result = self.scan()
        response = self.client.patch(reverse('diagnosis-detail', args=[result.data['id']]),
                                     {'crop_type': 'Maize'}, format='multipart')
        self.assertEqual(response.status_code, 405)
        self.assertEqual(Diagnosis.objects.get().crop_type, 'Tomato')

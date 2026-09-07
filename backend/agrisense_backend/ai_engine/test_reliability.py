import io
import json
from types import SimpleNamespace
from unittest.mock import Mock, patch

from django.core.cache import cache
from django.test import TestCase, override_settings
from PIL import Image

from diagnosis.models import Disease
from .openrouter_client import OpenRouterVisionClient
from .ollama_client import OllamaVisionClient
from .services import (
    AIEngineUnavailable, AIImageRejected, OpenRouterEngine, OllamaEngine,
    analyze_disease, get_available_crops, get_engine, reset_engine_cache,
)


def photo(size=(64, 64)):
    image = io.BytesIO()
    Image.new('RGB', size, (65, 125, 80)).save(image, 'PNG')
    image.seek(0)
    return image


def classification(**changes):
    return {'image_type': 'crop', 'detected_crop': 'Tomato', 'crop_confidence': 92,
            'outcome': 'disease', 'disease_name': 'Tomato Blight', 'confidence': 89,
            'evidence': ['Dark lesions on a tomato leaf.'], **changes}


def transport(result=None, *, status=200, error=None, headers=None):
    envelope = {'model': 'test/vision:free',
                'choices': [{'message': {'content': json.dumps(result or classification())}}]}
    if error:
        envelope['error'] = error
    return Mock(return_value=SimpleNamespace(
        status_code=status, headers=headers or {}, json=lambda: envelope))


@override_settings(AI_ENGINE='openrouter', OPENROUTER_API_KEY='unit-test-only',
                   OPENROUTER_MODEL='openrouter/free', OPENROUTER_FALLBACK_MODELS=[],
                   AI_ALLOW_RULE_FALLBACK=True, AI_REQUIRE_TRAINED_MODEL=True)
class VisionReliabilityTests(TestCase):
    def setUp(self):
        cache.clear()
        reset_engine_cache()
        Disease.objects.create(disease_name='Tomato Blight', crop_name='Tomato',
                               symptoms='Reviewed symptoms', medication='Reviewed treatment only')
        Disease.objects.create(disease_name='Maize Rust', crop_name='Maize')
        self.addCleanup(reset_engine_cache)

    def engine(self, result):
        return OpenRouterEngine(OpenRouterVisionClient(post=transport(result)))

    def test_router_is_accepted_by_free_spend_guard(self):
        post = transport()
        result = OpenRouterEngine(OpenRouterVisionClient(post=post)).analyze(photo(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Tomato Blight')
        kwargs = post.call_args.kwargs
        self.assertEqual(kwargs['json']['model'], 'openrouter/free')
        self.assertEqual(kwargs['json']['provider']['max_price'], {'prompt': 0, 'completion': 0})
        self.assertEqual(kwargs['json']['reasoning'], {'enabled': False})
        self.assertEqual(kwargs['timeout'], (5, 25))
        self.assertEqual(post.call_count, 1)

    def test_non_crop_overrides_an_otherwise_valid_disease_result(self):
        with self.assertRaises(AIImageRejected) as caught:
            self.engine(classification(image_type='not_crop')).analyze(photo(), 'Tomato')
        self.assertEqual(caught.exception.code, 'not_a_crop')

    def test_wrong_crop_cannot_get_selected_crop_diagnosis(self):
        with self.assertRaises(AIImageRejected) as caught:
            self.engine(classification(detected_crop='Maize')).analyze(photo(), 'Tomato')
        self.assertEqual(caught.exception.code, 'crop_mismatch')
        self.assertEqual(caught.exception.detected_crop, 'Maize')

    def test_wrong_crop_cannot_even_be_marked_healthy(self):
        with self.assertRaises(AIImageRejected):
            self.engine(classification(detected_crop='Maize', outcome='healthy',
                                       disease_name='Healthy')).analyze(photo(), 'Tomato')

    def test_unidentifiable_crop_is_rejected_not_assumed(self):
        for changes in ({'detected_crop': 'Unknown'}, {'image_type': 'uncertain'},
                        {'crop_confidence': 45, 'confidence': 99}):
            with self.subTest(changes=changes), self.assertRaises(AIImageRejected) as caught:
                self.engine(classification(**changes)).analyze(photo(), 'Tomato')
            self.assertEqual(caught.exception.code, 'crop_uncertain')

    def test_crop_aliases_are_recognised_without_cross_crop_fallback(self):
        result = self.engine(classification(detected_crop='Corn', disease_name='Maize Rust')).analyze(photo(), 'Maize')
        self.assertEqual(result['disease_name'], 'Maize Rust')

    def test_missing_identity_evidence_fails_closed_even_with_rule_fallback_flag(self):
        payload = classification()
        del payload['detected_crop']
        with self.assertRaises(AIEngineUnavailable) as caught:
            self.engine(payload).analyze(photo(), 'Tomato')
        self.assertEqual(caught.exception.code, 'ai_invalid_response')

    def test_trained_requirement_also_blocks_an_engines_internal_demo_fallback(self):
        engine = Mock()
        engine.analyze.return_value = {'trained_model': False, 'engine': 'rule-based'}
        with patch('ai_engine.services.get_engine', return_value=engine):
            with self.assertRaises(AIEngineUnavailable):
                analyze_disease(photo(), 'Tomato')

    def test_non_finite_or_coerced_confidences_are_rejected(self):
        for field in ('confidence', 'crop_confidence'):
            for value in (True, '90', float('nan'), float('inf'), -1, 101):
                with self.subTest(field=field, value=value), self.assertRaises(AIEngineUnavailable):
                    self.engine(classification(**{field: value})).analyze(photo(), 'Tomato')

    def test_provider_error_is_not_a_demo_diagnosis(self):
        post = transport(status=429, error={'code': 429}, headers={'Retry-After': '120'})
        with self.assertRaises(AIEngineUnavailable) as caught:
            OpenRouterEngine(OpenRouterVisionClient(post=post)).analyze(photo(), 'Tomato')
        self.assertEqual(caught.exception.code, 'ai_rate_limited')
        self.assertEqual(caught.exception.retry_after, 120)
        self.assertEqual(post.call_count, 1, 'No hidden retries may consume the free budget')

    def test_provider_error_inside_http_200_is_handled(self):
        post = transport(error={'code': 429})
        with self.assertRaises(AIEngineUnavailable) as caught:
            OpenRouterEngine(OpenRouterVisionClient(post=post)).analyze(photo(), 'Tomato')
        self.assertEqual(caught.exception.code, 'ai_rate_limited')

    def test_images_are_resized_and_upload_rewound(self):
        import base64
        post = transport()
        image = photo((2400, 1600))
        OpenRouterEngine(OpenRouterVisionClient(post=post)).analyze(image, 'Tomato')
        url = post.call_args.kwargs['json']['messages'][1]['content'][1]['image_url']['url']
        resized = Image.open(io.BytesIO(base64.b64decode(url.split(',')[1])))
        self.assertLessEqual(max(resized.size), 1024)
        self.assertEqual(resized.format, 'JPEG')
        self.assertFalse(resized.getexif())
        self.assertEqual(image.tell(), 0)

    def test_only_reviewed_crops_are_offered_and_case_duplicates_are_removed(self):
        Disease.objects.create(crop_name='tomato', disease_name='Other reviewed disease')
        self.assertEqual(get_available_crops(), ['Tomato', 'Maize'])
        Disease.objects.all().delete()
        self.assertEqual(get_available_crops(), [])

    def test_cached_engine_respects_changed_spend_guard_and_timeout(self):
        first = get_engine()
        with override_settings(OPENROUTER_TIMEOUT_SECONDS=12, OPENROUTER_FREE_ONLY=False):
            second = get_engine()
        self.assertIsNot(first, second)
        self.assertEqual(second._client.timeout, 12)
        self.assertFalse(second._client.free_only)

    @override_settings(OPENROUTER_FALLBACK_MODELS=['openai/paid-model'])
    def test_paid_fallback_is_never_called(self):
        post = transport()
        with self.assertRaises(AIEngineUnavailable):
            OpenRouterEngine(OpenRouterVisionClient(post=post)).analyze(photo(), 'Tomato')
        post.assert_not_called()


@override_settings(AI_ENGINE='ollama', OPENROUTER_API_KEY='', OLLAMA_MODEL='gemma3:4b',
                   OLLAMA_BASE_URL='http://private-model:11434', OLLAMA_TIMEOUT_SECONDS=25)
class LocalVisionTests(TestCase):
    def setUp(self):
        Disease.objects.create(disease_name='Tomato Blight', crop_name='Tomato',
                               medication='Reviewed treatment only')
        reset_engine_cache()
        self.addCleanup(reset_engine_cache)

    def test_local_vision_needs_no_key_and_uses_same_guards(self):
        post = Mock(return_value=SimpleNamespace(status_code=200, json=lambda: {
            'model': 'gemma3:4b', 'message': {'content': json.dumps(classification())}}))
        engine = OllamaEngine(OllamaVisionClient(post=post))
        result = engine.analyze(photo(), 'Tomato')
        self.assertEqual(result['engine'], 'ollama-vision')
        self.assertEqual(result['medication'], 'Reviewed treatment only')
        self.assertEqual(post.call_args.args[0], 'http://private-model:11434/api/chat')
        payload = post.call_args.kwargs['json']
        self.assertFalse(payload['stream'])
        self.assertEqual(payload['keep_alive'], '30m')
        self.assertIn('detected_crop', payload['format']['required'])
        self.assertTrue(payload['messages'][1]['images'][0])
        self.assertNotIn('headers', post.call_args.kwargs)

    def test_local_wrong_crop_is_rejected(self):
        post = Mock(return_value=SimpleNamespace(status_code=200, json=lambda: {
            'message': {'content': json.dumps(classification(detected_crop='Cassava'))}}))
        with self.assertRaises(AIImageRejected):
            OllamaEngine(OllamaVisionClient(post=post)).analyze(photo(), 'Tomato')

    @override_settings(OLLAMA_MODEL='some-model:cloud')
    def test_cloud_model_not_silently_used_as_quota_free_local_model(self):
        post = Mock()
        with self.assertRaises(AIEngineUnavailable):
            OllamaEngine(OllamaVisionClient(post=post)).analyze(photo(), 'Tomato')
        post.assert_not_called()

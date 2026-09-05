import io
import json
from decimal import Decimal

from django.test import TestCase, override_settings
from PIL import Image

from ai_engine.class_mapping import ClassMapError, infer_class_fields, parse_class_map
from ai_engine.openrouter_client import OpenRouterVisionClient
from ai_engine.services import (AIEngineUnavailable, AIInferenceError,
                                OpenRouterEngine, RuleBasedEngine,
                                TensorFlowEngine, analyze_disease,
                                get_available_crops, get_disease_info,
                                get_engine_info)


def png_bytes(color=(100, 130, 90), size=(64, 64)):
    buf = io.BytesIO()
    Image.new('RGB', size, color).save(buf, format='PNG')
    buf.seek(0)
    return buf


class RuleBasedEngineTests(TestCase):
    def test_analyze_is_deterministic(self):
        img = png_bytes()
        r1 = RuleBasedEngine().analyze(img, 'Tomato')
        img.seek(0)
        r2 = RuleBasedEngine().analyze(img, 'Tomato')
        self.assertEqual(r1['disease_name'], r2['disease_name'])
        self.assertEqual(r1['confidence'], r2['confidence'])
        self.assertIn('engine', r1)
        self.assertEqual(r1['engine'], 'rule-based')

    def test_analyze_returns_full_treatment_payload(self):
        result = RuleBasedEngine().analyze(png_bytes(), 'Maize')
        for key in ['symptoms', 'confidence', 'disease_name', 'severity',
                    'causes', 'prevention', 'treatment_type', 'medication',
                    'instructions', 'duration', 'follow_up_date']:
            self.assertIn(key, result)
        self.assertIsInstance(result['confidence'], Decimal)

    def test_unknown_crop_falls_back_to_default(self):
        result = RuleBasedEngine().analyze(png_bytes(), 'Mango')
        self.assertIn(result['disease_name'], [
            'Tomato Late Blight', 'Tomato Early Blight', 'Tomato Bacterial Wilt'])

    def test_brownish_image_scores_lesion_diseases(self):
        # Brown-heavy image should favour high-lesion signatures over mosaic.
        brown = png_bytes(color=(150, 90, 70))
        result = RuleBasedEngine().analyze(brown, 'Tomato')
        self.assertIn(result['disease_name'], ['Tomato Late Blight', 'Tomato Early Blight'])


class RuleBasedEngineV2Tests(TestCase):
    """AI v2: healthy outcome, calibrated confidence, honest inconclusive."""

    def test_healthy_leaf_returns_healthy(self):
        # Bright green, no lesion -> 'Healthy' outcome, not a disease.
        result = RuleBasedEngine().analyze(png_bytes(color=(80, 160, 70)), 'Tomato')
        self.assertTrue(result['is_healthy'])
        self.assertEqual(result['disease_name'], 'Healthy')
        self.assertEqual(result['treatment_type'], 'No treatment required')

    def test_confidence_is_calibrated_lower(self):
        # Temperature scaling must not overclaim ~95% certainty.
        result = RuleBasedEngine().analyze(png_bytes(), 'Tomato')
        self.assertLessEqual(float(result['confidence']), 90.0)

    def test_low_confidence_returns_inconclusive(self):
        # Force the low-confidence threshold high so any disease match is
        # declared inconclusive (honest "consult an agronomist" path).
        with override_settings(AI_LOW_CONFIDENCE_THRESHOLD=99.0):
            result = RuleBasedEngine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Inconclusive')
        self.assertTrue(result.get('low_confidence'))
        self.assertIn('agronomist', result['treatment_type'].lower())

    def test_v2_model_version(self):
        result = RuleBasedEngine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['model_version'], 'v2.0-rules')


@override_settings(AI_ENGINE='rules', AI_REQUIRE_TRAINED_MODEL=False)
class KnowledgeBaseTests(TestCase):
    def test_available_crops(self):
        crops = get_available_crops()
        self.assertIn('Tomato', crops)
        self.assertIn('Maize', crops)

    def test_disease_info_fallback(self):
        info = get_disease_info('Maize Rust')
        self.assertIsNotNone(info)
        self.assertEqual(info['disease_name'], 'Maize Rust')

    def test_engine_info_is_truthful_about_default_heuristic(self):
        info = get_engine_info()
        self.assertEqual(info['status'], 'degraded')
        self.assertEqual(info['engine'], 'rule-based')
        self.assertFalse(info['trained_model'])

    @override_settings(AI_REQUIRE_TRAINED_MODEL=True)
    def test_production_gate_rejects_heuristic(self):
        with self.assertRaises(AIEngineUnavailable):
            analyze_disease(png_bytes(), 'Tomato')
        self.assertEqual(get_engine_info()['status'], 'error')


class ClassMapTests(TestCase):
    def test_parses_explicit_manifest(self):
        classes = parse_class_map({'classes': [
            {'index': 0, 'label': 'Tomato___Early_blight',
             'crop_type': 'Tomato', 'disease_name': 'Tomato Early Blight'},
            {'index': 1, 'label': 'Tomato___healthy',
             'crop_type': 'Tomato', 'is_healthy': True},
        ]})
        self.assertEqual(classes[0].disease_name, 'Tomato Early Blight')
        self.assertTrue(classes[1].is_healthy)

    def test_parses_keras_class_indices(self):
        classes = parse_class_map({
            'Tomato___Late_blight': 1,
            'Tomato___healthy': 0,
        })
        self.assertEqual([item.index for item in classes], [0, 1])
        self.assertTrue(classes[0].is_healthy)
        self.assertEqual(classes[1].disease_name, 'Tomato Late Blight')

    def test_infers_maize_alias(self):
        crop, disease, healthy = infer_class_fields(
            'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot')
        self.assertEqual(crop, 'Maize')
        self.assertEqual(disease, 'Maize Gray Leaf Spot')
        self.assertFalse(healthy)

    def test_parses_huggingface_id2label_with_healthy_prefix(self):
        classes = parse_class_map({'id2label': {
            '0': 'Tomato with Early Blight',
            '1': 'Healthy Tomato Plant',
        }})
        self.assertEqual(classes[0].crop_type, 'Tomato')
        self.assertEqual(classes[0].disease_name, 'Tomato Early Blight')
        self.assertTrue(classes[1].is_healthy)

    def test_rejects_unmappable_label(self):
        with self.assertRaises(ClassMapError):
            parse_class_map(['mystery'])


class _FakeOpenRouterResponse:
    def __init__(self, result=None, status_code=200, model='nex-agi/test:free',
                 error=None):
        self.status_code = status_code
        self._data = ({
            'model': model,
            'choices': [{
                'message': {'content': json.dumps(result or {})},
            }],
        } if error is None else {'error': {'message': error}})

    def json(self):
        return self._data


@override_settings(
    AI_ENGINE='openrouter',
    OPENROUTER_API_KEY='test-openrouter-key',
    OPENROUTER_MODEL='dots-studio/dots-3-note-preview:free',
    OPENROUTER_FALLBACK_MODELS=['google/gemma-4-26b-a4b-it:free'],
    OPENROUTER_CONFIDENCE_THRESHOLD=70,
    OPENROUTER_MAX_CONFIDENCE=95,
    AI_ALLOW_RULE_FALLBACK=False,
)
class OpenRouterEngineTests(TestCase):
    def setUp(self):
        from diagnosis.models import Disease

        Disease.objects.create(
            disease_name='Reviewed Tomato Blight', crop_name='Tomato',
            pathogen='Reviewed fungus', symptoms='Reviewed dark leaf spots',
            causes='Local reviewed cause', severity='medium',
            prevention='Local reviewed prevention',
            treatment_type='Local reviewed treatment',
            medication='Local reviewed medication',
            instructions='Local reviewed instructions', duration=12,
        )
        Disease.objects.create(
            disease_name='Reviewed Maize Rust', crop_name='Maize',
            symptoms='Orange pustules', severity='medium',
        )
        self.requests = []
        self.result = {
            'outcome': 'disease',
            'disease_name': 'Reviewed Tomato Blight',
            'confidence': 88,
            'evidence': ['dark spots visible on the leaf'],
        }
        self.status_code = 200
        self.error = None
        # Which model the provider reports answering; with the `models`
        # failover array this can differ from the one we requested.
        self.responding_model = 'dots-studio/dots-3-note-preview:free'

    def post(self, url, **kwargs):
        self.requests.append((url, kwargs))
        return _FakeOpenRouterResponse(
            result=self.result,
            status_code=self.status_code,
            model=self.responding_model,
            error=self.error,
        )

    def engine(self):
        return OpenRouterEngine(OpenRouterVisionClient(post=self.post))

    def test_supported_crops_come_only_from_reviewed_database_rows(self):
        crops = get_available_crops()
        # The engine's supported-crop list is the union of reviewed database
        # crops and the bundled/defaults (the crop picker must offer every
        # crop the knowledge base can still diagnose offline), with reviewed
        # rows first and no duplicates.
        self.assertEqual(crops[0], 'Maize')
        self.assertEqual(crops[1], 'Tomato')
        self.assertEqual(len(crops), len(set(crops)))

    def test_uses_only_reviewed_diseases_for_selected_crop(self):
        result = self.engine().analyze(png_bytes(), 'Tomato')

        self.assertEqual(result['disease_name'], 'Reviewed Tomato Blight')
        self.assertEqual(result['medication'], 'Local reviewed medication')
        self.assertEqual(result['engine'], 'openrouter-vision')
        self.assertTrue(result['trained_model'])
        self.assertTrue(result['knowledge_base_match'])

        _url, request = self.requests[0]
        payload = request['json']
        serialized = json.dumps(payload)
        self.assertIn('Reviewed Tomato Blight', serialized)
        self.assertNotIn('Reviewed Maize Rust', serialized)
        # Treatments are deliberately never sent to or accepted from the model.
        self.assertNotIn('Local reviewed medication', serialized)
        allowed = payload['response_format']['json_schema']['schema'] \
            ['properties']['disease_name']['enum']
        self.assertEqual(
            allowed,
            ['Healthy', 'Inconclusive', 'NotACrop', 'CropMismatch',
             'Reviewed Tomato Blight'],
        )
        self.assertTrue(request['headers']['Authorization'].startswith('Bearer '))
        image_url = payload['messages'][1]['content'][1]['image_url']['url']
        self.assertTrue(image_url.startswith('data:image/jpeg;base64,'))

    def test_healthy_result_uses_no_disease_treatment(self):
        self.result = {
            'outcome': 'healthy', 'disease_name': 'Healthy',
            'confidence': 86, 'evidence': ['uniform green tissue'],
        }
        result = self.engine().analyze(png_bytes(), 'Tomato')
        self.assertTrue(result['is_healthy'])
        self.assertEqual(result['disease_name'], 'Healthy')
        self.assertEqual(result['treatment_type'], 'No treatment required')

    def test_low_confidence_becomes_inconclusive(self):
        self.result['confidence'] = 55
        result = self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Inconclusive')
        self.assertTrue(result['is_inconclusive'])
        self.assertTrue(result['trained_model'])

    def test_explicit_inconclusive_does_not_show_high_match_confidence(self):
        self.result = {
            'outcome': 'inconclusive', 'disease_name': 'Inconclusive',
            'confidence': 99, 'evidence': ['image is blurry'],
        }
        result = self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Inconclusive')
        self.assertLess(float(result['confidence']), 70)

    def test_model_cannot_select_unreviewed_disease(self):
        self.result['disease_name'] = 'Invented Leaf Disease'
        with self.assertRaises(AIInferenceError):
            self.engine().analyze(png_bytes(), 'Tomato')

    def test_model_treatment_fields_are_rejected(self):
        self.result['treatment'] = 'Buy an invented pesticide'
        with self.assertRaises(AIInferenceError):
            self.engine().analyze(png_bytes(), 'Tomato')

    def test_crop_without_reviewed_rows_is_rejected_before_api_call(self):
        with self.assertRaises(AIInferenceError):
            self.engine().analyze(png_bytes(), 'Cassava')
        self.assertEqual(self.requests, [])

    def test_duplicate_reviewed_names_are_rejected_before_api_call(self):
        from diagnosis.models import Disease
        Disease.objects.create(
            disease_name='reviewed tomato blight', crop_name='Tomato')
        with self.assertRaises(AIInferenceError):
            self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(self.requests, [])

    def test_provider_failure_fails_closed(self):
        self.status_code = 429
        self.error = 'rate limited'
        with self.assertRaises(AIEngineUnavailable):
            self.engine().analyze(png_bytes(), 'Tomato')

    def test_provider_failure_carries_actionable_hint(self):
        """The farmer-facing error is generic, but the admin/log detail must
        distinguish quota exhaustion from a retired model."""
        self.status_code = 429
        with self.assertRaises(AIEngineUnavailable) as ctx:
            self.engine().analyze(png_bytes(), 'Tomato')
        self.assertIn('Rate limited', str(ctx.exception))

        self.status_code = 404
        with self.assertRaises(AIEngineUnavailable) as ctx:
            self.engine().analyze(png_bytes(), 'Tomato')
        self.assertIn('check_ai_model', str(ctx.exception))

    def test_completion_budget_leaves_room_for_reasoning(self):
        """Reasoning models spend hidden tokens from the same completion
        budget; a small max_tokens yields an empty body and a failed scan."""
        self.engine().analyze(png_bytes(), 'Tomato')
        payload = self.requests[0][1]['json']
        self.assertGreaterEqual(payload['max_tokens'], 1500)

    @override_settings(OPENROUTER_API_KEY='')
    def test_missing_api_key_fails_closed(self):
        with self.assertRaises(AIEngineUnavailable):
            self.engine().analyze(png_bytes(), 'Tomato')

    # ── model routing / availability ─────────────────────────────────────
    def test_request_sends_server_side_fallback_chain(self):
        """Free endpoints get throttled first; OpenRouter must fail over for us.

        Sending the `models` array means a rate-limited primary is retried
        against the fallback inside a single HTTP request, so the farmer never
        re-uploads the photo.
        """
        self.engine().analyze(png_bytes(), 'Tomato')
        payload = self.requests[0][1]['json']
        self.assertEqual(
            payload['models'],
            ['dots-studio/dots-3-note-preview:free',
             'google/gemma-4-26b-a4b-it:free'],
        )
        # `model` stays set for providers/proxies that ignore `models`.
        self.assertEqual(payload['model'], 'dots-studio/dots-3-note-preview:free')

    @override_settings(OPENROUTER_FALLBACK_MODELS=[])
    def test_no_fallback_configured_omits_models_array(self):
        self.engine().analyze(png_bytes(), 'Tomato')
        self.assertNotIn('models', self.requests[0][1]['json'])

    @override_settings(
        OPENROUTER_FALLBACK_MODELS=['dots-studio/dots-3-note-preview:free'])
    def test_fallback_duplicating_primary_is_dropped(self):
        """A duplicated id would waste a retry on the model that just failed."""
        self.engine().analyze(png_bytes(), 'Tomato')
        self.assertNotIn('models', self.requests[0][1]['json'])

    def test_structured_output_routing_is_still_required(self):
        """require_parameters keeps us off endpoints that ignore json_schema.

        Without it a provider may return prose, and the disease allow-list
        stops being enforced at the transport layer.
        """
        self.engine().analyze(png_bytes(), 'Tomato')
        payload = self.requests[0][1]['json']
        self.assertTrue(payload['provider']['require_parameters'])
        self.assertEqual(payload['response_format']['type'], 'json_schema')
        self.assertTrue(payload['response_format']['json_schema']['strict'])

    def test_records_the_model_that_actually_answered(self):
        """With failover the responder may differ from the requested model."""
        self.responding_model = 'google/gemma-4-26b-a4b-it:free'
        result = self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['model_version'], 'google/gemma-4-26b-a4b-it:free')

    # ── spend guard (this deployment must never be billed) ───────────────
    def test_configured_models_are_all_free(self):
        client = OpenRouterVisionClient(post=self.post)
        for name in (client.model, *client.fallback_models):
            self.assertTrue(
                name.endswith(':free'),
                f'{name} is a paid model; the default config must stay free.')

    def test_request_pins_max_price_to_zero(self):
        """OpenRouter must refuse to bill rather than silently charge."""
        self.engine().analyze(png_bytes(), 'Tomato')
        provider = self.requests[0][1]['json']['provider']
        self.assertEqual(provider['max_price'], {'prompt': 0, 'completion': 0})

    @override_settings(OPENROUTER_MODEL='openai/gpt-4o')
    def test_paid_primary_is_refused_before_any_request(self):
        with self.assertRaises(AIEngineUnavailable):
            self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(self.requests, [], 'no billable call may be made')

    @override_settings(OPENROUTER_FALLBACK_MODELS=['openai/gpt-4o'])
    def test_paid_fallback_is_refused_before_any_request(self):
        with self.assertRaises(AIEngineUnavailable):
            self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(self.requests, [])

    @override_settings(
        OPENROUTER_MODEL='openai/gpt-4o',
        OPENROUTER_FREE_ONLY=False,
    )
    def test_paid_model_allowed_only_with_explicit_opt_in(self):
        self.responding_model = 'openai/gpt-4o'
        result = self.engine().analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['model_version'], 'openai/gpt-4o')
        self.assertNotIn('max_price', self.requests[0][1]['json']['provider'])


class _FakeModel:
    def __init__(self, output):
        self.output = output
        self.calls = 0

    def predict(self, batch, verbose=0):
        self.calls += 1
        return [self.output]


class TensorFlowEngineTests(TestCase):
    """Real inference orchestration tested with a tiny in-memory model double."""

    class_map = [
        {'index': 0, 'label': 'Tomato___healthy',
         'crop_type': 'Tomato', 'is_healthy': True},
        {'index': 1, 'label': 'Tomato___Early_blight',
         'crop_type': 'Tomato', 'disease_name': 'Tomato Early Blight'},
        {'index': 2, 'label': 'Corn_(maize)___Common_rust_',
         'crop_type': 'Maize', 'disease_name': 'Maize Rust'},
    ]

    def engine(self, output):
        return TensorFlowEngine(
            model=_FakeModel(output),
            class_map=self.class_map,
            preprocessor=lambda image: 'preprocessed-batch',
        )

    @override_settings(AI_MODEL_VERSION='test-cnn-v1')
    def test_model_prediction_maps_to_knowledge_base(self):
        engine = self.engine([0.02, 0.95, 0.03])
        result = engine.analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Tomato Early Blight')
        self.assertEqual(result['engine'], 'tensorflow-cnn')
        self.assertEqual(result['model_version'], 'test-cnn-v1')
        self.assertEqual(result['model_label'], 'Tomato___Early_blight')
        self.assertTrue(result['trained_model'])
        self.assertTrue(result['knowledge_base_match'])
        self.assertEqual(len(result['alternatives']), 2)

    def test_model_can_return_healthy(self):
        result = self.engine([0.96, 0.03, 0.01]).analyze(
            png_bytes(), 'Tomato')
        self.assertTrue(result['is_healthy'])
        self.assertEqual(result['disease_name'], 'Healthy')
        self.assertEqual(result['engine'], 'tensorflow-cnn')

    @override_settings(AI_MODEL_CONFIDENCE_THRESHOLD=99.0)
    def test_low_model_confidence_is_inconclusive(self):
        result = self.engine([0.04, 0.94, 0.02]).analyze(
            png_bytes(), 'Tomato')
        self.assertEqual(result['disease_name'], 'Inconclusive')
        self.assertTrue(result['low_confidence'])
        self.assertEqual(result['engine'], 'tensorflow-cnn')

    def test_selected_crop_masks_other_crop_classes(self):
        # The global top class is Tomato, but only Maize outputs are eligible.
        result = self.engine([0.01, 0.98, 0.01]).analyze(
            png_bytes(), 'Maize')
        self.assertEqual(result['disease_name'], 'Inconclusive')
        self.assertEqual(result['model_label'], 'Corn_(maize)___Common_rust_')

    def test_output_manifest_mismatch_fails_closed(self):
        engine = self.engine([0.1, 0.9])
        with self.assertRaises(AIInferenceError):
            engine.analyze(png_bytes(), 'Tomato')

    @override_settings(AI_ALLOW_RULE_FALLBACK=False)
    def test_missing_model_fails_instead_of_pretending(self):
        engine = TensorFlowEngine(model=None, class_map=self.class_map)
        with self.assertRaises(AIEngineUnavailable):
            engine.analyze(png_bytes(), 'Tomato')

    @override_settings(AI_ALLOW_RULE_FALLBACK=True)
    def test_rule_fallback_requires_explicit_opt_in(self):
        engine = TensorFlowEngine(model=None, class_map=self.class_map)
        result = engine.analyze(png_bytes(), 'Tomato')
        self.assertEqual(result['engine'], 'rule-based')
        self.assertFalse(result['trained_model'])
        self.assertIn('fallback_reason', result)

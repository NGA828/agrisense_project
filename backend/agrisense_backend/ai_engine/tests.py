import io
from decimal import Decimal

from django.test import TestCase, override_settings
from PIL import Image

from ai_engine.class_mapping import ClassMapError, infer_class_fields, parse_class_map
from ai_engine.services import (AIEngineUnavailable, AIInferenceError,
                                RuleBasedEngine, TensorFlowEngine,
                                analyze_disease, get_available_crops,
                                get_disease_info, get_engine_info)


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

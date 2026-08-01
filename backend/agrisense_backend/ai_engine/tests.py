import io
from decimal import Decimal

from django.test import TestCase, override_settings
from PIL import Image

from ai_engine.services import (RuleBasedEngine, analyze_disease,
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


class KnowledgeBaseTests(TestCase):
    def test_available_crops(self):
        crops = get_available_crops()
        self.assertIn('Tomato', crops)
        self.assertIn('Maize', crops)

    def test_disease_info_fallback(self):
        info = get_disease_info('Maize Rust')
        self.assertIsNotNone(info)
        self.assertEqual(info['disease_name'], 'Maize Rust')

    def test_engine_info(self):
        info = get_engine_info()
        self.assertEqual(info['status'], 'ok')
        self.assertIn('engine', info)

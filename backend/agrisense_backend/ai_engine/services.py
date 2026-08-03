"""
AgriSense AI plant-pathology engine.

Architecture
------------
The engine exposes a single entry point, ``analyze_disease(image, crop_type)``,
that every caller (REST view, admin tools) uses. It resolves the diagnosis
through an ordered pipeline:

1. **Knowledge base lookup** — the admin-managed ``diagnosis.Disease`` table is
   the source of truth. Diseases added/edited by administrators through the
   "Content Management" console immediately change inference output.
2. **Bundled fallback** — if the knowledge base has no entry for the crop, the
   curated built-in dictionary is used (works offline, zero setup).
3. **Inference backends** —
   * ``RuleBasedEngine`` (default): extracts lightweight color/texture features
     from the uploaded photo (Pillow) and scores the candidate diseases by
     feature distance. Fully deterministic, dependency-light and testable —
     the same photo always yields the same diagnosis and confidence.
   * ``OpenRouterEngine`` (primary): submits a privacy-scrubbed image to a
     configured vision model, constrained by a strict JSON schema to diseases
     already reviewed in the database for the selected crop.
   * ``TensorFlowEngine`` (optional local): loads a Keras `.keras`/`.h5`
     artifact and exact output class map for offline CNN inference.
"""

import hashlib
import logging
import math
import threading
from datetime import datetime, timedelta
from decimal import Decimal

from django.conf import settings

from .class_mapping import (ClassMapError, ModelClass, find_class_map,
                            load_class_map, parse_class_map)
from .openrouter_client import (OpenRouterResponseError,
                                OpenRouterUnavailableError,
                                OpenRouterVisionClient)

logger = logging.getLogger('agrisense.ai')

# Bundled fallback knowledge base (mirrors the seeded Disease rows).
# The authoritative source at runtime is the `diagnosis.Disease` table.
FALLBACK_DISEASE_DATABASE = {
    'Tomato': [
        {
            'disease_name': 'Tomato Late Blight',
            'pathogen': 'Phytophthora infestans',
            'symptoms': 'Dark, water-soaked lesions on leaves and stems. White fuzzy growth on leaf undersides in humid conditions. Rapid plant collapse.',
            'causes': 'Oomycete pathogen thriving in cool, wet weather (15-25°C). Spreads rapidly via wind and water splash.',
            'severity': 'high',
            'prevention': 'Use resistant varieties (e.g., Defiant, Mountain Magic). Ensure proper plant spacing for air circulation. Avoid overhead irrigation. Apply preventive fungicide during wet seasons.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Apply Mancozeb 80% WP (50g/20L) or Metalaxyl + Mancozeb. For organic: Copper hydroxide.',
            'instructions': 'Remove and destroy all infected plant material. Apply fungicide immediately. Repeat every 7-10 days. Treat entire field, not just visible infections.',
            'duration': 21,
        },
        {
            'disease_name': 'Tomato Early Blight',
            'pathogen': 'Alternaria solani',
            'symptoms': 'Dark concentric ring spots on older leaves first. Yellowing around spots. Stem lesions near soil.',
            'causes': 'Fungal pathogen. Favored by warm temperatures (24-29°C) and high humidity. Overhead watering increases spread.',
            'severity': 'medium',
            'prevention': 'Mulch around plants to prevent soil splash. Remove lower leaves. Rotate crops (3-year cycle). Use drip irrigation.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Chlorothalonil or Azoxystrobin. Organic option: Bacillus subtilis.',
            'instructions': 'Remove affected lower leaves. Apply fungicide starting at first sign. Cover both leaf surfaces. Reapply after rain.',
            'duration': 14,
        },
        {
            'disease_name': 'Tomato Bacterial Wilt',
            'pathogen': 'Ralstonia solanacearum',
            'symptoms': 'Rapid wilting of entire plant without yellowing. Brown discoloration of vascular tissue. Bacterial streaming from cut stems.',
            'causes': 'Soil-borne bacteria. Enters through roots. Thrives in warm (35°C), wet conditions.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Solarize soil before planting. Practice 3-year crop rotation. Avoid wounding roots.',
            'medication': 'No effective chemical treatment. Remove and destroy infected plants immediately.',
            'instructions': 'Remove infected plants and surrounding soil. Do NOT compost. Treat tools with bleach. Plant resistant varieties in affected areas.',
            'duration': 0,
        },
    ],
    'Maize': [
        {
            'disease_name': 'Maize Rust',
            'pathogen': 'Puccinia sorghi',
            'symptoms': 'Small, elongated orange-brown pustules on both leaf surfaces. Leaves may turn yellow and die prematurely.',
            'causes': 'Fungal pathogen. Favored by moderate temperatures (17-23°C) and high humidity/dew.',
            'severity': 'medium',
            'prevention': 'Plant resistant hybrids. Ensure adequate plant spacing. Avoid late planting. Remove crop debris after harvest.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Propiconazole or Tebuconazole (250ml/ha).',
            'instructions': 'Apply at first sign of pustules. Spray when wind is calm. Repeat after 14 days if needed.',
            'duration': 14,
        },
        {
            'disease_name': 'Maize Gray Leaf Spot',
            'pathogen': 'Cercospora zeae-maydis',
            'symptoms': 'Rectangular gray to tan lesions bounded by leaf veins. Lesions can coalesce, killing entire leaves.',
            'causes': 'Fungal pathogen. Favored by warm, humid conditions and reduced tillage.',
            'severity': 'high',
            'prevention': 'Use resistant hybrids. Rotate with non-host crops. Till soil to bury crop residue. Ensure proper plant spacing.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Azoxystrobin or Pyraclostrobin at tasseling stage.',
            'instructions': 'Apply fungicide at VT (tasseling) stage if disease is present on lower leaves. One application usually sufficient.',
            'duration': 14,
        },
    ],
    'Cassava': [
        {
            'disease_name': 'Cassava Mosaic Disease',
            'pathogen': 'Cassava mosaic virus (CMV)',
            'symptoms': 'Mosaic pattern of light and dark green on leaves. Leaf distortion, curling, and reduction in size. Stunted growth.',
            'causes': 'Viral disease transmitted by whitefly (Bemisia tabaci). Also spread through infected cuttings.',
            'severity': 'high',
            'prevention': 'Use certified virus-free planting material. Plant resistant varieties (e.g., NAROCASS 1). Control whitefly populations. Remove and destroy infected plants early.',
            'medication': 'No chemical treatment for virus. Control whiteflies with Neem oil or Imidacloprid.',
            'instructions': 'Remove infected plants immediately. Plant resistant varieties. Use clean cuttings from healthy plants. Monitor for whiteflies weekly.',
            'duration': 0,
        },
        {
            'disease_name': 'Cassava Bacterial Blight',
            'pathogen': 'Xanthomonas axonopodis pv. manihotis',
            'symptoms': 'Angular water-soaked leaf spots. Wilting and death of branches. Gummy exudate from stem lesions.',
            'causes': 'Bacterial pathogen. Spread by rain splash, contaminated tools, and infected cuttings.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Practice crop rotation. Disinfect tools between plants. Avoid overhead irrigation.',
            'medication': 'Copper-based bactericides can reduce spread. No cure for infected plants.',
            'instructions': 'Cut and burn infected branches below the lesion. Disinfect tools with 10% bleach. Apply copper spray to healthy plants preventively.',
            'duration': 0,
        },
    ],
    'Pepper': [
        {
            'disease_name': 'Pepper Anthracnose',
            'pathogen': 'Colletotrichum spp.',
            'symptoms': 'Sunken, circular lesions on fruits. Concentric rings in lesions. Pre and post-harvest fruit rot.',
            'causes': 'Fungal pathogen. Spread by rain splash. Favored by warm, humid conditions.',
            'severity': 'high',
            'prevention': 'Use resistant varieties. Mulch to prevent soil splash. Harvest fruits at maturity. Avoid wounding fruits.',
            'treatment_type': 'Fungicide Application',
            'medication': 'Mancozeb or Azoxystrobin. Apply preventively before rainy season.',
            'instructions': 'Apply fungicide at flowering and fruit set. Repeat every 7-10 days during wet periods. Harvest promptly when mature.',
            'duration': 21,
        },
    ],
    'Cocoa': [
        {
            'disease_name': 'Cocoa Black Pod',
            'pathogen': 'Phytophthora megakarya',
            'symptoms': 'Brown patches on pods that turn dark brown/black. Pod rotation. Internal bean damage.',
            'causes': 'Oomycete pathogen. Thrives in wet conditions. Primary source is infected pod husks on ground.',
            'severity': 'high',
            'prevention': 'Regular pod harvesting. Remove and destroy infected pods. Prune trees for better air circulation. Improve drainage.',
            'medication': 'Fungicide (Metalaxyl + Mancozeb) spray on pods. Cadusafos for swollen shoot vector control.',
            'instructions': 'Remove all infected pods from tree and ground. Spray remaining pods with fungicide. Repeat monthly during rainy season.',
            'duration': 30,
        },
    ],
}

# Signature features per disease class used by the rule-based scorer.
# (mean_green, mean_red, brown_lesion_fraction) normalized to [0,1].
# Values are heuristics derived from typical lesion appearance; they give the
# demo engine deterministic, image-dependent behaviour instead of randomness.
DISEASE_SIGNATURES = {
    'Tomato Late Blight': (0.42, 0.58, 0.62),
    'Tomato Early Blight': (0.50, 0.55, 0.45),
    'Tomato Bacterial Wilt': (0.35, 0.40, 0.30),
    'Maize Rust': (0.55, 0.62, 0.38),
    'Maize Gray Leaf Spot': (0.48, 0.52, 0.42),
    'Cassava Mosaic Disease': (0.60, 0.45, 0.18),
    'Cassava Bacterial Blight': (0.52, 0.48, 0.35),
    'Pepper Anthracnose': (0.46, 0.60, 0.55),
    'Cocoa Black Pod': (0.40, 0.55, 0.58),
}


class AIEngineError(RuntimeError):
    """Base exception for safe, user-facing AI engine failures."""


class AIEngineUnavailable(AIEngineError):
    """The configured trained model cannot currently serve inference."""


class AIInferenceError(AIEngineError):
    """A configured model failed while processing an image."""


class PlantPathologyEngine:
    """Interface shared by the demo heuristic and trained model adapters."""

    engine_name = 'unknown'
    model_version = 'unknown'
    is_trained_model = False

    @property
    def available(self):
        return True

    @property
    def supported_crops(self):
        return []

    def analyze(self, image, crop_type):
        raise NotImplementedError


class RuleBasedEngine(PlantPathologyEngine):
    """Deterministic feature-scoring engine.

    Extracts (mean_green, mean_red, lesion_fraction) features from the photo
    and scores candidate diseases by weighted Euclidean distance.
    """

    engine_name = 'rule-based'
    model_version = 'v1.0-rules'

    def _extract_features(self, image_file):
        """Return (features, ok_flag). Falls back to neutral features when
        Pillow cannot parse the image (e.g. corrupted uploads)."""
        default = (0.5, 0.5, 0.3), False
        try:
            from PIL import Image, ImageStat
            image = Image.open(image_file).convert('RGB')
            image.thumbnail((128, 128))
            stat = ImageStat.Stat(image)
            mean_rgb = [m / 255.0 for m in stat.mean[:3]]
            # Brownish/dark lesion heuristic: pixels where red dominates green
            # and value is mid-dark.
            pixels = list(image.getdata())
            lesion_count = sum(
                1 for r, g, b in pixels
                if r > g and r > 90 and r < 200 and (r - g) > 25
            )
            lesion_fraction = lesion_count / max(len(pixels), 1)
            return (mean_rgb[1], mean_rgb[0], lesion_fraction), True
        except Exception:
            return default

    # Healthy signature: a clearly healthy leaf is green-dominant with no lesion.
    # The scorer returns this when the image strongly resembles a healthy leaf,
    # giving the "no disease" outcome the spec expects.
    HEALTHY_SIGNATURE = (0.62, 0.40, 0.08)  # (mean_green, mean_red, lesion_fraction)

    def _score(self, features, candidate_name):
        fx = DISEASE_SIGNATURES.get(candidate_name, (0.5, 0.5, 0.4))
        distance = sum((a - b) ** 2 for a, b in zip(features, fx)) ** 0.5
        # Max distance across feature space is sqrt(3); map to a 78–97% score.
        confidence = 97.0 - min(19.0, (distance / 1.732) * 19.0)
        return confidence

    @staticmethod
    def _calibrate(raw):
        """Temperature scaling (calibration) to avoid overclaiming confidence.

        Pulls every score toward a neutral 82%: a marginal match can no longer
        claim ~95% certainty. Kept monotonic so ranking is unchanged, but the
        absolute number is an honest confidence estimate.
        """
        from django.conf import settings
        temperature = getattr(settings, 'AI_TEMPERATURE', 1.6)
        neutral = 82.0
        calibrated = neutral + (raw - neutral) / temperature
        return max(50.0, min(97.0, calibrated))

    @staticmethod
    def _looks_healthy(features):
        """A clearly healthy leaf: green-dominant and essentially no lesion."""
        mean_green, _mean_red, lesion = features
        return mean_green > 0.55 and lesion < 0.10

    def analyze(self, image, crop_type):
        features, ok = self._extract_features(image)

        # Healthy outcome first: a healthy leaf is not a disease.
        if self._looks_healthy(features):
            return self._build_healthy_result(ok)

        diseases = self._candidates(crop_type)
        if not diseases:
            diseases = self._candidates('Tomato')

        scored = [(self._score(features, d['disease_name']), d) for d in diseases]
        scored.sort(key=lambda pair: pair[0], reverse=True)
        raw, disease = scored[0]
        confidence = self._calibrate(raw)

        # Low confidence -> honest "inconclusive" outcome instead of a wrong
        # confident diagnosis.
        from django.conf import settings
        low_threshold = getattr(settings, 'AI_LOW_CONFIDENCE_THRESHOLD', 80.0)
        if confidence < low_threshold:
            return self._build_inconclusive_result(crop_type, confidence, ok)

        return self._build_result(disease, confidence, ok)

    @staticmethod
    def _build_healthy_result(ok):
        return {
            'is_healthy': True,
            'disease_name': 'Healthy',
            'confidence': Decimal('88.0'),
            'severity': 'low',
            'symptoms': 'No disease symptoms detected.',
            'causes': 'The plant appears healthy.',
            'prevention': 'Continue good agronomic practices: proper watering, '
                          'spacing, soil care and regular monitoring.',
            'treatment_type': 'No treatment required',
            'medication': 'No pesticide needed. Maintain plant health with '
                          'balanced nutrients.',
            'instructions': 'Keep monitoring for early signs of pests or disease.',
            'duration': 0,
            'follow_up_date': None,
            'engine': 'rule-based',
            'trained_model': False,
            'model_version': 'v2.0-rules',
            'image_parsed': ok,
        }

    @staticmethod
    def _build_inconclusive_result(crop_type, confidence, ok):
        return {
            'is_healthy': False,
            'disease_name': 'Inconclusive',
            'confidence': Decimal(str(round(confidence, 1))),
            'severity': 'unknown',
            'symptoms': 'The image could not be confidently matched to a known disease.',
            'causes': 'Low image clarity, unusual lighting, or an uncommon presentation.',
            'prevention': 'Retake the photo in good, even lighting, close to the '
                          'affected area, and include the whole leaf.',
            'treatment_type': 'Consult an agronomist',
            'medication': 'Do not apply chemicals without a confirmed diagnosis.',
            'instructions': f'Share this photo with a local agronomist or AgriSense '
                            f'support for a {crop_type} follow-up.',
            'duration': 0,
            'follow_up_date': None,
            'engine': 'rule-based',
            'trained_model': False,
            'model_version': 'v2.0-rules',
            'image_parsed': ok,
            'low_confidence': True,
        }

    def _candidates(self, crop_type):
        from diagnosis.models import Disease
        db_rows = Disease.objects.filter(crop_name__iexact=crop_type)
        if db_rows.exists():
            return [
                {
                    'disease_name': row.disease_name,
                    'pathogen': row.pathogen,
                    'symptoms': row.symptoms,
                    'causes': row.causes,
                    'severity': row.severity,
                    'prevention': row.prevention,
                    'treatment_type': row.treatment_type,
                    'medication': row.medication,
                    'instructions': row.instructions,
                    'duration': row.duration,
                }
                for row in db_rows
            ]
        return FALLBACK_DISEASE_DATABASE.get(crop_type, [])

    @staticmethod
    def _build_result(disease, confidence, ok):
        duration = int(disease.get('duration', 14))
        return {
            'symptoms': disease.get('symptoms', ''),
            'confidence': Decimal(str(round(max(0.0, min(97.0, confidence)), 1))),
            'disease_name': disease.get('disease_name', 'Unknown'),
            'severity': disease.get('severity', 'low'),
            'causes': disease.get('causes', ''),
            'prevention': disease.get('prevention', ''),
            'treatment_type': disease.get('treatment_type', 'Cultural Management'),
            'medication': disease.get('medication', 'No chemical treatment recommended'),
            'instructions': disease.get('instructions', 'Follow integrated pest management practices.'),
            'duration': duration,
            'follow_up_date': (datetime.now() + timedelta(days=duration)).date(),
            'engine': 'rule-based',
            'trained_model': False,
            'model_version': 'v2.0-rules',
            'image_parsed': ok,
        }


class OpenRouterEngine(PlantPathologyEngine):
    """Remote vision engine restricted to reviewed database diseases.

    OpenRouter performs visual screening only. Candidate names and reviewed
    symptoms are sent as an allow-list; all treatment content is resolved from
    the local database after the response passes server-side validation.
    """

    engine_name = 'openrouter-vision'
    is_trained_model = True

    def __init__(self, client=None):
        self._client = client or OpenRouterVisionClient()
        self.model_version = self._client.model or 'unconfigured'

    @property
    def available(self):
        return self._client.available and not self._client.configuration_error

    @property
    def load_error(self):
        return self._client.configuration_error

    @staticmethod
    def _reviewed_candidates(crop_type):
        """Return only admin-reviewed Disease rows—never bundled guesses."""
        from diagnosis.models import Disease

        return [
            {
                'disease_name': row.disease_name,
                'pathogen': row.pathogen,
                'symptoms': row.symptoms,
                'causes': row.causes,
                'severity': row.severity,
                'prevention': row.prevention,
                'treatment_type': row.treatment_type,
                'medication': row.medication,
                'instructions': row.instructions,
                'duration': row.duration,
            }
            for row in Disease.objects.filter(
                crop_name__iexact=crop_type).order_by('disease_name')
        ]

    def _fallback(self, image, crop_type, reason):
        if not bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)):
            raise AIEngineUnavailable(reason)
        logger.warning('Using rule-based AI fallback after OpenRouter failure: %s',
                       reason)
        result = RuleBasedEngine().analyze(image, crop_type)
        result['fallback_reason'] = reason
        result['trained_model'] = False
        return result

    def analyze(self, image, crop_type):
        if not self.available:
            return self._fallback(
                image, crop_type,
                self.load_error or 'The OpenRouter vision engine is unavailable.')

        candidates = self._reviewed_candidates(crop_type)
        if not candidates:
            raise AIInferenceError(
                f'No reviewed diseases exist in the database for {crop_type!r}.')
        names = [item['disease_name'].casefold() for item in candidates]
        if len(names) != len(set(names)):
            raise AIInferenceError(
                f'Duplicate reviewed disease names exist for {crop_type!r}.')

        try:
            prediction = self._client.classify(image, crop_type, candidates)
        except OpenRouterUnavailableError as exc:
            return self._fallback(image, crop_type, str(exc))
        except OpenRouterResponseError as exc:
            if bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)):
                return self._fallback(image, crop_type, str(exc))
            raise AIInferenceError(str(exc)) from exc

        configured_cap = min(100.0, max(0.0, float(getattr(
            settings, 'OPENROUTER_MAX_CONFIDENCE', 95.0))))
        confidence = min(max(prediction.confidence, 0.0), configured_cap)
        threshold = min(100.0, max(0.0, float(getattr(
            settings, 'OPENROUTER_CONFIDENCE_THRESHOLD', 70.0))))
        if prediction.outcome == 'inconclusive':
            # The model may be highly confident that it cannot classify the
            # image; that is not a high disease-match confidence for the UI.
            confidence = min(confidence, max(0.0, threshold - 1.0))
        metadata = {
            'engine': self.engine_name,
            'trained_model': True,
            'model_version': prediction.model,
            'model_label': prediction.disease_name,
            'alternatives': [{
                'disease_name': prediction.disease_name,
                'confidence': round(confidence, 2),
            }],
            'visual_evidence': list(prediction.evidence),
        }

        if prediction.outcome == 'inconclusive' or confidence < threshold:
            result = RuleBasedEngine._build_inconclusive_result(
                crop_type, confidence, True)
            result.update(metadata)
            result['is_inconclusive'] = True
            result['low_confidence'] = True
            return result

        if prediction.outcome == 'healthy':
            result = RuleBasedEngine._build_healthy_result(True)
            result.update(metadata)
            result['confidence'] = Decimal(str(round(confidence, 2)))
            return result

        # A second server-side exact allow-list check ensures a provider cannot
        # select another crop or hallucinate a disease even if it ignores schema.
        reviewed_by_name = {
            item['disease_name'].casefold(): item for item in candidates
        }
        disease = reviewed_by_name.get(prediction.disease_name.casefold())
        if disease is None:
            raise AIInferenceError(
                'OpenRouter selected a disease that is not reviewed for this crop.')

        result = RuleBasedEngine._build_result(disease, confidence, True)
        result.update(metadata)
        result.update({
            'is_healthy': False,
            'is_inconclusive': False,
            'knowledge_base_match': True,
        })
        return result


class TensorFlowEngine(PlantPathologyEngine):
    """Keras/TensorFlow image-classification backend.

    Unlike the previous placeholder, this adapter performs the complete
    inference path: model loading, EXIF-safe image preprocessing, prediction,
    probability calibration, crop-aware class selection, class-manifest lookup,
    and treatment-plan resolution from the knowledge base.

    A class manifest is mandatory.  Model output order is a training artifact
    and must never be guessed from database row order.
    """

    engine_name = 'tensorflow-cnn'
    is_trained_model = True
    _UNSET = object()

    def __init__(self, model=_UNSET, class_map=None, preprocessor=None):
        self._model = None
        self._classes = []
        self._preprocessor = preprocessor
        self._predict_lock = threading.Lock()
        self._load_error = ''
        self._model_path = str(getattr(settings, 'AI_MODEL_PATH', '') or '').strip()
        self.model_version = str(
            getattr(settings, 'AI_MODEL_VERSION', '') or 'unversioned-model')

        try:
            if class_map is not None:
                if all(isinstance(item, ModelClass) for item in class_map):
                    self._classes = sorted(class_map, key=lambda item: item.index)
                else:
                    self._classes = parse_class_map(class_map)
            elif self._model_path:
                map_path = find_class_map(
                    self._model_path,
                    str(getattr(settings, 'AI_CLASS_MAP_PATH', '') or '').strip(),
                )
                if map_path is None:
                    raise ClassMapError(
                        'No class manifest found. Set AI_CLASS_MAP_PATH or place '
                        'class_map.json beside the model.')
                self._classes = load_class_map(map_path)
            else:
                raise ClassMapError('AI_MODEL_PATH is not configured.')
        except ClassMapError as exc:
            self._load_error = str(exc)

        # Dependency injection keeps inference logic unit-testable without the
        # optional, heavyweight TensorFlow package in normal backend installs.
        if model is not self._UNSET:
            self._model = model
            if self._model is None and not self._load_error:
                self._load_error = 'No model instance was supplied.'
            return

        if self._load_error:
            return
        try:
            import tensorflow as tf
            self._model = tf.keras.models.load_model(self._model_path, compile=False)
        except Exception as exc:  # optional dependency/artifact is environment-specific
            self._load_error = (
                f'Could not load TensorFlow model at {self._model_path!r}: '
                f'{type(exc).__name__}: {exc}')
            logger.warning('AI model unavailable: %s', self._load_error)
            self._model = None

    @property
    def available(self):
        return self._model is not None and bool(self._classes)

    @property
    def load_error(self):
        return self._load_error

    @property
    def supported_crops(self):
        return list(dict.fromkeys(item.crop_type for item in self._classes))

    def _input_size(self):
        configured = getattr(settings, 'AI_MODEL_INPUT_SIZE', '224x224')
        if isinstance(configured, (tuple, list)) and len(configured) == 2:
            return int(configured[0]), int(configured[1])
        value = str(configured).lower().replace(',', 'x').replace(' ', '')
        try:
            width, height = value.split('x', 1)
            width, height = int(width), int(height)
            if width > 0 and height > 0:
                return width, height
        except (TypeError, ValueError):
            pass
        raise AIEngineUnavailable(
            'AI_MODEL_INPUT_SIZE must look like 224x224 (width x height).')

    def _prepare_image(self, image_file):
        if self._preprocessor is not None:
            return self._preprocessor(image_file)

        try:
            import numpy as np
            from PIL import Image, ImageOps

            image_file.seek(0)
            image = ImageOps.exif_transpose(Image.open(image_file)).convert('RGB')
            width, height = self._input_size()
            image = ImageOps.fit(
                image,
                (width, height),
                method=Image.Resampling.BILINEAR,
                centering=(0.5, 0.5),
            )
            array = np.asarray(image, dtype='float32')
            normalization = str(getattr(
                settings, 'AI_MODEL_NORMALIZATION', 'zero_one')).strip().lower()
            if normalization in ('zero_one', '0_1', 'rescale'):
                array /= 255.0
            elif normalization in ('minus_one_one', '-1_1', 'mobilenet'):
                array = array / 127.5 - 1.0
            elif normalization == 'imagenet':
                array /= 255.0
                array = (array - np.asarray([0.485, 0.456, 0.406], dtype='float32'))
                array /= np.asarray([0.229, 0.224, 0.225], dtype='float32')
            elif normalization not in ('none', 'raw'):
                raise AIEngineUnavailable(
                    'AI_MODEL_NORMALIZATION must be zero_one, minus_one_one, '
                    'imagenet, or none.')
            return np.expand_dims(array, axis=0)
        except AIEngineError:
            raise
        except Exception as exc:
            raise AIInferenceError(
                f'Could not preprocess the uploaded image: {exc}') from exc
        finally:
            try:
                image_file.seek(0)
            except Exception:
                pass

    @staticmethod
    def _prediction_vector(output):
        """Convert a Keras/Tensor/NumPy output to a flat Python float list."""
        if isinstance(output, dict):
            output_name = str(getattr(settings, 'AI_MODEL_OUTPUT_NAME', '') or '')
            if output_name:
                if output_name not in output:
                    raise AIInferenceError(
                        f'Model output {output_name!r} was not returned.')
                output = output[output_name]
            elif len(output) == 1:
                output = next(iter(output.values()))
            else:
                raise AIInferenceError(
                    'Model returned multiple named outputs; set AI_MODEL_OUTPUT_NAME.')

        if hasattr(output, 'numpy'):
            output = output.numpy()
        if hasattr(output, 'tolist'):
            output = output.tolist()

        # Remove batch/single-output wrappers while retaining the class axis.
        while isinstance(output, (list, tuple)) and len(output) == 1 \
                and isinstance(output[0], (list, tuple)):
            output = output[0]
        if not isinstance(output, (list, tuple)) or not output:
            raise AIInferenceError('Model returned an empty or unsupported output.')
        if any(isinstance(value, (list, tuple, dict)) for value in output):
            raise AIInferenceError(
                'Model output must have shape [batch, classes] with batch size 1.')
        try:
            vector = [float(value) for value in output]
        except (TypeError, ValueError) as exc:
            raise AIInferenceError('Model output contains non-numeric values.') from exc
        if not all(math.isfinite(value) for value in vector):
            raise AIInferenceError('Model output contains NaN or infinite values.')
        return vector

    @staticmethod
    def _probabilities(vector):
        """Accept logits or probabilities and apply optional temperature scaling."""
        temperature = float(getattr(settings, 'AI_MODEL_TEMPERATURE', 1.0))
        if temperature <= 0:
            raise AIEngineUnavailable('AI_MODEL_TEMPERATURE must be greater than zero.')

        looks_like_probabilities = (
            all(0.0 <= value <= 1.0 for value in vector)
            and abs(sum(vector) - 1.0) <= 0.02
        )
        if looks_like_probabilities:
            # Temperature scaling in log-probability space.
            logits = [math.log(max(value, 1e-12)) / temperature for value in vector]
        else:
            logits = [value / temperature for value in vector]
        maximum = max(logits)
        exponentials = [math.exp(value - maximum) for value in logits]
        total = sum(exponentials)
        if total <= 0:
            raise AIInferenceError('Model probabilities could not be normalised.')
        return [value / total for value in exponentials]

    def _predict(self, batch):
        try:
            # A single model instance is shared by request threads. Serialising
            # predict protects Keras backends/exported graphs that are not
            # re-entrant while preprocessing remains concurrent.
            with self._predict_lock:
                try:
                    output = self._model.predict(batch, verbose=0)
                except TypeError:
                    # Some exported/fake model signatures do not accept verbose.
                    output = self._model.predict(batch)
            vector = self._prediction_vector(output)
            expected_count = max(item.index for item in self._classes) + 1
            strict_count = bool(getattr(settings, 'AI_STRICT_CLASS_COUNT', True))
            if len(vector) < expected_count or (strict_count and len(vector) != expected_count):
                raise AIInferenceError(
                    f'Model returned {len(vector)} classes but the manifest describes '
                    f'{expected_count}. Use the exact class map exported during training.')
            return self._probabilities(vector)
        except AIEngineError:
            raise
        except Exception as exc:
            raise AIInferenceError(f'TensorFlow inference failed: {exc}') from exc

    def _fallback(self, image, crop_type, reason):
        if not bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)):
            raise AIEngineUnavailable(reason)
        logger.warning('Using rule-based AI fallback: %s', reason)
        result = RuleBasedEngine().analyze(image, crop_type)
        result['fallback_reason'] = reason
        result['trained_model'] = False
        return result

    def analyze(self, image, crop_type):
        if not self.available:
            reason = self._load_error or 'The configured TensorFlow model is unavailable.'
            return self._fallback(image, crop_type, reason)

        try:
            probabilities = self._predict(self._prepare_image(image))
            crop_key = str(crop_type).strip().casefold()
            eligible = [item for item in self._classes
                        if item.crop_type.casefold() == crop_key]
            if not eligible:
                raise AIInferenceError(
                    f'The trained model has no classes for {crop_type!r}.')

            ranked = sorted(
                ((probabilities[item.index], item) for item in eligible),
                key=lambda pair: pair[0], reverse=True,
            )
            probability, predicted = ranked[0]
            confidence = probability * 100.0
            alternatives = [
                {
                    'label': item.label,
                    'disease_name': 'Healthy' if item.is_healthy else item.disease_name,
                    'confidence': round(score * 100.0, 2),
                }
                for score, item in ranked[:3]
            ]

            threshold = float(getattr(
                settings, 'AI_MODEL_CONFIDENCE_THRESHOLD', 65.0))
            if confidence < threshold:
                result = RuleBasedEngine._build_inconclusive_result(
                    crop_type, confidence, True)
                result.update({
                    'engine': self.engine_name,
                    'model_version': self.model_version,
                    'model_label': predicted.label,
                    'alternatives': alternatives,
                    'trained_model': True,
                })
                return result

            if predicted.is_healthy:
                result = RuleBasedEngine._build_healthy_result(True)
                result.update({
                    'confidence': Decimal(str(round(confidence, 2))),
                    'engine': self.engine_name,
                    'model_version': self.model_version,
                    'model_label': predicted.label,
                    'alternatives': alternatives,
                    'trained_model': True,
                })
                return result

            disease = get_disease_info(predicted.disease_name)
            knowledge_base_match = disease is not None
            if disease is None:
                # The classifier can know more classes than the treatment
                # knowledge base.  Preserve the classification but never invent
                # pesticide instructions for an unmapped disease.
                disease = {
                    'disease_name': predicted.disease_name,
                    'symptoms': f'The trained image model matched {predicted.label}.',
                    'causes': 'A treatment record for this model class has not yet '
                              'been reviewed in the AgriSense knowledge base.',
                    'severity': 'unknown',
                    'prevention': 'Isolate affected material where practical and '
                                  'seek local agronomic confirmation.',
                    'treatment_type': 'Consult an agronomist',
                    'medication': 'Do not apply chemicals until the diagnosis is '
                                  'confirmed by a qualified advisor.',
                    'instructions': 'Ask an administrator to map this model class '
                                    'to a reviewed disease record.',
                    'duration': 0,
                }

            result = RuleBasedEngine._build_result(disease, confidence, True)
            result.update({
                'is_healthy': False,
                'is_inconclusive': not knowledge_base_match,
                'engine': self.engine_name,
                'model_version': self.model_version,
                'model_label': predicted.label,
                'alternatives': alternatives,
                'trained_model': True,
                'knowledge_base_match': knowledge_base_match,
            })
            return result
        except AIEngineError as exc:
            if bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)):
                return self._fallback(image, crop_type, str(exc))
            raise
        except Exception as exc:
            reason = f'Unexpected TensorFlow inference failure: {exc}'
            if bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)):
                return self._fallback(image, crop_type, reason)
            raise AIInferenceError(reason) from exc


_ENGINE_CACHE = {}


def _engine_cache_key():
    api_key = str(getattr(settings, 'OPENROUTER_API_KEY', '') or '')
    key_fingerprint = hashlib.sha256(api_key.encode()).hexdigest()[:12] \
        if api_key else ''
    return (
        str(getattr(settings, 'AI_ENGINE', 'openrouter')).strip().lower(),
        str(getattr(settings, 'AI_MODEL_PATH', '') or ''),
        str(getattr(settings, 'AI_CLASS_MAP_PATH', '') or ''),
        str(getattr(settings, 'AI_MODEL_VERSION', '') or ''),
        str(getattr(settings, 'AI_MODEL_INPUT_SIZE', '224x224')),
        str(getattr(settings, 'AI_MODEL_NORMALIZATION', 'zero_one')),
        bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False)),
        bool(getattr(settings, 'AI_REQUIRE_TRAINED_MODEL', False)),
        key_fingerprint,
        str(getattr(settings, 'OPENROUTER_MODEL', '') or ''),
        str(getattr(settings, 'OPENROUTER_BASE_URL', '') or ''),
    )


def reset_engine_cache():
    """Clear process-local model instances (primarily useful for tests/reloads)."""
    _ENGINE_CACHE.clear()


def get_engine():
    """Return the configured engine, loading a trained model once per process."""
    key = _engine_cache_key()
    if key not in _ENGINE_CACHE:
        requested = key[0]
        if requested in ('openrouter', 'openrouter-vision', 'cloud'):
            engine = OpenRouterEngine()
        elif requested in ('tensorflow', 'keras', 'tf'):
            engine = TensorFlowEngine()
        elif requested == 'auto':
            # Prefer configured cloud vision, then a local artifact, and expose
            # the labelled heuristic only when neither real model is available.
            if str(getattr(settings, 'OPENROUTER_API_KEY', '') or '').strip():
                engine = OpenRouterEngine()
            elif key[1]:
                engine = TensorFlowEngine()
            else:
                engine = RuleBasedEngine()
        elif requested in ('rules', 'rule-based', 'heuristic'):
            engine = RuleBasedEngine()
        else:
            raise AIEngineUnavailable(
                f'Unknown AI_ENGINE={requested!r}; use openrouter, tensorflow, '
                f'auto, or rules.')
        _ENGINE_CACHE[key] = engine
    return _ENGINE_CACHE[key]


def analyze_disease(image, crop_type):
    """Analyze a plant image through the configured inference backend."""
    if not str(crop_type or '').strip():
        raise AIInferenceError('A crop type is required for model inference.')
    engine = get_engine()
    if (isinstance(engine, RuleBasedEngine)
            and bool(getattr(settings, 'AI_REQUIRE_TRAINED_MODEL', False))):
        raise AIEngineUnavailable(
            'A trained model is required but only the demo heuristic is configured.')
    return engine.analyze(image, str(crop_type).strip())


def get_engine_info():
    """Truthful readiness metadata for health checks and the admin console."""
    try:
        engine = get_engine()
    except AIEngineError as exc:
        return {
            'status': 'error',
            'engine': 'unavailable',
            'trained_model': False,
            'detail': str(exc),
        }

    if isinstance(engine, OpenRouterEngine):
        if not engine.available:
            fallback = bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False))
            detail = (engine.load_error or 'OpenRouter is unavailable.') \
                if settings.DEBUG else 'OpenRouter configuration failed readiness checks.'
            return {
                'status': 'degraded' if fallback else 'error',
                'engine': 'rule-based' if fallback else engine.engine_name,
                'requested_engine': engine.engine_name,
                'model_version': engine.model_version,
                'trained_model': False,
                'remote': True,
                'detail': detail,
            }
        return {
            'status': 'ok',
            'engine': engine.engine_name,
            'model_version': engine.model_version,
            'trained_model': True,
            'remote': True,
            'detail': ('OpenRouter vision is configured; availability is checked '
                       'on each diagnosis request.'),
        }

    if isinstance(engine, RuleBasedEngine):
        required = bool(getattr(settings, 'AI_REQUIRE_TRAINED_MODEL', False))
        return {
            'status': 'error' if required else 'degraded',
            'engine': engine.engine_name,
            'model_version': 'v2.0-rules',
            'trained_model': False,
            'detail': ('A trained model is required but only the demo heuristic is configured.'
                       if required else
                       'Demo heuristic only — no trained pathology model is configured.'),
        }
    if isinstance(engine, TensorFlowEngine) and not engine.available:
        fallback = bool(getattr(settings, 'AI_ALLOW_RULE_FALLBACK', False))
        detail = (engine.load_error or 'TensorFlow model unavailable.') \
            if settings.DEBUG else 'Configured model failed readiness checks.'
        return {
            'status': 'degraded' if fallback else 'error',
            'engine': 'rule-based' if fallback else engine.engine_name,
            'requested_engine': engine.engine_name,
            'model_version': engine.model_version,
            'trained_model': False,
            'detail': detail,
        }
    return {
        'status': 'ok',
        'engine': engine.engine_name,
        'model_version': engine.model_version,
        'trained_model': True,
        'classes': len(getattr(engine, '_classes', [])),
        'supported_crops': engine.supported_crops,
        'detail': f'{engine.model_version} — trained CNN inference ready',
    }


def get_available_crops():
    """Crops supported by the active model, or by the heuristic knowledge base."""
    try:
        engine = get_engine()
    except AIEngineError:
        engine = None
    if isinstance(engine, TensorFlowEngine) and engine.supported_crops:
        return engine.supported_crops

    from diagnosis.models import Disease
    db_crops = list(Disease.objects.values_list(
        'crop_name', flat=True).distinct().order_by('crop_name'))
    if isinstance(engine, OpenRouterEngine):
        # Cloud classification is deliberately limited to reviewed DB content.
        return db_crops
    return list(dict.fromkeys(
        [crop for crop in db_crops] + list(FALLBACK_DISEASE_DATABASE.keys())))


def get_disease_info(disease_name):
    """Look up a disease's full treatment record from DB, then bundled data."""
    from diagnosis.models import Disease
    row = Disease.objects.filter(disease_name__iexact=disease_name).first()
    if row:
        return {
            'disease_name': row.disease_name,
            'pathogen': row.pathogen,
            'symptoms': row.symptoms,
            'causes': row.causes,
            'severity': row.severity,
            'prevention': row.prevention,
            'treatment_type': row.treatment_type,
            'medication': row.medication,
            'instructions': row.instructions,
            'duration': row.duration,
        }
    for crop_diseases in FALLBACK_DISEASE_DATABASE.values():
        for disease in crop_diseases:
            if disease['disease_name'].lower() == disease_name.lower():
                return disease
    return None


def image_digest(image_file):
    """Content hash of an upload (used for diagnostics / dedupe)."""
    try:
        image_file.seek(0)
        digest = hashlib.sha256(image_file.read()).hexdigest()[:16]
        image_file.seek(0)
        return digest
    except Exception:
        return ''

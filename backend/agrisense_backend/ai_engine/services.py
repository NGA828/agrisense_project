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
   * ``TensorFlowEngine`` (optional): when ``AI_MODEL_PATH`` points to a
     trained artifact (Keras SavedModel/`.h5`), the image is preprocessed to
     224x224 and predicted with the model; the knowledge base supplies the
     treatment plan for the predicted class. Enable by setting
     ``AI_ENGINE=tensorflow``.
"""

import hashlib
import os
from datetime import datetime, timedelta
from decimal import Decimal

from django.conf import settings

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


class PlantPathologyEngine:
    """Pluggable inference engine (rule-based default, TF optional)."""

    engine_name = 'rule-based'
    model_version = 'fallback-1.0'

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

    def _score(self, features, candidate_name):
        fx = DISEASE_SIGNATURES.get(candidate_name, (0.5, 0.5, 0.4))
        distance = sum((a - b) ** 2 for a, b in zip(features, fx)) ** 0.5
        # Max distance across feature space is sqrt(3); map to a 78–97% score.
        confidence = 97.0 - min(19.0, (distance / 1.732) * 19.0)
        return confidence

    def analyze(self, image, crop_type):
        features, ok = self._extract_features(image)
        diseases = self._candidates(crop_type)
        if not diseases:
            diseases = self._candidates('Tomato')

        scored = [(self._score(features, d['disease_name']), d) for d in diseases]
        scored.sort(key=lambda pair: pair[0], reverse=True)
        confidence, disease = scored[0]
        return self._build_result(disease, confidence, ok)

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
            'model_version': 'v1.0-rules',
            'image_parsed': ok,
        }


class TensorFlowEngine(PlantPathologyEngine):
    """Optional CNN inference backend.

    Activated when ``AI_ENGINE=tensorflow`` and ``AI_MODEL_PATH`` points to a
    Keras SavedModel. The model must output a class index per trained crop
    dataset; the knowledge base maps that index/class to a treatment plan.
    """

    engine_name = 'tensorflow-cnn'
    model_version = 'unloaded'

    def __init__(self):
        self._model = None
        path = os.getenv('AI_MODEL_PATH', '')
        if path:
            try:
                import tensorflow as tf  # noqa: F401  (optional heavy dep)
                self._model = tf.keras.models.load_model(path)
                self.model_version = os.getenv('AI_MODEL_VERSION', 'cnn-1.0')
            except Exception:
                self._model = None

    @property
    def available(self):
        return self._model is not None

    def analyze(self, image, crop_type):
        if not self.available:
            # Graceful degradation to the deterministic engine.
            return RuleBasedEngine().analyze(image, crop_type)
        # NOTE: preprocessing & class-mapping depend on the trained dataset;
        # implement together with the model export notebook.
        raise NotImplementedError(
            'TensorFlow inference requires the class mapping layer for the '
            'trained artifact (see ai_engine/README).')


_ENGINE_CACHE = {}


def get_engine():
    """Return the configured engine (cached per process)."""
    engine = os.getenv('AI_ENGINE', 'rules')
    if engine not in _ENGINE_CACHE:
        if engine == 'tensorflow':
            _ENGINE_CACHE[engine] = TensorFlowEngine()
        else:
            _ENGINE_CACHE[engine] = RuleBasedEngine()
    return _ENGINE_CACHE[engine]


def analyze_disease(image, crop_type):
    """Public entry point: analyze a plant photo and return a diagnosis dict.

    ``image`` is a Django UploadedFile / file-like object; ``crop_type`` is the
    crop selected by the farmer (e.g. 'Tomato'). Returns a dict with the
    disease fields plus confidence, engine and model metadata.
    """
    engine = get_engine()
    result = engine.analyze(image, crop_type or 'Tomato')
    return result


def get_engine_info():
    """Metadata for health checks and admin "System Health" screen."""
    engine = get_engine()
    if isinstance(engine, TensorFlowEngine) and not engine.available:
        return {'status': 'ok', 'engine': 'rule-based',
                'detail': 'TensorFlow engine requested but model unavailable; '
                          'using rule-based fallback'}
    return {'status': 'ok', 'engine': engine.engine_name,
            'detail': f'{engine.model_version} — deterministic feature scoring'
                      if engine.engine_name == 'rule-based'
                      else f'{engine.model_version} — CNN inference'}


def get_available_crops():
    """Supported crop types (DB knowledge base first, bundled fallback second)."""
    from diagnosis.models import Disease
    db_crops = list(Disease.objects.values_list('crop_name', flat=True).distinct().order_by('crop_name'))
    merged = list(dict.fromkeys([c for c in db_crops] + list(FALLBACK_DISEASE_DATABASE.keys())))
    return merged


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

# AgriSense plant-pathology inference

## Engines

AgriSense uses a pluggable backend with three deliberately distinct modes:

1. `AI_ENGINE=openrouter` — **primary** cloud vision path. The default model is
   `nex-agi/nex-n2-pro:free`.
2. `AI_ENGINE=tensorflow` — optional local/offline Keras CNN with an exact class
   manifest.
3. `AI_ENGINE=rules` — deterministic colour/lesion heuristic for demos only. It
   is not a trained pathology model and health reports it as `degraded`.

## OpenRouter setup (primary)

Create an OpenRouter key and keep it only in the backend environment:

```dotenv
AI_ENGINE=openrouter
OPENROUTER_API_KEY=replace-in-the-private-server-environment
OPENROUTER_MODEL=nex-agi/nex-n2-pro:free
OPENROUTER_BASE_URL=https://openrouter.ai/api/v1
OPENROUTER_TIMEOUT_SECONDS=60
OPENROUTER_IMAGE_MAX_DIMENSION=1280
OPENROUTER_CONFIDENCE_THRESHOLD=70
OPENROUTER_MAX_CONFIDENCE=95
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
```

No OpenRouter SDK is required; the existing `requests` dependency calls the
OpenAI-compatible chat-completions endpoint.

### Database-only disease restriction

OpenRouter is not allowed to provide arbitrary diagnoses or treatments:

- Only `diagnosis.Disease` rows for the farmer-selected crop are loaded.
  Bundled fallback diseases are **not** eligible in OpenRouter mode.
- The request includes only each reviewed disease name, pathogen and reviewed
  symptoms. Medication, instructions and other treatment content are never sent.
- A strict JSON schema limits `disease_name` to `Healthy`, `Inconclusive`, or
  one of those exact reviewed database names.
- The backend repeats the allow-list check after receiving the response, so a
  provider that ignores the schema still cannot inject another disease.
- Unexpected response fields—including model-generated treatment advice—are
  rejected.
- Causes, prevention, medication, instructions, severity and duration are
  always copied from the matching local `Disease` row.
- Low confidence, poor image quality, crop mismatch or any unknown label becomes
  `Inconclusive`; chemicals are not recommended for uncertain results.

Before upload, the backend rotates the photo correctly, resizes it, converts it
to JPEG and strips EXIF metadata. The image is then sent as a private base64
data URL. Deployments must still disclose this third-party image processing to
users in their privacy notice.

The free model is suitable for prototypes and low-volume use. Free availability
and rate limits can change, and a general vision-language model is not a
field-validated plant pathology classifier. Keep agronomist confirmation in the
workflow and evaluate against representative local field images.

## Optional local TensorFlow model

Use Python 3.11 (the Docker image already does):

```bash
cd backend/agrisense_backend
pip install -r requirements.txt -r requirements-ai.txt
mkdir -p ai_models
```

Configure:

```dotenv
AI_ENGINE=tensorflow
AI_MODEL_PATH=/absolute/path/to/plant_disease_v3.keras
AI_CLASS_MAP_PATH=/absolute/path/to/plant_disease_v3.classes.json
AI_MODEL_VERSION=plant-disease-v3.2.0
AI_MODEL_INPUT_SIZE=224x224
AI_MODEL_NORMALIZATION=zero_one
AI_MODEL_CONFIDENCE_THRESHOLD=65
AI_MODEL_TEMPERATURE=1.0
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
```

A local classifier must accept one RGB image batch and return one class vector.
Its manifest must contain the exact training output order. The parser accepts an
explicit `classes` list, Keras `class_indices.json`, or Hugging Face `id2label`.
`model_manifests/plantvillage_38.json` is an integration example, not a complete
AgriSense model: PlantVillage does not cover Cassava or Cocoa.

## Readiness and failures

Verify configuration with:

```bash
python manage.py check
python manage.py runserver
curl http://localhost:8000/api/health/
```

A configured OpenRouter engine reports `openrouter-vision`. Health validates
configuration without making a billable model request; provider availability is
checked during diagnosis. Missing credentials, network failures, malformed JSON,
unknown diseases and provider errors fail closed. A rule fallback occurs only
when `AI_ALLOW_RULE_FALLBACK=true`, and it remains visibly labelled as untrained.

Every diagnosis persists `engine`, `trained_model`, `model_version`,
`model_label`, and alternatives so results remain auditable after a model or
provider changes.

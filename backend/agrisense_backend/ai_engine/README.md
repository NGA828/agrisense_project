# AgriSense plant-pathology inference

## Current setup

Use the maintained [AI setup guide](../../../docs/AI_SETUP.md) for installation,
free-provider limits, privacy, crop screening, timeouts and local Ollama. It
supersedes the old hard-coded free-model/failover instructions.

- `AI_ENGINE=openrouter`: `openrouter/free` routes among available free vision
  models compatible with structured output. A zero prompt/completion price cap
  and a free-only model-ID guard prevent silently selecting a paid endpoint.
- `AI_ENGINE=ollama`: private vision model such as `gemma3:4b`, with the same
  identity/disease contract and no hosted API daily quota. Hardware is required.
- `AI_ENGINE=tensorflow`: optional local Keras CNN with an exact class manifest.
  A closed-set classifier is **not** a reliable general-purpose non-crop detector.
- `AI_ENGINE=rules`: colour/lesion demo only. `AI_REQUIRE_TRAINED_MODEL=true`
  blocks it, including internal fallback results. Never use it to hide provider errors.

## Shared vision contract

One image request returns `image_type`, `detected_crop`, finite numeric
`crop_confidence`, the disease/healthy/inconclusive outcome and image evidence.
The backend validates identity **before** accepting even a healthy result.
Non-crop, mismatched or uncertain identity returns a 422 rejection with no
persisted diagnosis/image/treatment. Disease uncertainty may instead return
an inconclusive screening, with no chemical recommendation.

Only reviewed `Disease` rows for the selected crop are eligible; unknown labels
and generated treatment fields fail closed. Causes, medication and instructions
are copied from reviewed data. Model confidence is self-reported, not a clinical
accuracy guarantee. Evaluate on real local field images and consult an agronomist.

Images are rotated/resized, converted to JPEG and stripped of EXIF before being
sent to the configured vision service. Cloud processing must be disclosed to
users. A private model avoids the cloud provider, but the app still sends the
photo to the AgriSense backend.

`ai_engine/cache.py` binds reuse to the user, image, selected crop, engine/config,
and reviewed knowledge-base contents. Use shared Redis across workers. No
failures are cached and no automatic repeated requests spend the free budget.

```bash
python manage.py check_ai_model --check-auth  # no inference/charge
python manage.py check_ai_model --list-free   # current advertised free candidates
python manage.py check_ai_model --json        # machine-readable capability report
```

A readiness/catalog check cannot guarantee latency, recognition accuracy, daily
free capacity or future provider uptime. For 50+ daily scans without purchasing
API credits, size and test a private Ollama deployment; see the setup guide.

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
unknown diseases and provider errors fail closed. OpenRouter/Ollama never fall
back to rules. A legacy TensorFlow demo fallback requires explicit permission
and is rejected at the API boundary when a trained model is required.

Every diagnosis persists `engine`, `trained_model`, `model_version`,
`model_label`, `detected_crop`, `crop_confidence`, and alternatives so results remain auditable after a model or
provider changes.

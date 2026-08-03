# AgriSense plant-pathology inference

## What is and is not AI here

The upload flow and REST endpoint do not, by themselves, make a disease model.
AgriSense has two deliberately distinct engines:

- `AI_ENGINE=tensorflow` — **trained CNN inference**. The backend loads a Keras
  model, preprocesses the uploaded pixels, runs `model.predict`, maps the output
  through the model's class manifest, applies a confidence threshold, and joins
  the prediction to the reviewed `Disease` knowledge base.
- `AI_ENGINE=rules` — a deterministic colour/lesion heuristic for demos and
  backend development. It is not a trained pathology model. API responses and
  the Flutter result screen label it as such, and `/api/health/` reports it as
  `degraded`.

The old TensorFlow adapter raised `NotImplementedError`; it now implements the
complete inference path. A trained artifact is intentionally not committed to
Git because model weights are large, versioned deployment artifacts and must be
validated separately from application source.

## Model contract

A model must:

1. accept one RGB image batch (default shape `[1, 224, 224, 3]`);
2. return one vector of class logits or probabilities (`[1, class_count]`);
3. be saved as a Keras `.keras` or compatible `.h5` artifact; and
4. ship with the **exact output-index manifest used during training**.

Preferred manifest:

```json
{
  "classes": [
    {
      "index": 0,
      "label": "Tomato___Early_blight",
      "crop_type": "Tomato",
      "disease_name": "Tomato Early Blight"
    },
    {
      "index": 1,
      "label": "Tomato___healthy",
      "crop_type": "Tomato",
      "is_healthy": true
    }
  ]
}
```

The parser also accepts:

- a list of labels;
- Keras `class_indices.json` (`label -> index`); or
- Hugging Face `config.json` containing `id2label`.

Explicit crop and disease fields are safest. Never construct the model output
order from database rows. `model_manifests/plantvillage_38.json` is provided for
models that use the standard 38-class PlantVillage ordering; verify it against
your training export before use. That dataset does not cover all AgriSense
crops (notably Cassava and Cocoa), so it is an integration example rather than
a complete production model for this app.

## Local setup

Use Python 3.11 (the repository Docker image already does):

```bash
cd backend/agrisense_backend
pip install -r requirements.txt -r requirements-ai.txt
mkdir -p ai_models
# Copy/version your validated artifacts outside Git:
# ai_models/plant_disease_v3.keras
# ai_models/plant_disease_v3.classes.json
```

Configure `.env`:

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

Normalization must match training:

| Value | Runtime transform |
|---|---|
| `zero_one` | `pixel / 255` |
| `minus_one_one` | `pixel / 127.5 - 1` |
| `imagenet` | PyTorch/ImageNet channel mean and standard deviation |
| `none` | raw `0..255` float values |

Then verify readiness:

```bash
python manage.py check
python manage.py runserver
curl http://localhost:8000/api/health/
```

A ready model reports roughly:

```json
{
  "checks": {
    "ai_engine": {
      "status": "ok",
      "engine": "tensorflow-cnn",
      "trained_model": true,
      "model_version": "plant-disease-v3.2.0"
    }
  }
}
```

If a configured model or manifest is missing, diagnosis returns HTTP `503`
instead of silently impersonating trained AI. Set `AI_ALLOW_RULE_FALLBACK=true`
only when an explicitly labelled demo fallback is acceptable.

## Knowledge-base mapping

The model decides the visual class. The admin-reviewed `Disease` table supplies
symptoms, causes, prevention and treatment. `disease_name` in the manifest
should exactly match a `Disease.disease_name` value (case-insensitive).

If a model class has no reviewed disease record, AgriSense preserves the model
label but marks the result inconclusive and recommends agronomist review; it
does **not** invent pesticide instructions.

## Validation before agricultural use

PlantVillage-style datasets are mostly detached leaves photographed against
controlled backgrounds. High validation accuracy on that dataset does not imply
similar accuracy in farms, with clutter, multiple leaves, shadows and regional
cultivars. Before enabling treatment recommendations:

- evaluate on held-out field photos from every supported region/crop;
- keep plant/leaf groups out of both training and validation splits;
- include healthy and out-of-distribution examples;
- calibrate confidence on a separate calibration set;
- review every class-to-treatment mapping with a local agronomist; and
- retain the model version and class manifest with each release.

Every diagnosis now persists `engine`, `trained_model`, `model_version`,
`model_label`, and top alternatives so results remain auditable after the active model changes.

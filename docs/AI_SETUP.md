# Reliable crop analysis: free-model setup

## What changed

- You must select a crop. The app no longer silently selects Tomato or offers crops with no reviewed disease data.
- One vision request checks **whether the photo contains a crop**, identifies the actual crop, and screens for a disease. The backend independently checks those fields before accepting any disease or `Healthy` result.
- Non-crop photos, crop mismatches and uncertain crop identities return a helpful message. **No diagnosis, treatment plan or image is saved for these rejections.**
- The model may choose only a disease reviewed for the selected crop. Medication, dosage and treatment instructions are never taken from generated model text.
- Photos are resized to 1,024 pixels before upload where supported, then resized/rotated and stripped of EXIF on the server. Hidden reasoning is disabled and the output budget is bounded.
- Recent identical scans are reused for the **same user + image + crop + model/configuration + reviewed data** for 10 minutes. Edits to reviewed data invalidate the cache. A concurrent duplicate does not make another model call.
- Expired login tokens are refreshed for scan uploads. Network, quota and model-response failures are not disguised as a diagnosis or blamed on the photo.

**No AI model is error-free.** Crop recognition and self-reported confidence can be wrong. This is visual screening, not a laboratory diagnosis or a substitute for an agronomist. Test on representative crop/non-crop photos from your farms before relying on it.

## Choose the free option that matches your daily requirement

| Option | Model cost | Daily capacity | Trade-off |
|---|---|---|---|
| **Groq free tier** (recommended) | Zero — free API key, no credit card | ~30 requests/min and a per-model daily quota per key (commonly 1,000–14,400 requests/day; far above 50 scans/day) | Shared free quotas can throttle at peak times; a fallback model is configured automatically |
| OpenRouter free router | Zero-priced endpoints only by default | Shared provider/account quota (often ~50/day on the basic free tier) | Simple setup; free availability and latency vary |
| Private Ollama vision model | No hosted API per-scan fee | No provider daily request cap; the app has no daily cap | You provide suitable hardware, electricity/hosting and model maintenance |

The basic OpenRouter free tier is commonly limited to **50 requests/day across the account**, not 50 successful scans for every farmer. Other users, unsuccessful calls and upstream availability can reduce the number of useful results. Switching free models/keys is not a way to create extra account quota. Check the current [provider limits](https://openrouter.ai/docs/api_reference/limits) before deployment.

The **Groq free tier** is tracked per API key and per model, resets daily, and needs no credit card; check your live quotas at [console.groq.com/settings/limits](https://console.groq.com/settings/limits). Groq serves inference on dedicated LPU hardware, so scans usually return in a few seconds. If **at least 50 fresh analyses/day without buying API credits** is a firm requirement, Groq is the simplest way to satisfy it; the private Ollama option removes provider quotas entirely if you have the hardware. There is intentionally no automatic paid fallback or automatic retry loop that spends more requests.

## Option A — Groq free tier, recommended

1. Create a free API key (no credit card) at <https://console.groq.com/keys>.
2. Keep the key only in `backend/agrisense_backend/.env` (or your hosting secret manager). Do not put it in Flutter, Git, screenshots, or chat.
3. Set:

```dotenv
AI_ENGINE=groq
GROQ_API_KEY=replace-privately
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
GROQ_FALLBACK_MODELS=meta-llama/llama-4-maverick-17b-128e-instruct
GROQ_TIMEOUT_SECONDS=25
GROQ_MAX_TOKENS=1024
GROQ_IMAGE_MAX_DIMENSION=1024
GROQ_IMAGE_QUALITY=82
AI_CROP_CONFIDENCE_THRESHOLD=80
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
AI_ANALYSIS_CACHE_SECONDS=600
THROTTLE_AI_RATE=20/min
```

4. Restart Django, then verify the key and models **without submitting a scan**:

```bash
cd backend/agrisense_backend
python manage.py check_ai_model --check-auth
python manage.py check_ai_model --list-free
```

Notes:

- Groq's API is OpenAI-compatible, so the engine reuses the same guarded pipeline: the model may only name diseases reviewed for the selected crop, the crop in the photo must match the farmer's selection, and non-crop photos are refused with `not_a_crop`/`crop_mismatch` (nothing is saved).
- Because Groq has no server-side model router, the configured fallback models are tried **client-side, once each**, only on transport/model-level errors (429/5xx/model unavailable). A rejected key never retries.
- Free-tier rate limits are per key and per model: at ~30 requests/minute you can serve bursts of farmers, and the per-model daily quota (model dependent) is far above 50 scans/day. The app-level throttle is `THROTTLE_AI_RATE` (20/min per user by default) and identical re-scans within `AI_ANALYSIS_CACHE_SECONDS` reuse the previous result instead of spending quota.
- When the quota is exhausted the app answers `429` with `Retry-After`; it never fabricates a diagnosis instead.

## Option B — OpenRouter, easiest to start

Keep the key only in `backend/agrisense_backend/.env` (or your hosting secret manager). Do not put it in Flutter, Git, screenshots, or chat.

```dotenv
AI_ENGINE=openrouter
OPENROUTER_API_KEY=replace-privately
OPENROUTER_MODEL=openrouter/free
# Pinned free vision models tried (server-side, one HTTP request) if the
# auto-router is throttled or has no live endpoint. Free slugs are retired
# regularly — refresh with `python manage.py check_ai_model --list-free`.
OPENROUTER_FALLBACK_MODELS=google/gemma-4-26b-a4b-it:free,google/gemma-4-31b-it:free,nvidia/nemotron-nano-12b-v2-vl:free
OPENROUTER_ALLOW_PAID_MODELS=false
OPENROUTER_TIMEOUT_SECONDS=25
OPENROUTER_MAX_TOKENS=1024
OPENROUTER_IMAGE_MAX_DIMENSION=1024
OPENROUTER_IMAGE_QUALITY=82
AI_CROP_CONFIDENCE_THRESHOLD=80
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
AI_ANALYSIS_CACHE_SECONDS=600
THROTTLE_AI_RATE=20/min
```

Get a key from <https://openrouter.ai/keys>. The [free router](https://openrouter.ai/docs/guides/routing/routers/free-router) selects currently available free models compatible with image input and structured output, instead of depending on a list of retired model IDs. Its choice can vary. The actual responding model is recorded on each diagnosis.

The spend guard accepts only `openrouter/free` or `:free` model IDs and pins provider prompt/completion prices to zero. A duplicate primary/fallback is removed. To pin a particular free vision model, inspect the live catalog first:

```bash
cd backend/agrisense_backend
python manage.py check_ai_model --list-free
python manage.py check_ai_model --check-auth
```

The second command checks credentials and catalog capability **without submitting a scan**. It cannot guarantee remaining free requests or a successful future diagnosis. Restart Django after changing the environment.

## Option C — Private Ollama, no daily provider quota

1. Install [Ollama](https://ollama.com/) on the inference machine.
2. Download a **vision-capable** local model, for example `ollama pull gemma3:4b`.
3. Keep Ollama running and private. Warm the model before accepting traffic; the adapter keeps it loaded for 30 minutes after use. Benchmark latency and accuracy on your actual hardware. A CPU-only machine can be much slower than a suitable GPU.
4. Set:

```dotenv
AI_ENGINE=ollama
OLLAMA_BASE_URL=http://127.0.0.1:11434
OLLAMA_MODEL=gemma3:4b
OLLAMA_TIMEOUT_SECONDS=25
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
```

That loopback URL is **server-to-server**, when Django and Ollama run on the same machine; the phone/browser never calls it. Use a private service hostname if they run separately. Do not expose Ollama's unauthenticated port publicly. Cloud-tagged models are rejected by this adapter.

The repository also includes an optional Compose profile. In the environment file used by Compose, set `AI_ENGINE=ollama` and `OLLAMA_BASE_URL=http://ollama:11434`, then, from the repository root:

```bash
docker compose --env-file backend/agrisense_backend/.env --profile local-ai up -d --build
docker compose --env-file backend/agrisense_backend/.env --profile local-ai exec ollama ollama pull gemma3:4b
docker compose --env-file backend/agrisense_backend/.env exec backend python manage.py check_ai_model
```

Weights stay in the `ollama_models` Docker volume, not Git. No weights are downloaded by Django or included in this patch. A downloaded model and adequate runtime resources are still required. Pin and validate an Ollama image/model version for production.

## Required for ALL options: reviewed crop data

```bash
python manage.py migrate
```

Add/review `Disease` records in Django admin or the app's content-management screen for every crop you intend to offer. On an **isolated development database only**, `python manage.py seed_data` supplies demo crop data **and demo accounts with known passwords**. Never run that command on a public production database as a shortcut.

An empty knowledge base intentionally exposes no crops. Do not turn on the colour-rule demo to conceal missing data or provider failures. The optional legacy TensorFlow closed-set classifier is not an open-world non-crop detector; prefer the guarded Groq/OpenRouter/Ollama paths for this requirement.

## Production and troubleshooting

- Existing diagnoses are not re-classified by the migration. Resubmit a photo if an old result seemed wrong.
- Deploy the updated backend **and rebuild/install the Flutter app**. Cached scans now return HTTP 200; new scans return 201, and image rejections have dedicated error codes.
- Use `CACHE_BACKEND=redis` with a shared `REDIS_CACHE_URL` for multiple workers. Redis uses an ownership-checked atomic lease; local-memory caching coordinates only within one process.
- A cache/throttle outage stops new inference with a private, retryable 503 rather than bypassing the free-request guard. Cache write/cleanup failures cannot hide an already-saved diagnosis or change a crop rejection into a server error. Redis connection/read waits are bounded to two seconds each.
- `ai_cache_unavailable`: the shared cache needs attention. Wait briefly and retry; the request does not fall back to a guessed diagnosis.
- The default provider read timeout is 25 seconds (connection timeout up to 5 seconds); the app waits up to 45 seconds per upload attempt. These are waiting limits, **not a measured completion-time guarantee**. Model cold starts, provider queues and slow uploads still matter.
- `GET /api/health/` reports configuration under `checks.ai_engine`; it does not make an expensive live inference call.
- `not_a_crop` / `crop_mismatch`: choose an actual photo of the selected crop, or change the crop selection. The app will never silently substitute another crop.
- `crop_uncertain`: retake a clearer photo with useful plant features visible.
- `ai_rate_limited`: obey `Retry-After` when returned. The quota is shared; do not repeatedly tap retry.
- `ai_timeout` / `ai_invalid_response`: a provider issue, not proof your plant is diseased. No result is saved; retry later.
- **`OpenRouter returned fields outside the restricted diagnosis schema`** in older builds happened when a free model added extra JSON keys (e.g. `reasoning`). The current build tolerates extra keys (they are ignored and audited in the logs — only the seven contracted fields are read, and treatments still come exclusively from reviewed database rows), while missing or mistyped fields still fail closed. A model that wraps the result one level deep (e.g. `{"diagnosis": {...}}`) is also accepted. Update the backend if you still see this error.
- `ai_knowledge_base_empty` / `unsupported_crop`: review/add the relevant disease records, then reload the crop selector.

Never lower the crop-identity threshold simply to make more uploads pass. Better to refuse an uncertain photo than prescribe a treatment for the wrong crop.

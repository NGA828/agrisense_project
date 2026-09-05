# Getting the AI Plant Doctor running

Everything in the code is already configured. There are exactly **two** things
left to do, and both are one-liners.

---

## 1. Get a free OpenRouter API key

1. Go to <https://openrouter.ai> and sign up (email or GitHub).
   **No credit card is required**, and none should be added.
2. Open <https://openrouter.ai/keys> and click **Create Key**.
3. Copy the key (it starts with `sk-or-v1-...`). You only see it once.

## 2. Put the key in the backend environment

Create `backend/agrisense_backend/.env` (the file is git-ignored — the key must
never be committed or placed in the Flutter app):

```bash
cd backend/agrisense_backend
cp .env.example .env
```

Then edit `.env` and set just this one line:

```dotenv
OPENROUTER_API_KEY=sk-or-v1-your-key-here
```

Everything else already has a working default: the model, the free-only spend
guard, the fallback model, the confidence thresholds.

## 3. Seed the disease knowledge base

**This step is not optional.** The AI is deliberately restricted to diseases
that exist in your database — it is never allowed to invent one. With an empty
`Disease` table every scan fails with:

```
No reviewed diseases exist in the database for 'Tomato'.
```

So run:

```bash
python manage.py migrate
python manage.py seed_data      # seeds 9 diseases across 5 crops
```

---

## Verify before you scan

```bash
python manage.py check_ai_model
```

Expected:

```
primary : OK    google/gemma-4-26b-a4b-it:free
                free, vision + structured outputs, served by Google AI Studio
fallback1: OK   meta-llama/llama-4-scout:free
fallback2: OK   mistralai/mistral-small-3.1-24b-instruct:free
fallback3: OK   dots-studio/dots-3-note-preview:free  (retired 2026-09-30)
Configuration is usable.
```

Then check the app's own health endpoint:

```bash
curl http://localhost:8000/api/health/
```

The `ai` section should read `"status": "ok"`. If it says
`"OPENROUTER_API_KEY is not configured."`, the `.env` file was not picked up —
confirm it sits next to `manage.py` and that `python-dotenv` is installed.

---

## "It was working, now every scan fails" — check this first

Free OpenRouter models are **retired on a rolling schedule** (for example,
`dots-studio/dots-3-note-preview:free` is scheduled for removal on
**2026-09-30**, and providers drop free endpoints without notice). When the
primary *and* every fallback are dead or throttled, every diagnosis fails with
the same generic "could not analyze this photo" error — which looks like the AI
"can't recognize anything", including perfectly clear crop photos.

Two commands tell you which case you are in:

```bash
python manage.py check_ai_model            # are the configured models alive?
python manage.py check_ai_model --list-free # what can I switch to right now?
```

Then update `OPENROUTER_MODEL` / `OPENROUTER_FALLBACK_MODELS` in `.env` to a
model that reports **OK on all three requirements** (vision, structured
outputs, live provider) and restart the backend.

Also confirm the failure is not quota: the free tier allows **50 requests per
day, account-wide** (failed requests count too). A day of UI testing can
exhaust it, and then every scan fails until the daily reset — or until the
one-time $10 top-up raises it to 1,000/day.

---

## What each failure message means

| Message | Cause | Fix |
|---|---|---|
| `OPENROUTER_API_KEY is not configured.` | Step 2 missing/not loaded | Check `.env` is in `backend/agrisense_backend/` |
| `No reviewed diseases exist in the database for 'X'.` | Step 3 missing, or crop has no rows | `python manage.py seed_data` |
| `OPENROUTER_FREE_ONLY is enabled but these models are not free: ...` | A paid model was configured | Use a `:free` id, or set `OPENROUTER_ALLOW_PAID_MODELS=true` |
| `OpenRouter returned HTTP 429. Rate limited...` | Daily/minute cap hit | Wait; see budget notes below |
| `OpenRouter returned HTTP 402. ...out of free-tier credit/quota` | Free daily quota exhausted | Wait for reset or one-time $10 top-up |
| `OpenRouter returned HTTP 401. The API key was rejected` | Key revoked/typo | Create a new key at openrouter.ai/settings/keys |
| `OpenRouter returned HTTP 404. ...no longer has a live provider` | Model retired | `python manage.py check_ai_model --list-free` |
| `empty diagnosis content` | Model spent its output budget on reasoning | Raise `OPENROUTER_MAX_TOKENS` (default 2000) or switch to a non-reasoning model |

---

## Staying inside the free tier

One photo scan = one OpenRouter request. No retries are performed.

| Account | Scans/day | Scans/min |
|---|---|---|
| Free (no card) | **50** | 20 |
| After a one-time $10 credit purchase | 1,000 | 20 |

The daily cap is **account-wide across all `:free` models**, so the fallback
model buys reliability, not extra quota. Failed requests still count.

**While building UI, don't burn quota on the real model:**

```dotenv
AI_ENGINE=rules
AI_REQUIRE_TRAINED_MODEL=false
```

This uses the local heuristic engine — zero requests, no key needed. Switch back
to `AI_ENGINE=openrouter` when you want to test real diagnosis quality.

To make your app's throttle match OpenRouter's ceiling (so users see a clean
error instead of a raw 429):

```dotenv
THROTTLE_AI_RATE=20/min
```

---

## Notes

- The key lives **only** in the backend. The Flutter app talks to your Django
  server, never to OpenRouter, so the key is never shipped in the APK.
- Scans are also constrained by the crop list: `seed_data` covers Tomato, Maize,
  Cassava, Pepper and Cocoa. To support more crops, add `Disease` rows via the
  admin — the AI picks them up immediately, with no code change.
- `dots-3-note-preview` is a *preview* model and free slugs do get retired. If
  diagnoses start failing, run `check_ai_model` first.

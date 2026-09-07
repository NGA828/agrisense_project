# AgriSense AI — Intelligent Agricultural Assistant

> A plant doctor, a weather forecaster and a farm-supply marketplace in one mobile app — connecting **Farmers**, **Agro-input Dealers** and **Administrators** on a single platform.

## Overview

AgriSense helps farmers screen crop photos and access reviewed treatment guidance,
weather and farm supplies. Crop identity is checked against the farmer's explicit
selection before accepting a diagnosis; uncertain or non-crop images are refused.
AI can still be wrong, so treatment decisions need agronomist confirmation.
Marketplace checkout supports configured **MTN Collection**; Orange Money/cards
are not integrated, and simulated payments are explicitly test-only.

**Setup:** [Free AI and the 50-scans/day requirement](docs/AI_SETUP.md) ·
[Real payments vs test mode](docs/PAYMENTS_SETUP.md).

## Architecture

| Layer | Technology | Role |
|---|---|---|
| **Frontend** | Flutter (+ Provider, web_socket_channel) | Simple, intuitive green-themed mobile UI |
| **Backend** | Django 4.2 + Django REST Framework + Channels | Central orchestrator of all business logic |
| **Auth** | SimpleJWT (access + rotating refresh, blacklist) | Persistent secure sessions |
| **Database** | MySQL 8 (utf8mb4) — SQLite supported for local dev | Users, products, orders, payments, chats, diagnoses |
| **Cache / Queue** | Redis (django-redis cache + Celery broker); locmem/eager in dev | Caching, async workers, background scheduling |
| **Async** | Celery + django-celery-beat schedules (reservations, premiums, reconciliation, weather cleanup) | Background jobs that never block requests |
| **AI Engine** | Free Groq vision tier (recommended) / free OpenRouter router / private Ollama vision; reviewed crop-specific diseases; optional legacy CNN/demo engines | Image-based crop screening with auditable model provenance |
| **Real-time** | Django Channels WebSocket (JWT-secured) | Instant chat + push-bus (live notifications & stock) |
| **External** | OpenWeatherMap, verified MTN Collection, explicit test simulator | Weather forecasts & mobile-money payments |
| **Observability** | JSON structured logging, request-id tracing, `/api/health/`, optional Sentry | Trace + monitor production |

## Features

### Farmer
- **Persistent session** — auto-login on app start, JWT auto-refresh
- **Dashboard** — time-aware greeting, live weather mini-card, AI tips, announcements
- **AI Plant Doctor** — camera/gallery scan → disease/healthy/inconclusive + model confidence (not clinically calibrated) + severity + full treatment plan + recommended products (crop-mandatory)
- **Marketplace** — searchable catalog with categories, images, prices, verified/premium badges, ratings/reviews; premium dealers rank first
- **Real-time chat** — WebSocket messaging with dealers (images, typing indicators, auto-reconnect with backfill)
- **Live marketplace** — stock availability updates instantly as orders are placed
- **Payments** — verified MTN checkout, pending-payment recovery, amount validation and paid-only dealer visibility; simulator/sandbox are labelled TEST
- **History** — diagnosis history and order history modules
- **Offline-first** — diagnosis history, marketplace catalog and weather are cached for low-coverage areas, with an offline action outbox
- **Works on first launch, offline** — a pre-populated SQLite knowledge base (crops, diseases, treatments, irrigation thresholds) ships inside the APK and installs itself into internal storage on first run; see [docs/BUNDLED_DATABASE.md](docs/BUNDLED_DATABASE.md)
- **Irrigation dashboard** — register soil-moisture sensors and get live, crop-aware irrigation advice (moisture + rain + thresholds); reachable from the Home quick-access grid
- **In-app notifications** — order/payment/premium updates with unread badge, delivered live over the push bus

### Agro-input Dealer
- **Inventory CRUD** — add/edit/delete products, images, prices, stock; availability toggle
- **Order management** — paid-only order list/notifications, ship/deliver workflow and safe stock handling; live refunds require provider operations
- **Live inventory** — stock changes push to the dashboard in real time as orders are placed/cancelled
- **Customer chat** — real-time conversations with farmers (typing indicators)
- **Premium tier** — subscription via mobile money (or admin grant); products get search visibility boost until expiry
- **Dashboard** — real product/order/revenue counters
- **Sales analytics** — revenue/order time-series, top products, stock health

### Administrator
- **Analytics dashboard** — real stats + time-series charts (user growth, diagnoses, order volume, revenue), top products/dealers, and regional/geo disease aggregation
- **User management** — search, suspend/activate, delete fraudulent accounts
- **Dealer verification** — pending-application queue with approve/reject
- **Content & knowledge base** — add/edit/delete diseases; changes immediately affect AI diagnoses
- **Broadcast center** — targeted announcements (all / farmers / dealers) with active toggle
- **Audit log** — immutable record of every privileged admin action
- **Product moderation** — report queue with dismiss/remove resolution
- **System health** — live API/DB/AI-engine checks
- **IoT & USSD** — field-sensor ingestion (soil moisture/temp/humidity/rainfall), **precision
  irrigation advice** (moisture + weather + crop thresholds) and a USSD/SMS companion so
  feature-phone farmers can check weather & diagnosis
- **Predictive outbreak alerts** — detects *growing* disease clusters from geo-tagged diagnoses
  and proactively pushes warnings to nearby farmers

## Quick Start

### 0. Requirements

- **Python 3.10+**
- **MySQL 8.0+ or MariaDB 10.6+** (recommended; the schema uses `utf8mb4`,
  `CHECK` constraints and descending indexes). SQLite works too for quick
  local smoke tests — see the note at the end of this section.
- **Current stable Flutter** for the app (the checked-in lockfile requires Dart 3.11+)

### Backend (Django + MySQL)

```bash
cd backend/agrisense_backend
python -m venv venv
source venv/bin/activate           # Windows: venv\Scripts\activate
pip install -r requirements.txt
```

The project uses **PyMySQL** (pure Python — no C compiler needed on Windows)
and already ships the `cryptography` package required for MySQL 8's
`caching_sha2_password` authentication.

#### Option A — One command (recommended)

Start your MySQL server, then:

```bash
python manage.py create_mysql_database
# prompts for the MySQL root password; creates:
#   database  agrisense_db      (utf8mb4)
#   user      agrisense_user    (password: password123, full access)
```

It is idempotent — safe to re-run. Then:

```bash
python manage.py migrate
python manage.py seed_data            # ISOLATED DEV ONLY: creates known demo passwords
python manage.py createsuperuser
python manage.py runserver            # REST API on :8000
```

#### Option B — Manual MySQL setup

Linux / macOS:

```bash
mysql -u root -p -e "CREATE DATABASE agrisense_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p -e "CREATE USER 'agrisense_user'@'localhost' IDENTIFIED BY 'password123';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON agrisense_db.* TO 'agrisense_user'@'localhost';"
mysql -u root -p -e "CREATE USER 'agrisense_user'@'%' IDENTIFIED BY 'password123';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON agrisense_db.* TO 'agrisense_user'@'%';"
```

Windows (cmd / PowerShell):

```bat
mysql -u root -p -e "CREATE DATABASE agrisense_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
mysql -u root -p -e "CREATE USER 'agrisense_user'@'localhost' IDENTIFIED BY 'password123';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON agrisense_db.* TO 'agrisense_user'@'localhost';"
```

#### Connecting with different credentials

All database settings come from environment variables (or `backend/agrisense_backend/.env` — copy `.env.example`):

```bash
DB_NAME=agrisense_db DB_USER=root DB_PASSWORD=yourpass DB_HOST=localhost DB_PORT=3306 python manage.py runserver
```

#### MySQL notes you may care about

- The `Order` model maps to a table named `` `order` `` — `order` is a MySQL
  reserved word, but Django always quotes identifiers with backticks, so the
  app is unaffected. Just remember to backtick it if you write raw SQL.
- MySQL 8's default `caching_sha2_password` auth works out of the box thanks
  to the `cryptography` dependency (PyMySQL performs the RSA key exchange).
- `FILE_UPLOAD_MAX_MEMORY_SIZE`/`DATA_UPLOAD_MAX_MEMORY_SIZE` are set to 10 MB
  in `settings.py`, so large plant photos upload fine through the API.
- Not using MySQL right now? For zero-setup smoke tests you can run
  `export DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3` (or the
  equivalent `set` on Windows) before `migrate` — no other changes needed.

### Free AI setup

Follow [docs/AI_SETUP.md](docs/AI_SETUP.md). Recommended free configuration
(Groq — free key from <https://console.groq.com/keys>, no credit card):

```dotenv
AI_ENGINE=groq
GROQ_API_KEY=replace-privately-in-the-backend
GROQ_MODEL=meta-llama/llama-4-scout-17b-16e-instruct
GROQ_FALLBACK_MODELS=meta-llama/llama-4-maverick-17b-128e-instruct
AI_REQUIRE_TRAINED_MODEL=true
AI_ALLOW_RULE_FALLBACK=false
```

Alternatives: `AI_ENGINE=openrouter` (free router) or `AI_ENGINE=ollama`
(self-hosted). Add **reviewed Disease records** for each supported crop, and run
`python manage.py check_ai_model --check-auth` to check credentials/capabilities
without using an inference request. Missing provider configuration or reviewed
data deliberately does not produce a guessed diagnosis.

Every engine applies the same guards: the photo must actually show a crop
(`not_a_crop` rejections), the crop in the photo must match the farmer's
selection (`crop_mismatch` rejections), and only diseases reviewed for that
crop can be returned — treatment text always comes from the local reviewed
database, never from the model.

The app has no daily scan cap (20/minute default burst throttle). Groq's free
tier allows ~30 requests/minute and a per-model daily quota per key (commonly
1,000–14,400 requests/day) — comfortably above **50 scans/day**, with LPU-speed
responses (typically a few seconds per scan). Caching and smaller images reduce
repeated calls and upload size; they cannot guarantee provider uptime, response
speed or accuracy.

### Payment setup

Payments are **off until configured** (or simulated). Follow
[docs/PAYMENTS_SETUP.md](docs/PAYMENTS_SETUP.md) for MTN sandbox/live credentials,
Cameroon target/currency, callbacks, reconciliation and historical-order audits.
`python manage.py check_payments --check-auth` validates authentication without
charging anyone. Keep all provider credentials private in the backend.

In development (`DEBUG=True`) the local simulator is on by default and
**deterministic: simulated payments always succeed**, so checkout demos never
randomly fail. To test the failure flow, pay from a number ending in `0000`
(e.g. `+237 670 00 00 00`). A failed or unpaid checkout is never sent to the
dealer. On a `DEBUG=False` demo server, set `PAYMENT_SIMULATOR_ENABLED=true`
and `PAYMENT_SIMULATOR_ALLOW_NON_DEBUG=true` (explicit, warned-about opt-in).
It transfers no funds. Orange/card collection, automatic live refunds and
dealer wallet payouts are not implemented.

### Frontend (Flutter)

```bash
cd frontend/agrisense_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api   # Android emulator
# Real device: use your reachable backend host, not localhost.
```

Android emulator defaults to `10.0.2.2`; iOS simulator/desktop defaults to localhost.
Web defaults to its **own origin**: reverse-proxy `/api/`, `/media/`, `/ws/` to
Django, or set a public `API_BASE_URL` and configure CORS/WebSocket origins.
Use HTTPS for production and rebuild/install the app with the backend update.
New scans and purchases require a connection; cached reference/history is not
an offline payment or a new offline AI diagnosis.

### Demo accounts

| Role | Username | Password | Notes |
|---|---|---|---|
| Farmer | `farmer1` / `farmer2` | `password123` | |
| Dealer (premium) | `dealer1` | `password123` | products rank first |
| Dealer | `dealer2` | `password123` | |
| Dealer (pending) | `dealer3` | `password123` | shows in admin verification queue |
| Admin | `admin1` | `password123` | |

**Local simulator only:** explicitly enable it in DEBUG to test even-last-digit
success / odd-last-digit failure. This is not the MTN external sandbox and does
not move money. Never seed demo accounts or enable simulation on a public launch.

## API Endpoints

### Auth & Users
- `POST /api/auth/login/` · `POST /api/auth/register/` · `POST /api/auth/refresh/`
- `GET /api/users/me/` · `PATCH /api/users/me/`
- Admin: `GET /api/users/` · `GET /api/users/dealer_requests/` · `POST /api/users/{id}/suspend|activate|verify_dealer|upgrade_premium/` · `DELETE /api/users/{id}/`

### Diagnosis & AI
- `POST /api/diagnosis/analyze/` (multipart image + crop_type — crop is required; new 201 / cached 200 / image rejected 422) · `GET /api/diagnosis/history/`
- Returns `healthy` / `inconclusive` outcomes, conservative confidence thresholds/caps, and auditable `engine`, `trained_model`, `model_version`, `model_label`, and alternatives
- `GET /api/diseases/supported_crops/` · Admin: `GET /api/diseases/list_diseases/`, `POST /api/diseases/add_disease/`, full CRUD

### Regional Analytics
- `GET /api/admin/regional/?period=7d|30d|90d|1y` — disease counts by crop + geo-clustered outbreak points (admin)

### Marketplace & Orders
- `GET /api/products/marketplace/?category=&search=` (premium-boosted ranking)
- Dealer: `GET /api/products/my_products/`, POST/PUT/DELETE `/api/products/{id}/`, `POST /api/products/{id}/toggle_availability/`
- `POST /api/orders/` (buyer-scoped `checkout_key`, reserves stock but does not notify the dealer) · `GET /api/orders/` · `POST /api/orders/{id}/update_status/` (ship/deliver) · `POST /api/orders/{id}/cancel/` (farmer/dealer/admin)

### Payments
- `POST /api/payments/` (validates amount + ownership) · `POST /api/payments/{id}/process_payment/` · `GET /api/payments/{id}/verify/` · `POST /api/payments/{id}/refund/` (admin, test-only accounting) · `GET /api/payments/my_payments/`
- `GET /api/payments/methods/` (gateway readiness/test labels and premium pricing)
- `POST /api/payments/mtn/callback/` (native hint; authenticated provider status is checked)
- `POST /api/payments/webhook/` (HMAC-signed integration bridge, not native MTN)

### Ledger & Settlement
- Double-entry ledger records every collection (→ escrow), fulfilment (→ dealer + platform fee),
  and test refund (escrow reversal) with an immutable audit trail.
  **Ledger balances are accounting, not real wallet transfers or bank settlement.**

### Reviews, Reports & Trust
- `POST /api/reviews/` (farmers, verified purchases only) · `GET /api/reviews/?product=`
  · one review per farmer+product; product rating/avg surfaced in the catalog
- `POST /api/product_reports/` (report a product) · `POST /api/product_reports/{id}/resolve/` (admin)
  · moderation queue (pending → dismissed/removed)

### Audit Log
- `GET /api/audit_logs/` (admin; filterable by category) · `GET /api/audit_logs/summary/`
  · immutable write-through from suspend/verify/delete/premium/refund/moderation/content actions

### Dealer Analytics & OTP
- `GET /api/dealers/analytics/?period=7d|30d|90d|1y` — dealer-scoped revenue/orders/top products
- `POST /api/auth/otp/send/` · `POST /api/auth/otp/verify/` — phone OTP for registration/password reset

### IoT Sensors (Phase F)
- `POST /api/sensors/` (register a field sensor, optional `crop`) · `POST /api/sensors/{id}/ingest/` (single/batch readings)
- `GET /api/sensors/{id}/latest/` — latest reading + irrigation advice
- `GET /api/sensors/{id}/irrigation_advice/?crop=Tomato` — precision irrigation recommendation
  (moisture + trend + local rain probability + crop thresholds: `irrigate_now` / `delay_rain` / `monitor` / `adequate`)
- Celery beat `monitor-irrigation` (30 min) auto-pushes an alert when irrigation is due (throttled per sensor)

### Predictive Outbreak Alerting (Phase F)
- `GET /api/admin/outbreaks/` — admin outbreak console (list detected alerts)
- Celery beat `detect-outbreaks` (hourly) detects *growing* disease clusters from geo-tagged
  diagnoses and pushes targeted warnings to nearby farmers
- Run manually: `python manage.py detect_outbreaks`

### USSD / SMS Companion (Phase F)
- `POST /api/ussd/` — gateway callback with `{phoneNumber, text}`; serves weather/diagnosis menus
  to feature-phone farmers

### Load testing
- `load_tests/locustfile.py` (scenario-based) and `load_tests/k6_smoke.js` (CI smoke gate)

### Chat (REST + WebSocket)
- `GET/POST /api/chat/` · `GET /api/chat/{id}/messages/` · `POST /api/chat/{id}/send_message|mark_read/`
- `WS /ws/chat/{room_id}/?token=<JWT>` — authenticated + membership-checked, typing events

### Realtime Push Bus
- `WS /ws/push/?token=<JWT>` — one persistent per-user connection delivering
  `notification`, `stock_update` and broadcast events live
- `POST /api/push/register/` · `POST /api/push/unregister/` — FCM/APNs device tokens for true push

### Weather, Announcements, Notifications, System
- `POST /api/weather/`
- `GET/POST /api/announcements/` · `GET /api/announcements/active/` (audience-targeted);
  activating a broadcast fans out to the target users' notifications + push
- `GET /api/notifications/` · `GET /api/notifications/unread_count/` · `POST .../{id}/mark_read/`
- `GET /api/admin/stats/` · `GET /api/admin/analytics/?period=7d|30d|90d|1y`
- `GET /api/health/` — DB, cache/Redis, AI-engine, push and payments dependency liveness

### Background tasks (Celery)
- `release_stale_reservations_task` (every 5 min) · `expire_premiums_task` (daily)
- `reconcile_payments_task` (every 60 seconds) · `cleanup_weather_task` (daily)
- `fan_out_announcement_task` (on broadcast). Run `worker`/`beat` services in
  docker-compose, or `celery -A agrisense_backend worker/beat`. Without a broker
  (no `CELERY_BROKER_URL`) tasks run eagerly — no server needed for dev/tests.

## Security highlights

- Role-based access control everywhere; **admin cannot self-register**; privileged fields admin-only
- Dealer accounts require **admin verification** before listing products
- JWT rotation with **blacklist**; short access tokens + transparent client refresh
- **Authenticated & participant-checked WebSockets** — sender identity always comes from the token
- **Transactional, stock-safe orders** with `SELECT ... FOR UPDATE` and quantity validation
- **Reservation model** — definitive payment failure releases stock; retries recheck
  availability. Processing/uncertain payments cannot expire or be cancelled blindly.
  `python manage.py reconcile_payments` verifies payments and releases safe abandoned holds.
- Payment amount/ownership checks, unique provider references and idempotent processing.
  A reported payment success alone cannot publish an order; live status is verified.
- **Accounting is not a refund/payout adapter.** Live refunds are refused until a real
  provider transfer workflow is integrated; never show a ledger reversal as money sent.
- Native callbacks trigger authenticated provider verification, with polling as backup.
- Env-driven secrets, CORS/ALLOWED_HOSTS allow-lists, DRF throttling, image type validation
- **Custom production-security system checks** (`agrisense.W*`) fail the gate on
  insecure defaults; `manage.py check --deploy` surfaces them.
- **Structured JSON logging** with request-id tracing; optional Sentry error tracking.
- DB constraints: non-negative price/stock/quantity

## Tests

```bash
cd backend/agrisense_backend
python -m pip install -r requirements-dev.txt
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
# Backend coverage: auth/RBAC, JWT rotation, orders/stock + reservation lifecycle,
# payment failure/retry/refund, ledger settlement, HMAC webhook, realtime push
# bus (auth, fan-out, ping/pong), push-token registration, broadcast fan-out,
# Celery tasks (eager), weather auth/cache/cleanup, custom security checks,
# chat permissions, disease-DB authorization, AI determinism, analytics, health
```

CI is deferred in this update; no GitHub Actions workflow is included.
Run the manual checks below and the [deployment validation checklist](docs/DEPLOYMENT.md)
before release. The backend previously passed 331 SQLite tests with mocked
providers. Flutter analysis/tests/build and real AI/MTN validation remain unrun.

Frontend regression checks (requires a working Flutter SDK):

```bash
cd frontend/agrisense_app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
flutter build web --release
```

The 50-scan backend regression uses mocked inference; it proves application
allowance, not real provider capacity or recognition accuracy. See the setup
guides for staging/live acceptance checks.

See `docs/ARCHITECTURE_ANALYSIS.md` for the full architecture & gap analysis, `docs/DEPLOYMENT.md` for production deployment (Docker, daphne, Redis channel layer, payment/weather keys), `docs/ADMIN_DASHBOARD_REDESIGN.md` for the admin-console UI/UX overhaul plus the image-upload debugging guide & fixes, `docs/FARMER_DASHBOARD_REDESIGN.md` for the farmer experience redesign, and `docs/DEALER_DASHBOARD_REDESIGN.md` for the dealer-console redesign strategy (workflows, data visualization and usability).

## Project structure

```
agrisense_project/
├── backend/agrisense_backend/
│   ├── agrisense_backend/     # settings, urls, asgi, celery, logging, checks
│   ├── users/                 # custom user, registration, admin management
│   ├── diagnosis/             # diagnoses, treatment plans, disease knowledge base
│   ├── ai_engine/             # guarded Groq/OpenRouter/Ollama vision + legacy CNN/demo adapters
│   ├── products/              # catalog, orders, stock management
│   ├── payments/              # payment model + mobile-money gateway adapters
│   ├── chat/                  # chat rooms, messages, JWT WebSocket consumer
│   ├── weather/               # weather API + farming-advice engine
│   ├── announcements/         # broadcasts + per-user in-app notifications
│   ├── realtime/              # push-bus WS consumer, FCM/APNs push provider
│   ├── ledger/                # double-entry accounting, settlement, refunds
│   ├── auditlog/              # immutable admin action audit trail
│   ├── sensors/               # IoT field-sensor ingestion + irrigation advisory
│   ├── ussd/                  # USSD/SMS feature-phone companion
│   └── system/                # /api/health/ probes
├── frontend/agrisense_app/
│   └── lib/
│       ├── models/            # user, product, diagnosis, notification, analytics
│       ├── providers/         # auth, diagnosis, marketplace, weather, chat, ...
│       ├── screens/           # farmer/dealer/admin UIs
│       ├── services/api/      # ApiService (JWT refresh, media resolution, WS urls)
│       ├── services/local/    # offline cache + action outbox + bundled SQLite KB
│       ├── l10n/              # EN/FR localization
│       ├── theme/             # green premium theme
│       └── widgets/
│   └── assets/db/             # pre-populated SQLite shipped inside the APK
├── tools/                     # build_offline_db.py — generates the bundled DB asset
├── docs/                      # architecture analysis + deployment guide
├── Dockerfile
└── docker-compose.yml         # MySQL + Redis + backend (daphne)
```

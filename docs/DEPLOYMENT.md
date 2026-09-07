# AgriSense AI — Deployment & Operations Guide

## 1. Quick start (development)

### Backend

```bash
cd backend/agrisense_backend
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt

# Option A: MySQL (recommended for production-like behaviour)
mysql -u root -p -e "CREATE DATABASE agrisense_db CHARACTER SET utf8mb4;"
mysql -u root -p -e "CREATE USER 'agrisense_user'@'localhost' IDENTIFIED BY 'password123';"
mysql -u root -p -e "GRANT ALL PRIVILEGES ON agrisense_db.* TO 'agrisense_user'@'localhost';"

# Option B: SQLite (zero-setup smoke tests)
export DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3

python manage.py migrate
python manage.py seed_data          # ISOLATED DEV ONLY: creates known demo passwords
python manage.py createsuperuser    # optional extra admin
python manage.py runserver
```

### Frontend (Flutter)

```bash
cd frontend/agrisense_app
flutter pub get

# Android emulator: host machine is reachable at 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api

# iOS simulator / desktop
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api

# Physical device (same Wi-Fi):
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000/api
```

The default `API_BASE_URL` uses `10.0.2.2` on Android emulators, localhost on
iOS simulator/desktop, and the **browser origin on web**. Web needs a reverse
proxy for `/api/`, `/media/`, `/ws/`, or an explicit reachable HTTPS API URL
with CORS/WebSocket origins configured. A remote browser must not call localhost.

> **Splash screen note:** the splash is driven by `AuthProvider.restoreSession()`,
> which holds the splash for a minimum ~2.2 s so the logo animation always
> completes even on a fresh (no-session) launch. Ensure the `assets/app_icon/`
> directory is present (the only asset dir used by the app) — stale
> `assets/images/` / `assets/icons/` entries were removed from `pubspec.yaml`
> because they did not exist and would fail the build.

### Demo accounts (from `seed_data`)

| Role | Username | Password | Notes |
|---|---|---|---|
| Farmer | `farmer1` | `password123` | |
| Farmer | `farmer2` | `password123` | |
| Dealer (premium) | `dealer1` | `password123` | products rank first |
| Dealer | `dealer2` | `password123` | |
| Dealer (pending) | `dealer3` | `password123` | appears in admin verification queue |
| Admin | `admin1` | `password123` | |

## 2. Production stack (Docker)

```bash
cp backend/agrisense_backend/.env.example backend/agrisense_backend/.env
# Privately set production secrets, DEBUG=False, allowed hosts/origins and providers.
docker compose --env-file backend/agrisense_backend/.env up -d --build
# The backend entrypoint applies migrations. Create your own admin account:
docker compose --env-file backend/agrisense_backend/.env exec backend python manage.py createsuperuser
# Add reviewed Disease records via admin; do NOT seed demo accounts on a public server.
```

- API + WebSockets: `http://<host>:8000`
- Admin console: `http://<host>:8000/admin/`
- Health probe: `http://<host>:8000/api/health/`

### Security checklist for production

- [ ] Set a strong `DJANGO_SECRET_KEY` (never the dev default).
- [ ] `DEBUG=False` and strict `ALLOWED_HOSTS`.
- [ ] Put an nginx/Traefik reverse proxy in front with TLS; set
      `SECURE_SSL_REDIRECT=True`, restrict `CORS_ALLOWED_ORIGINS`.
- [ ] Restrict `/admin/` (VPN / IP allow-list).
- [ ] Run `python manage.py expire_premiums` daily (cron) so expired dealer
      subscriptions lose their search boost.
- [ ] Run `python manage.py reconcile_payments` every few minutes (cron /
      Celery beat) so abandoned unpaid orders free their reserved stock.
- [ ] Set a strong `PAYMENT_WEBHOOK_SECRET` and configure provider callbacks to
      `POST /api/payments/mtn/callback/` for native MTN hints; see [payment setup](PAYMENTS_SETUP.md).
      Live completion always requires an authenticated provider status query.
- [ ] Set `ORDER_RESERVATION_MINUTES` and, once monetising, `PLATFORM_COMMISSION_RATE`.
- [ ] For true push notifications, set `PUSH_PROVIDER=fcm` and `FCM_CREDENTIALS_PATH`
      to a Firebase service-account JSON; the app registers device tokens via
      `POST /api/push/register/`. With `PUSH_PROVIDER=noop` (default), notifications
      are delivered in-app over the `WS /ws/push/` bus only.
- [ ] Run the Celery **worker** and **beat** services (included in `docker-compose.yml`)
      so background tasks execute; set `CELERY_BROKER_URL`/`CELERY_RESULT_BACKEND` to
      Redis. (Without a broker, tasks run eagerly in-process — fine for dev.)
- [ ] Set `CACHE_BACKEND=redis` + `REDIS_CACHE_URL` (production); `CACHE_BACKEND=locmem`
      needs no server in dev/test.
- [ ] Set `PAYMENT_WEBHOOK_SECRET` to a long random value and configure provider callbacks.
- [ ] Optional: set `SENTRY_DSN` for error tracking; keep `JSON_LOGS=true` and a sane
      `LOG_LEVEL` for structured, request-id-tagged logging.
- [ ] Run backend tests on SQLite and MySQL, migration/asset checks, and Flutter analysis/tests/build. CI is deferred in this update.
- [ ] For phone OTP, set `SMS_PROVIDER` (noop logs the code / debug returns it;
      africastalking / twilio for real delivery) and enable
      `OTP_REQUIRED_FOR_REGISTRATION` / `OTP_REQUIRED_FOR_PASSWORD_RESET` when ready.
- [ ] Review the immutable **audit log** (`/api/audit_logs/`) for governance; product
      reports land in `/api/product_reports/` for moderation.
- [ ] The Flutter app ships **offline-first** (cached history/catalog/weather + an action
      outbox) and supports **EN/FR** via `flutter_localizations`. For backend API-message
      translations, compile `locale/fr/LC_MESSAGES/django.po` with `django-admin compilemessages`
      (requires GNU gettext).
- [ ] AI v2 tuning: adjust `AI_TEMPERATURE` / `AI_LOW_CONFIDENCE_THRESHOLD` to set how
      conservative the confidence reporting is.
- [ ] (Phase F, optional) Wire an IoT/MQTT bridge to `POST /api/sensors/{id}/ingest/` and a
      USSD/SMS gateway to `POST /api/ussd/`. Run `load_tests/` (Locust/k6) against staging
      before scaling out workers.
- [ ] Configure approved MTN Collection credentials and `MTN_MOMO_ENABLED`.
      Orange/card adapters are not implemented; never substitute test simulation.
- [ ] Add `OPENWEATHER_API_KEY` for live forecasts.
- [ ] Point the Flutter app at the production `API_BASE_URL` via
      `--dart-define` at build time (do not ship debug URLs).

## 3. WebSockets

Chat uses `wss://<host>/ws/chat/<room_id>/?token=<JWT access token>`.
The connection requires a valid token and room membership; messages are always
attributed to the authenticated user. `CHANNEL_LAYER_BACKEND=redis` must be set
when running more than one ASGI worker.

## 4. Payments

Follow [PAYMENTS_SETUP.md](PAYMENTS_SETUP.md), including the historical-data audit.
Gateways default to disabled. The local simulator requires an explicit flag and
DEBUG; neither it nor MTN sandbox moves funds. Live Cameroon Collection requires
approved merchant credentials and the `mtncameroon` target. Only provider-verified
payments publish a dealer order. Keep worker/beat running for reconciliation.
Ledger entries are not real refunds or dealer wallet payouts.

## 5. AI engine

Follow [AI_SETUP.md](AI_SETUP.md). The default is `openrouter/free`, restricted to
zero-priced vision endpoints and reviewed crop-specific diseases. Non-crop,
mismatched and uncertain identities are rejected before saving a diagnosis.
There is no silent rule-based or paid fallback on a provider error.

A hosted free account's quota is shared and is not a guarantee of 50 successful
daily scans. `AI_ENGINE=ollama` with a private vision model removes the provider
daily quota but requires adequate tested hardware. Use the `local-ai` Compose
profile and `OLLAMA_BASE_URL=http://ollama:11434` for the included private service.
Always disclose the selected mode's photo-processing behavior to users.

## 6. Manual validation (CI deferred)

```bash
cd backend/agrisense_backend
python -m pip install -r requirements-dev.txt
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
```

The 200+ test suite covers auth/RBAC, JWT rotation + blacklist, registration
hardening, orders/stock integrity, payments, chat permissions, disease-DB
authorization, restricted OpenRouter requests/responses, local inference and
health checks.
No GitHub Actions workflow is included in this update. CI was deferred with
user approval because the publishing connection cannot write workflow files.
Run these additional checks manually (from the repository root):

```bash
# Use an isolated test configuration/database, not live provider credentials.
(cd backend/agrisense_backend && python manage.py makemigrations --check --dry-run --noinput)
python tools/build_offline_db.py --check
(cd frontend/agrisense_app && flutter pub get && flutter analyze --no-fatal-infos && flutter test && flutter build web --release)
```

Repeat the backend suite against an isolated MySQL database using the documented
`DB_ENGINE`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_HOST` and `DB_PORT` settings.
Do not run tests against the application database or enable real collections.

Validation for this change: 331 backend tests passed on SQLite with mocked
providers; migration consistency and the bundled database check passed.
Flutter analysis/tests/build, MySQL, Docker and real Redis integration checks
have not run. Real-photo accuracy, latency, 50 successful daily analyses and
MTN sandbox/live collection also remain unverified. Test/model credentials are
not included, and no application database migration or deployment was performed.

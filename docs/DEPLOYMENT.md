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
python manage.py seed_data          # demo users, products, diseases, orders...
python manage.py createsuperuser    # optional extra admin
python manage.py runserver
```

### Frontend (Flutter)

```bash
cd frontend/agrisense_app
flutter pub get

# Android emulator: host machine is reachable at 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api

# iOS simulator / desktop / web
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api

# Physical device (same Wi-Fi):
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8000/api
```

The default `API_BASE_URL` already adapts per platform (`10.0.2.2` on Android,
`localhost` elsewhere) so plain `flutter run` also works on emulators.

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
cp backend/agrisense_backend/.env.example .env   # fill in secrets
docker compose up -d --build
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py seed_data
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
- [ ] Run `python manage.py release_stale_reservations` every few minutes (cron /
      Celery beat) so abandoned unpaid orders free their reserved stock.
- [ ] Set a strong `PAYMENT_WEBHOOK_SECRET` and configure provider callbacks to
      `POST /api/payments/webhook/` (HMAC-signed) for real MTN/Orange money flows.
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
- [ ] CI (`.github/workflows/ci.yml`) runs backend checks + tests and `flutter analyze`/test.
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
- [ ] Configure real MTN MoMo / Orange Money credentials and set
      `MTN_MOMO_ENABLED`/`ORANGE_MONEY_ENABLED`; provide the callback host for
      webhook-style payment verification.
- [ ] Add `OPENWEATHER_API_KEY` for live forecasts.
- [ ] Point the Flutter app at the production `API_BASE_URL` via
      `--dart-define` at build time (do not ship debug URLs).

## 3. WebSockets

Chat uses `wss://<host>/ws/chat/<room_id>/?token=<JWT access token>`.
The connection requires a valid token and room membership; messages are always
attributed to the authenticated user. `CHANNEL_LAYER_BACKEND=redis` must be set
when running more than one ASGI worker.

## 4. Payments

The default `SandboxGateway` simulates MTN MoMo / Orange Money deterministically:
phone numbers ending in an even digit succeed, odd digits fail. Replace it via
`payments/gateway.py` by implementing `MTNMoMoGateway`/`OrangeMoneyGateway`
(`request_payment`, `verify_transaction`) — credentials come from the
environment, and `get_gateway()` returns the live adapter only when the
corresponding `*_ENABLED=true` flag is set, so switching providers is a config
change, not a code change.

## 5. AI engine

- Primary: `AI_ENGINE=openrouter` with backend-only `OPENROUTER_API_KEY` and
  `OPENROUTER_MODEL=nex-agi/nex-n2-pro:free`.
- The request schema and a second server-side check restrict classification to
  `Healthy`, `Inconclusive`, or exact admin-reviewed `Disease` rows for the
  selected crop. No treatment fields are sent to or accepted from the model.
- Photos are resized and re-encoded without EXIF before private base64 upload.
  The privacy notice must disclose third-party image processing.
- Missing credentials, network/quota errors, malformed output and unreviewed
  labels fail closed. Keep `AI_ALLOW_RULE_FALLBACK=false` in production.
- Optional offline mode: `AI_ENGINE=tensorflow`, validated Keras artifact and
  exact class manifest; build Docker with `INSTALL_AI=true`.
- Every diagnosis stores engine, actual routed model, raw label and alternatives.
  See `backend/agrisense_backend/ai_engine/README.md` for full configuration.

## 6. Tests & CI

```bash
cd backend/agrisense_backend
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
```

The 200+ test suite covers auth/RBAC, JWT rotation + blacklist, registration
hardening, orders/stock integrity, payments, chat permissions, disease-DB
authorization, restricted OpenRouter requests/responses, local inference and
health checks.
`flutter analyze` should be run in CI for the frontend.

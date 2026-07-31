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

- Default `AI_ENGINE=rules`: deterministic feature-scoring over the
  admin-managed `Disease` knowledge base. Same photo → same diagnosis.
- Optional `AI_ENGINE=tensorflow` with `AI_MODEL_PATH` pointing at a Keras
  artifact for CNN inference; degrades gracefully to the rule-based engine
  when the artifact is missing.
- Admin content management (add/edit diseases) immediately affects diagnoses.

## 6. Tests & CI

```bash
cd backend/agrisense_backend
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
```

76 tests cover auth/RBAC, JWT rotation + blacklist, registration hardening,
orders/stock integrity, payments (amount, ownership, idempotency, premium),
chat permissions, disease-DB authorization, AI determinism and health checks.
`flutter analyze` should be run in CI for the frontend.

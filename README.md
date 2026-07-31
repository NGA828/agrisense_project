# AgriSense AI — Intelligent Agricultural Assistant

> A plant doctor, a weather forecaster and a farm-supply marketplace in one mobile app — connecting **Farmers**, **Agro-input Dealers** and **Administrators** on a single platform.

## Overview

AgriSense AI removes agricultural guesswork. A farmer photographs a sick leaf, the AI engine identifies the disease with a confidence score and a full treatment plan (causes, prevention, specific fungicides and application instructions), and the farmer can then buy the recommended inputs from verified dealers — chatting in real time and paying with **MTN Mobile Money** or **Orange Money** — all inside one green-themed Flutter app.

## Architecture

| Layer | Technology | Role |
|---|---|---|
| **Frontend** | Flutter (+ Provider, web_socket_channel) | Simple, intuitive green-themed mobile UI |
| **Backend** | Django 4.2 + Django REST Framework + Channels | Central orchestrator of all business logic |
| **Auth** | SimpleJWT (access + rotating refresh, blacklist) | Persistent secure sessions |
| **Database** | MySQL 8 (utf8mb4) — SQLite supported for local dev | Users, products, orders, payments, chats, diagnoses |
| **AI Engine** | Pluggable: rule-based scorer (default) / TensorFlow CNN (optional) | Image-based plant pathology with confidence scoring |
| **Real-time** | Django Channels WebSocket (JWT-secured) | Instant chat + live order notifications |
| **External** | OpenWeatherMap, MTN MoMo / Orange Money gateway adapters | Weather forecasts & mobile-money payments |

## Features

### Farmer
- **Persistent session** — auto-login on app start, JWT auto-refresh
- **Dashboard** — time-aware greeting, live weather mini-card, AI tips, announcements
- **AI Plant Doctor** — camera/gallery scan → disease + confidence + severity + full treatment plan + recommended products
- **Marketplace** — searchable catalog with categories, images, prices, verified/premium badges; premium dealers rank first
- **Real-time chat** — WebSocket messaging with dealers (images supported)
- **Payments** — MTN MoMo / Orange Money checkout with amount validation & provider simulation
- **History** — diagnosis history and order history modules
- **In-app notifications** — order/payment/premium updates with unread badge

### Agro-input Dealer
- **Inventory CRUD** — add/edit/delete products, images, prices, stock; availability toggle
- **Order management** — live order list, real-time "new order" notifications, accept/ship/deliver/cancel with automatic stock restore
- **Customer chat** — real-time conversations with farmers
- **Premium tier** — subscription via mobile money (or admin grant); products get search visibility boost until expiry
- **Dashboard** — real product/order/revenue counters

### Administrator
- **Analytics dashboard** — real stats + time-series charts (user growth, diagnoses, order volume, revenue) and top products/dealers
- **User management** — search, suspend/activate, delete fraudulent accounts
- **Dealer verification** — pending-application queue with approve/reject
- **Content & knowledge base** — add/edit/delete diseases; changes immediately affect AI diagnoses
- **Broadcast center** — targeted announcements (all / farmers / dealers) with active toggle
- **System health** — live API/DB/AI-engine checks

## Quick Start

### 0. Requirements

- **Python 3.10+**
- **MySQL 8.0+ or MariaDB 10.6+** (recommended; the schema uses `utf8mb4`,
  `CHECK` constraints and descending indexes). SQLite works too for quick
  local smoke tests — see the note at the end of this section.
- **Flutter 3.x** for the mobile app

### Backend (Django + MySQL)

```bash
cd backend/agrisense_backend
python -m venv venv && source venv/bin/activate     # Windows: venv\Scripts\activate
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
python manage.py seed_data            # demo users/products/diseases/orders/chats
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

### Frontend (Flutter)

```bash
cd frontend/agrisense_app
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api   # Android emulator
# or: flutter run --dart-define=API_BASE_URL=http://localhost:8000/api  # iOS/web/desktop
```

The default base URL adapts per platform automatically (`10.0.2.2` on Android, `localhost` elsewhere), so plain `flutter run` works on emulators.

### Demo accounts

| Role | Username | Password | Notes |
|---|---|---|---|
| Farmer | `farmer1` / `farmer2` | `password123` | |
| Dealer (premium) | `dealer1` | `password123` | products rank first |
| Dealer | `dealer2` | `password123` | |
| Dealer (pending) | `dealer3` | `password123` | shows in admin verification queue |
| Admin | `admin1` | `password123` | |

**Payment simulator:** MTN/Orange sandbox succeeds when the phone number ends in an even digit and fails on odd digits — so you can test both flows.

## API Endpoints

### Auth & Users
- `POST /api/auth/login/` · `POST /api/auth/register/` · `POST /api/auth/refresh/`
- `GET /api/users/me/` · `PATCH /api/users/me/`
- Admin: `GET /api/users/` · `GET /api/users/dealer_requests/` · `POST /api/users/{id}/suspend|activate|verify_dealer|upgrade_premium/` · `DELETE /api/users/{id}/`

### Diagnosis & AI
- `POST /api/diagnosis/analyze/` (multipart image + crop_type) · `GET /api/diagnosis/history/`
- `GET /api/diseases/supported_crops/` · Admin: `GET /api/diseases/list_diseases/`, `POST /api/diseases/add_disease/`, full CRUD

### Marketplace & Orders
- `GET /api/products/marketplace/?category=&search=` (premium-boosted ranking)
- Dealer: `GET /api/products/my_products/`, POST/PUT/DELETE `/api/products/{id}/`, `POST /api/products/{id}/toggle_availability/`
- `POST /api/orders/` (stock-safe) · `GET /api/orders/` · `POST /api/orders/{id}/update_status/`

### Payments
- `POST /api/payments/` (validates amount + ownership) · `POST /api/payments/{id}/process_payment/` · `GET /api/payments/{id}/verify/` · `GET /api/payments/my_payments/`

### Chat (REST + WebSocket)
- `GET/POST /api/chat/` · `GET /api/chat/{id}/messages/` · `POST /api/chat/{id}/send_message|mark_read/`
- `WS /ws/chat/{room_id}/?token=<JWT>` — authenticated + membership-checked

### Weather, Announcements, Notifications, System
- `POST /api/weather/`
- `GET/POST /api/announcements/` · `GET /api/announcements/active/` (audience-targeted)
- `GET /api/notifications/` · `GET /api/notifications/unread_count/` · `POST .../{id}/mark_read/`
- `GET /api/admin/stats/` · `GET /api/admin/analytics/?period=7d|30d|90d|1y` · `GET /api/health/`

## Security highlights

- Role-based access control everywhere; **admin cannot self-register**; privileged fields admin-only
- Dealer accounts require **admin verification** before listing products
- JWT rotation with **blacklist**; short access tokens + transparent client refresh
- **Authenticated & participant-checked WebSockets** — sender identity always comes from the token
- **Transactional, stock-safe orders** with `SELECT ... FOR UPDATE` and quantity validation
- Payment **amount integrity**, ownership checks and idempotent processing (gateway adapter pattern)
- Env-driven secrets, CORS/ALLOWED_HOSTS allow-lists, DRF throttling, image type validation
- DB constraints: non-negative price/stock/quantity

## Tests

```bash
cd backend/agrisense_backend
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
# 77 tests: auth/RBAC, JWT rotation, orders/stock, payments, chat permissions,
# disease-DB authorization, AI determinism, analytics aggregation, health checks
```

See `docs/ARCHITECTURE_ANALYSIS.md` for the full architecture & gap analysis and `docs/DEPLOYMENT.md` for production deployment (Docker, daphne, Redis channel layer, payment/weather keys).

## Project structure

```
agrisense_project/
├── backend/agrisense_backend/
│   ├── agrisense_backend/     # settings, urls, asgi (WS + WebSockets)
│   ├── users/                 # custom user, registration, admin management
│   ├── diagnosis/             # diagnoses, treatment plans, disease knowledge base
│   ├── ai_engine/             # plant-pathology engine (rule-based + TF adapter)
│   ├── products/              # catalog, orders, stock management
│   ├── payments/              # payment model + mobile-money gateway adapters
│   ├── chat/                  # chat rooms, messages, JWT WebSocket consumer
│   ├── weather/               # weather API + farming-advice engine
│   ├── announcements/         # broadcasts + per-user in-app notifications
│   └── system/                # /api/health/ probes
├── frontend/agrisense_app/
│   └── lib/
│       ├── models/            # user, product, diagnosis, notification, analytics
│       ├── providers/         # auth, diagnosis, marketplace, weather, chat, ...
│       ├── screens/           # farmer/dealer/admin UIs
│       ├── services/api/      # ApiService (JWT refresh, media resolution, WS urls)
│       ├── theme/             # green premium theme
│       └── widgets/
├── docs/                      # architecture analysis + deployment guide
├── Dockerfile
└── docker-compose.yml         # MySQL + Redis + backend (daphne)
```

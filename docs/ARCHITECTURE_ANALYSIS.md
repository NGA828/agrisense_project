# AgriSense AI — Architecture Analysis, Gap Analysis & Production Readiness Report

**Prepared by:** Senior Full-Stack Software Architect
**Scope:** Full-stack audit of the AgriSense AI monorepo (`backend/` Django + `frontend/` Flutter)
**Date:** 2026-07-31
**Branch:** `arena/019fb8bc-agrisense-project` (base commit `7e7de4c`)

---

## Table of Contents

1. [System Comprehension](#1-system-comprehension)
2. [Current State Assessment](#2-current-state-assessment)
3. [Gap Analysis](#3-gap-analysis)
4. [Security Audit](#4-security-audit)
5. [Architecture Recommendations](#5-architecture-recommendations)
6. [Production Roadmap](#6-production-roadmap)
7. [Implementation Plan (already executed)](#7-implementation-plan-already-executed)

---

## 1. System Comprehension

### 1.1 What AgriSense AI is

AgriSense AI is a three-actor agricultural ecosystem delivered as a mobile-first Flutter application with a Django REST backend:

| Actor | Core journey | Spec requirement |
|---|---|---|
| **Farmer** | Diagnose plant disease via AI → get treatment plan → buy remedy from marketplace → chat with dealer → pay via MTN MoMo / Orange Money → track history | Primary user; full journey must be seamless |
| **Agro-input Dealer** | CRUD products → receive orders + payment verification → chat with farmers → premium visibility boost | Merchant operations + monetization |
| **Administrator** | Platform analytics → user moderation (suspend/delete) → knowledge-base updates → broadcast push notifications | Governance & content management |

### 1.2 Request flow (as designed)

```
Flutter (Dining room)
   │  REST + JWT (Bearer) + WebSocket
   ▼
Django REST API (Waiter/Kitchen) ──┬── MySQL (Filing cabinet: users, products, orders, payments, diagnoses, chats)
                                  ├── AI Engine (Specialist chef: image → disease + confidence + treatment)
                                  ├── OpenWeatherMap (Outside phone line: current + 5-day forecast)
                                  └── MTN MoMo / Orange Money (Outside phone line: payment initiation/verification)
```

### 1.3 Current module inventory

**Backend (Django 4.2 + DRF + SimpleJWT + Channels):**
- `users` — custom `User` (AbstractUser + role, phone, profile photo, verification, premium flags), registration, admin user management, premium upgrade, admin stats.
- `diagnosis` — `Diagnosis`, `Location`, `TreatmentPlan`, `Disease` (admin-managed knowledge base), AI analyze action.
- `products` — `Product`, `Order` (farmer↔product), marketplace browse, dealer CRUD, order status flow.
- `payments` — `Payment` (MTN_MOMO / ORANGE_MONEY), simulated processing, order linkage.
- `chat` — `ChatRoom`, `Message`, REST endpoints + Channels WebSocket consumer.
- `weather` — `WeatherData` + live OpenWeatherMap integration with farming-advice engine + offline fallback.
- `ai_engine` — `AIModel` registry + `services.py` disease database & `analyze_disease()`.
- `announcements` — `Announcement` with audience targeting (all/farmers/dealers).

**Frontend (Flutter + Provider):**
- Providers: `AuthProvider`, `DiagnosisProvider`, `MarketplaceProvider`, `WeatherProvider`, `ChatProvider`, `AnnouncementProvider`.
- Screens: onboarding, role selection, login/register, farmer dashboard/home, AI camera scan, diagnosis result/history, treatment plan, marketplace, product detail, payment, order history, weather, chat list/chat, dealer dashboard (products/orders/chat/premium), admin dashboard (overview/users/orders/settings), admin analytics, content management, dealer verification, notifications, system health.

---

## 2. Current State Assessment

The repository contains a **structurally correct skeleton with a polished UI layer, but it is not yet a production-ready, fully-integrated system.** Three distinct maturity levels exist:

1. **Fully wired (backend ↔ frontend):** Authentication, diagnosis analyze/history, product CRUD (dealer), order placement, payment create/process, premium upgrade, admin stats + user suspend/activate, announcements.
2. **Backend exists but frontend never calls it (screens are static mockups):** Marketplace browse, weather, chat, diagnosis history/result rendering, treatment plan, admin analytics, content management (disease DB), dealer verification, notifications, system health.
3. **Missing entirely or broken:** Several API contracts the frontend already expects (`/api/diseases/add_disease/`, `/api/users/dealer_requests/`, health/analytics endpoints), WebSocket authentication, JWT rotation blacklist app, session persistence/auto-login, token refresh, real-time chat, stock/race-condition protection, and role-based write permissions on several resources.

**Proof points found during the audit:**
- `ApiService.addDisease()` POSTs to `/api/diseases/add_disease/` — no such route exists (`404`).
- `ApiService.getPendingDealers()` GETs `/api/users/dealer_requests/` — no such action exists (`404`).
- `AdminAnalyticsScreen`, `NotificationsScreen`, `ContentManagementScreen`, `DealerVerificationScreen`, `SystemHealthScreen` contain zero `ApiService` calls — all displayed data is hardcoded.
- `ChatProvider` is REST-only; `ChatConsumer` accepts any unauthenticated WebSocket and trusts a client-supplied `sender_id` (identity spoofing).
- `settings.py`: hardcoded `SECRET_KEY`; `CORS_ALLOW_ALL_ORIGINS=True`; `ROTATE_REFRESH_TOKENS=True` + `BLACKLIST_AFTER_ROTATION=True` **without** `rest_framework_simplejwt.token_blacklist` in `INSTALLED_APPS` (runtime failure on refresh rotation); access token lifetime of 1 day is excessive; no throttling.
- `register_view` lets any caller register with `role='admin'` — privilege escalation.
- `OrderViewSet.perform_create` mutates stock without `select_for_update()`/transactions (race condition) and does not validate quantity against stock.
- `ChatMessage.fromApi` reads `json['content']` but the REST serializer emits `message` (field mismatch — messages render empty).
- Frontend `baseUrl` hardcoded to `http://localhost:8000` (unusable from Android emulator/device out of the box).

---

## 3. Gap Analysis

### 3.1 Missing logical components (P0 = blocks core flows)

| # | Component | Where it should live | Why it's needed | Priority |
|---|---|---|---|---|
| G1 | Disease knowledge base seeded & admin-editable | `diagnosis.Disease` | Admin content management is a spec feature; today the AI engine uses a hardcoded Python dict, so admin edits have zero effect | **P0** |
| G2 | AI engine driven by DB knowledge base + pluggable model | `ai_engine.services` | "Update the AI's knowledge base (new diseases/treatments)" must change diagnosis output | **P0** |
| G3 | `add_disease` / disease-CRUD admin endpoints | `diagnosis.views` | Frontend already calls them | **P0** |
| G4 | `dealer_requests` (pending verification queue) | `users.views` | Dealer onboarding requires admin approval; screen exists but is a mockup | **P0** |
| G5 | Session persistence + auto-login + token refresh | `AuthProvider`, `ApiService` | "App remembers him so he doesn't log in every time"; 401-retry with refresh token | **P0** |
| G6 | Real-time chat over WebSocket with auth + membership checks | `chat.consumers`, `ChatProvider` | Spec: "Real-time chat functionality"; today REST-only + insecure WS | **P0** |
| G7 | Stock-safe order creation (transactional, `select_for_update`, stock validation) | `products.views` | Prevents overselling / negative stock | **P0** |
| G8 | Marketplace ranking: premium dealers + featured products first | `products.views.marketplace` | Premium tier's value proposition is "visibility boosting in search results" | **P0** |
| G9 | Payment integrity: amount matches order, single processing, verified status, premium-payment integration | `payments` | Trust in payment verification; spec: "payment verification" for dealers | **P0** |
| G10 | Admin analytics time-series (user growth, transaction volume, diagnosis frequency, sales) | `admin_stats` + new `analytics` endpoint | Spec: "High-level data visualization"; screen exists with hardcoded numbers | **P0** |
| G11 | Health check endpoint + system-health screen wiring | new `system` endpoint | Deployability; screen exists as mockup | **P1** |
| G12 | Notifications: real CRUD + targeting + "push" abstraction | `announcements` | Spec: broadcast push notifications; screen is static | **P1** |
| G13 | Premium expiry enforcement + auto-expiry management command | `users` | Dealers pay for a period; after expiry the boost must stop | **P1** |
| G14 | Order notifications to dealer (in-app) | `products` + `announcements` or chat | Spec: "Real-time order notifications" | **P1** |
| G15 | Farmer profile editing / password change | `users` | Basic account hygiene | **P2** |
| G16 | Pagination contract consistency | all list endpoints | Frontend mixes `List` and `{results}` expectations | **P2** |
| G17 | Dealer must be verified to create products; admin product moderation | `products` | Trust & safety | **P2** |

### 3.2 Frontend screens that are static mockups (must be wired)

| Screen | Mocked content | Real source |
|---|---|---|
| `marketplace_screen.dart` | Product cards, categories | `GET /products/marketplace/` |
| `product_detail_screen.dart` | Product info, dealer block | `GET /products/{id}/` |
| `weather_screen.dart` | Forecast cards | `POST /weather/` (live) |
| `camera_screen.dart` | "38 diseases", scan results | `POST /diagnosis/analyze/` |
| `diagnosis_result_screen.dart` | Treatment steps, recommended products | Real `Diagnosis` object from provider |
| `diagnosis_history_screen.dart` | History cards | `GET /diagnosis/history/` |
| `treatment_plan_screen.dart` | Steps, products | `Diagnosis.treatment_plan` |
| `chat_list_screen.dart`, `chat_screen.dart` | Conversations/messages | `GET /chat/`, `/chat/{id}/messages/`, WS |
| `admin/analytics_screen.dart` | 12,458 users; +18.2% etc. | `GET /admin/analytics/` |
| `admin/content_management_screen.dart` | Disease list | `GET /diseases/` + CRUD |
| `admin/dealer_verification_screen.dart` | Pending dealers | `GET /users/dealer_requests/` + `verify_dealer` |
| `admin/notifications_screen.dart` | Notification cards | `GET/POST /announcements/` |
| `admin/system_health_screen.dart` | Service status | `GET /health/` |
| `farmer_home_screen.dart` | Weather/tips/announcements | Weather + announcements providers |
| `dealer_dashboard.dart` products tab | `getMarketplaceProducts()` (wrong endpoint) | `GET /products/my_products/` |
| `admin_dashboard.dart` orders/settings tabs | Static lists | `GET /orders/` (admin), user API |

---

## 4. Security Audit

### 4.1 Critical (must fix)

1. **Privilege escalation via self-registered admin** — `register_view` accepts `role='admin'` from anyone. **Fix:** reject `admin` at registration; only an existing admin (or CLI) can create admins; also harden `UserViewSet` so `role`/`is_staff`/`is_superuser` cannot be set via the public serializer.
2. **Unauthenticated WebSocket + sender spoofing** — `ChatConsumer` neither authenticates the socket nor verifies room membership, and trusts `sender_id` from the client, allowing anyone to post into any chat. **Fix:** JWT token via `?token=` query param, `database_sync_to_async` membership check on connect, sender derived from `self.scope['user']`, reject non-participants.
3. **JWT refresh rotation broken by missing blacklist app** — `ROTATE_REFRESH_TOKENS`/`BLACKLIST_AFTER_ROTATION` are on but `token_blacklist` isn't installed → `ImproperlyConfigured` at refresh time. **Fix:** add app + migration.
4. **Hardcoded secrets in source** — `SECRET_KEY`, DB credentials in `settings.py`. **Fix:** env-driven with dev defaults + `.env.example` + `.gitignore`d `.env`.
5. **Open CORS (`*` + credentials)** — **Fix:** env-driven allow-list; never `*` with credentials in production.
6. **`ALLOWED_HOSTS` wildcard fallback** — **Fix:** env-driven with strict default.
7. **No rate limiting / throttling** on auth & AI endpoints (brute force, API abuse). **Fix:** DRF throttles: `auth` (e.g., 10/min), `ai` (e.g., 20/min/user), `anon` default.

### 4.2 High

8. **Missing authorization on Disease DB mutations** — any authenticated user can create/update/delete diseases. **Fix:** `IsAdminUser`-style check in `DiseaseDatabaseViewSet`.
9. **Non-admin users can mutate themselves via `UserViewSet` router endpoints** (edit own `role`, `email`, etc.) and `DELETE /users/{id}` is open to any authenticated user (could delete own account — acceptable, but role/email changes must be constrained). **Fix:** dedicated read-only fields + role guard.
10. **Order creation without stock validation & non-atomic stock decrement** — overselling + negative stock. **Fix:** `select_for_update`, `transaction.atomic`, quantity validation, restore stock on cancel.
11. **Payment `amount` not validated against order total; duplicate processing allowed; no provider-verification abstraction.** **Fix:** amount check, status transition guard (`pending → completed/failed` only), pluggable provider gateway with sandbox simulation + webhook-ready hooks.
12. **Password policy not enforced at registration** (`create_user` bypasses validators) and no confirmation field server-side. **Fix:** run `validate_password`, require min length, add optional confirmation.
13. **No email uniqueness race / no verification of contact info** (dealer verification is manual — fine); **Fix:** rely on unique constraint; surface a proper error for duplicate email (already exists but returns raw error).

### 4.3 Medium

14. **Excessive JWT lifetimes** (1 day access / 7 days refresh). **Fix:** short access token (15–30 min) + sliding refresh; frontend auto-refresh.
15. **Diagnosis & product image validation** — file type/size enforced only globally (10 MB); add allow-list (`jpeg/png/webp`) validation.
16. **AI engine placeholder behavior** — random/heuristic disease confidence is misleading in production. **Implemented fix:** trained TensorFlow inference when a model artifact + exact class manifest exist, DB-driven treatment knowledge, persisted engine/model provenance, confidence gating, and an explicitly labelled rule fallback that reports degraded health.
17. **No logging configuration** — add structured logging for auth failures, payments, admin actions.
18. **WebSocket `Origin` not validated; in-memory channel layer not multi-worker safe.** **Fix:** Redis channel layer for prod (config switch), origin check.
19. **`media`/`static` served by dev server only** — note deployment requirements (nginx/CDN) in docs.
20. **Django admin reachable in prod without restrictions** — document IP restriction / separate admin host.

---

## 5. Architecture Recommendations

1. **Keep the layered design** — Django as the single orchestrator is correct; Flutter stays a thin client. Do not push business logic into the app.
2. **AI Engine as an adapter** — `ai_engine/services.py` should expose `PlantPathologyEngine` with pluggable backends: `RuleBasedEngine` (DB knowledge base; deterministic, works offline, fully testable) and `TensorFlowEngine`/`PyTorchEngine` (optional `.h5`/`.tflite` artifact; used when `AI_MODEL_PATH` is configured). The API response should include `engine` + `model_version` for trust/audit.
3. **Knowledge base = source of truth** — seed `Disease` rows from the curated disease dictionary (management command), and have the analyzer resolve disease info from the DB (falling back to bundled data). Admin edits then genuinely change diagnoses.
4. **Payment gateway adapter** — `payments/gateway.py` with `MobileMoneyGateway` interface; `SandboxGateway` (current simulation) and `MTNMoMoGateway`/`OrangeMoneyGateway` skeletons using the official sandbox APIs, plus idempotency via `transaction_id` and status-transition guards.
5. **Real-time layer** — keep Channels + Redis channel layer; add token-auth middleware for WS; Flutter uses `web_socket_channel` with reconnect + backfill fallback to REST.
6. **Analytics** — compute time-series server-side with `TruncDate`-style aggregation; expose `GET /api/admin/analytics/?period=7d|30d|90d|1y`; keep charts client-side (lightweight custom painters to avoid heavy chart deps).
7. **Infrastructure** — `docker-compose.yml` (MySQL 8, Redis, backend, migrate+seed); `gunicorn` + `uvicorn/daphne` note; `.env.example`; nginx reverse proxy for media/static; CI (GitHub Actions) running Django tests + `flutter analyze`.
8. **Data integrity** — database-level checks: `CheckConstraint` for non-negative stock/price/quantity; indexes on frequently filtered columns (orders by farmer/dealer, messages by room, payments by status).
9. **Observability** — `/api/health/` (db + ai + weather dependency liveness), request logging middleware, structured logs.

---

## 6. Production Roadmap

| Phase | Items |
|---|---|
| **P0 — Integrity & security (this PR)** | G1–G10 fixes; security items 1–13; auto-login + refresh; real-time chat; analytics; health; tests |
| **P1 — Operations** | Redis channel layer + WS auth origin; gunicorn/daphne; nginx; structured logging; deploy docs; premium expiry cron; notifications push (FCM optional) |
| **P2 — Scale** | Celery for AI inference + weather caching; CDN for media; payment webhooks; moderation queue; load tests; APK signing/CI |
| **P3 — Product** | Offline diagnosis cache; multi-language (FR/EN); SMS/USSD companion; in-app wallet; dealer analytics; ML model fine-tuning pipeline with labeled dataset collection |

---

## 7. Implementation Plan (already executed)

The accompanying code changes in this branch implement the following, in dependency order:

1. **Backend hardening** — settings env-ization, blacklist app, throttling, CORS/ALLOWED_HOSTS, registration role guard, user-management authorization, disease-CRUD admin guard.
2. **Backend feature completion** — `add_disease`, `dealer_requests`, `admin analytics` (time-series), `/api/health/`, announcement targeting + admin CRUD, payment integrity + gateway abstraction + premium payment, transactional stock-safe orders, premium-boosted marketplace ranking, DB-driven AI engine with deterministic fallback, WS auth + membership.
3. **Data layer** — migrations, constraints, seed command upgraded (users, products, diseases, weather, diagnoses, orders, payments, chats, announcements) so every screen has real demo data.
4. **Frontend completion** — configurable base URL, token refresh, session restore/auto-login, real-time chat (WS + REST fallback), all mockup screens wired to live APIs, diagnosis result/history/treatment wired to real objects, dealer product management corrected to `my_products`, admin screens functional.
5. **Tests & verification** — backend test suite (auth, RBAC, orders, payments, chat, diagnosis, analytics, health) run green; `manage.py check` clean; docs updated (README + this report + deployment guide).

---

*End of analysis. See `docs/DEPLOYMENT.md` for run instructions and the updated root `README.md` for the feature/endpoint inventory.*

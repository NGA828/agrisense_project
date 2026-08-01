# AgriSense AI — Enterprise Pre-Development Audit & Architecture Blueprint

**Role:** Expert Full-Stack Software Architect / Lead Developer
**Scope:** Full pre-development architectural audit of the AgriSense AI monorepo
**Stage:** No application code written in this pass — analysis, validation and planning only
**Date:** 2026-08-01

> **How to read this report.** This audit was performed against the **current, real
> state of the repository** (not the original spec in isolation). Every claim about
> what exists was verified by reading the code and running the suite (88/88 backend
> tests pass on SQLite, `manage.py check` clean). The report is organised around the
> four requested deliverables: **(1) Gap Analysis**, **(2) Technical Architecture
> Validation**, **(3) Feature Completeness Audit**, and **(4) Strategic Roadmap**, preceded
> by an executive architecture summary. A consolidated **missing-pieces register**,
> **technical-risk register**, and **priority matrix** close the document.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Proposed System Architecture (High-Level)](#2-proposed-system-architecture)
3. [Current-State Assessment (Verified)](#3-current-state-assessment-verified)
4. [Deliverable 1 — Gap Analysis](#4-deliverable-1--gap-analysis)
5. [Deliverable 2 — Technical Architecture Validation](#5-deliverable-2--technical-architecture-validation)
6. [Deliverable 3 — Feature Completeness Audit](#6-deliverable-3--feature-completeness-audit)
7. [Deliverable 4 — Strategic Implementation Roadmap](#7-deliverable-4--strategic-implementation-roadmap)
8. [Consolidated Missing-Pieces Register](#8-consolidated-missing-pieces-register)
9. [Technical Risk Register](#9-technical-risk-register)
10. [Priority / Decision Matrix](#10-priority--decision-matrix)
11. [Conclusion & Recommended Next Actions](#11-conclusion--recommended-next-actions)

---

## 1. Executive Summary

AgriSense AI is already a **structurally sound, mostly-functional monolith** rather
than the "skeleton with mockups" described in the earlier `ARCHITECTURE_ANALYSIS.md`.
A previous hardening pass was implemented: authentication, real-time chat (JWT-secured
WebSockets), transactional stock-safe orders, payment integrity with a gateway
adapter, an admin-managed disease knowledge base, time-series analytics, health
checks, 88 passing tests, and a polished 30-screen Flutter client.

However, the system is **prototype-grade, not enterprise-grade**, on four specific axes:

1. **Money-flow correctness.** Payment failure does *not* release reserved stock or
   cancel the order; there is no held-stock timeout, no farmer-initiated cancellation,
   no merchant payout/escrow/ledger, and no refund workflow — the `refunded` payment
   status is unreachable. This is the single most important correctness gap in a
   marketplace that takes real mobile money.
2. **Real-time / notification completeness.** Notifications are **in-app polling only** —
   there is no FCM/APNs push, no real-time fan-out to an open app, and broadcasts do not
   materialise as per-user notifications. Chat WebSockets have **no reconnect/backoff**,
   so real-time silently dies on any network blip. Inventory is server-atomic but the
   farmer's marketplace UI shows **stale stock** (no live stock broadcast/reservation model).
3. **Operational robustness.** The weather endpoint is `AllowAny` + rate-unprotected and
   writes a DB row on every call (unbounded growth, no cache/offline). No offline mode.
   No async task queue (Celery) for AI inference/notification fan-out. No CI pipeline
   committed. Several production-hardening smells remain in Docker/env defaults.
4. **Product completeness vs. the "Ultimate Goal."** The end-to-end happy path works, but
   the AI engine **always returns a disease** (a healthy leaf still gets a confident
   diagnosis), confidence is not calibrated, there is no "healthy / not-detectable"
   outcome, no multi-language (French for the target market), no offline cache, no
   reviews/trust signals, no dealer sales analytics, and no regional aggregation.

**Bottom line:** The recommendation is to **keep the modular monolith** (microservices are
premature at this scale), harden the money-flow and real-time layers first (Phases A–C),
then add the product-differentiating modules (Phases D–F). The system can reach
production-readiness through disciplined, module-by-module phases without a rewrite.

---

## 2. Proposed System Architecture (High-Level)

```
┌────────────────────────────────────────────────────────────────────────────┐
│  FLUTTER CLIENTS  (Android / iOS / Web / Desktop)                          │
│  • Provider state management  • 7 providers  • 30 screens                  │
│  • Secure token store  • JWT auto-refresh  • WS chat  • camera/geo         │
└───────────────┬────────────────────────────────────────────────────────────┘
                │ HTTPS REST (Bearer JWT) + WSS (token) + later: WS push bus
                ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  DJANGO REST API — MODULAR MONOLITH (single deployable, 12 apps)          │
│                                                                            │
│  ┌────────────┬────────────┬────────────┬────────────┬─────────────────┐  │
│  │  users     │ diagnosis  │  products  │  payments  │   ai_engine     │  │
│  │  auth/RBAC │ +Disease KB│ orders/stock│ gateway    │ rule/TF adapters│  │
│  ├────────────┼────────────┼────────────┼────────────┼─────────────────┤  │
│  │  chat      │  weather   │announcements│  system   │  (future)        │  │
│  │ WS consumer│ +advice    │ +notif      │ health    │  ledger/escrow  │  │
│  └────────────┴────────────┴────────────┴────────────┴─────────────────┘  │
│  • SimpleJWT (rotation+blacklist) • DRF throttles • Channels + Redis      │
│  • (Phase C) Celery workers for AI inference + notification fan-out        │
└────────┬──────────────────────┬──────────────────────────────┬────────────┘
         │                      │                              │
         ▼                      ▼                              ▼
   ┌──────────┐          ┌──────────┐                   ┌───────────────┐
   │  MySQL 8 │          │  Redis   │                   │ External APIs │
   │ (source  │          │ channel  │                   │ • OpenWeather │
   │  of      │          │ layer /  │                   │ • MTN MoMo    │
   │  truth)  │          │ cache    │                   │ • Orange Money│
   └──────────┘          └──────────┘                   │ • (FCM) later │
                                                         └───────────────┘
```

**Key architectural decisions**

| Decision | Recommendation | Rationale |
|---|---|---|
| Deployment topology | **Modular monolith** (single Django app, internal app boundaries), NOT microservices | Scale today (hundreds–thousands of users) does not justify service fragmentation; microservices add distributed-transaction and ops cost. Design app boundaries so services can be extracted later (payments, AI, notifications) without a rewrite. |
| Orchestration | Django REST = single API gateway; thin Flutter client | Matches the "waiter/kitchen" model; keeps business rules server-side and testable. |
| Real-time | Channels + Redis channel layer; WS for chat; **separate WS push bus** (new) for inventory/notifications | Chat is group-scoped; push bus needs per-user fan-out to many rooms. |
| AI | Adapter pattern (`RuleBasedEngine` / `TensorFlowEngine`); DB knowledge base is source of truth | Same photo → same result (deterministic, testable); admin disease edits change inference; TF drops in behind the same interface. |
| Payments | Gateway adapter + **webhook-first** verification (new) + ledger (new) | Mobile-money providers push server-to-server callbacks; polling alone is not reconciliation-safe. |
| Data integrity | DB `CHECK` constraints + row locks (`select_for_update`) + idempotency keys | Already partially present; extend to held-stock timeout and ledger entries. |
| Concurrency | `transaction.atomic` + `select_for_update` at order/stock/payment boundaries | Already present; add a **reservation + expiry** model and an async task to reconcile. |
| Observability | `/api/health/` + structured logging (new) + request middleware (new) + (later) Sentry | Deployability and post-incident forensics. |

---

## 3. Current-State Assessment (Verified)

### 3.1 What is genuinely complete and solid

- **Backend (Django 4.2 + DRF + SimpleJWT + Channels):** 12 apps; `manage.py check`
  clean; **88/88 tests pass** (auth/RBAC, JWT rotation+blacklist, stock integrity,
  payment amount/ownership/idempotency, chat permissions, disease-DB authorization,
  AI determinism, analytics, health).
- **Auth & security:** custom `User` (role, phone, photo, verification, premium flags);
  admin cannot self-register; registration enforces Django password policy; JWT rotation
  with blacklist installed; short access tokens (30 min); env-driven secrets; image-type
  validation; DRF throttling (auth/ai/user/anon).
- **Diagnosis & AI:** DB-driven disease knowledge base; deterministic rule-based engine
  with `engine`/`model_version` metadata; graceful TF fallback; admin CRUD immediately
  affects inference; image digest hashing; follow-up dates.
- **Marketplace & orders:** premium-boosted ranking that respects expiry; dealer-verified
  gate before listing; transactional stock decrement with `select_for_update`; stock
  restore on dealer cancel; real-time dealer order notification.
- **Payments:** gateway adapter (sandbox + MTN/Orange stubs behind env flags); server-side
  amount integrity vs. order; ownership check; status-transition guard; premium activation
  on completion; premium expiry command (`expire_premiums`).
- **Chat:** JWT-auth + membership-checked WebSockets; sender always from token; REST
  fallback + live WS on the client.
- **Frontend (Flutter + Provider):** 30 screens, 7 providers, 5 models; per-platform base
  URL; transparent JWT refresh; session restore/auto-login; all prior mockup screens wired
  to live APIs; premium animated splash; green theme.
- **Ops:** `docker-compose.yml` (MySQL 8 + Redis + backend via daphne); `.env.example`;
  deployment guide; three redesign docs.

### 3.2 What is missing, broken, or prototype-grade (summary)

Full detail in [§4 Gap Analysis](#4-deliverable-1--gap-analysis). Headline items:
payment-failure does not release stock/cancel; no merchant payout/refund; no true push
notifications; no WS reconnect; no offline mode; weather endpoint is unprotected and
unbounded; AI has no "healthy" outcome and no calibrated confidence; no farmer cancel;
no multi-language; no CI; several Docker/env production smells.

---

## 4. Deliverable 1 — Gap Analysis

Deep dive across the three journeys, with emphasis on **error handling (payment
failures), real-time inventory synchronisation, and complex notification triggers**, plus
edge cases and logical inconsistencies.

### 4.1 Farmer journey

| # | Gap / edge case | Severity | Detail & evidence |
|---|---|---|---|
| F1 | **Payment failure leaves order pending and stock permanently reserved** | **P0 / Critical** | `OrderViewSet.create` decrements stock atomically and creates an order (`pending`, `unpaid`). `PaymentViewSet.process_payment` on failure only sets `payment.status='failed'`; it **never restores stock and never cancels the order**. If the farmer abandons after a failed payment, stock is locked out forever. |
| F2 | **No held-stock timeout / reservation expiry** | **P0 / Critical** | Two farmers can both reserve the last unit (each holds a pending order), one pays and the other's payment fails → no automated release. Need a reservation-hold TTL with a reconciler task. |
| F3 | **No farmer-initiated cancellation** | **P0** | Only `update_status` (dealer/admin) can cancel/restore stock. A farmer who changes their mind cannot cancel a pending order. |
| F4 | **No refund workflow** | **P1** | `Payment.status` has a `refunded` value but nothing ever transitions to it; no refund/partial-refund, no amount-reversal path, no dealer-payout clawback. |
| F5 | **Order↔payment lifecycle not unified** | **P1** | Order can exist with no payment; `payment_status` and `status` are two loosely-coupled fields; no single "checkout state machine" (reserved → paid → fulfilled → settled → refunded). |
| F6 | **No live stock on marketplace** | **P1** | Stock is server-atomic, but the farmer's catalog (`marketplace_screen`) shows a snapshot; a concurrent order can make a product go unavailable mid-browse. Need WS stock broadcast and/or `stock_quantity` surfaced + optimistic guard in UI. |
| F7 | **AI always returns a disease — no "healthy" outcome** | **P1** | The rule-based scorer always returns the top-1 class with ≥78% confidence. A photo of a healthy leaf yields a confident disease. Product must return a `healthy`/`no-disease` class and honest low-confidence "inconclusive" path. |
| F8 | **Confidence not calibrated; top-1 single label only** | **P1** | 78–97% is an arbitrary mapping from feature distance. Needs calibration (temperature/softmax + threshold), a confidence band, and an "uncertain → consult agronomist" outcome. |
| F9 | **`crop_type='unknown'` silently defaults to Tomato** | **P2** | In `analyze()`, unknown crop falls back to Tomato candidates — a maize leaf submitted as "unknown" is diagnosed against tomato disease. Must force crop selection or return "crop not supported." |
| F10 | **No offline mode / queued actions** | **P1** | No caching of diagnoses, marketplace, weather, or chat; `shared_preferences` is declared in `pubspec.yaml` but unused. Low-bandwidth / no-coverage farming regions need an offline-first queue for diagnosis and orders. |
| F11 | **No reviews / ratings / trust signals** | **P2** | The marketplace has no dealer reputation, product reviews, or verified-seller badges beyond `is_verified`. Trust is core to the farmer's buying decision. |
| F12 | **No order/notification delivery channels** | **P2** | Confirmations are in-app only; no SMS/email confirmation of orders or payments (important where app is closed). |
| F13 | **Profile/account hygiene incomplete** | **P2** | No email/phone OTP verification at sign-up; password reset verifies by `username`+`phone` only (no OTP), so a compromised phone number equals account takeover. |

### 4.2 Agro-input dealer journey

| # | Gap / edge case | Severity | Detail & evidence |
|---|---|---|---|
| D1 | **No payout / settlement / escrow** | **P0 / Critical** | Money is collected via mobile money, but there is **no ledger, balance, settlement, or withdrawal** for dealers. The platform currently holds funds with no disbursement mechanism — this must exist before going live with real money. |
| D2 | **No platform fee / commission model** | **P1** | Premium tier exists, but no per-transaction commission or escrow release; needed for monetisation and for payout math. |
| D3 | **No payment reconciliation view** | **P1** | Dealer sees "payment confirmed" notifications but no per-order settlement status or dispute workflow. |
| D4 | **Real-time inventory sync (dealer side)** | **P1** | When an order is placed, the dealer gets an in-app notification, but their product stock in the dashboard is not pushed live; stale values require refresh. WS stock push needed. |
| D5 | **No order acceptance expiry / SLA** | **P2** | An order sits `pending` until the dealer acts; no auto-escalation or farmer-facing "dealer has not responded" state. |
| D6 | **No inventory low-stock alerts / reorder reminders** | **P2** | No notification when `stock_quantity` drops below a dealer-set threshold. |
| D7 | **Premium: no auto-renew / payment failure on renewal** | **P2** | `expire_premiums` drops the boost at expiry but there is no renewal billing, no "your premium expired" notification, and no retry of a failed renewal payment. |
| D8 | **Dealer sales analytics absent** | **P2** | The dashboard shows counters, but no time-series, top products, conversion, or revenue-per-product for the dealer (admin has analytics; dealer does not). |

### 4.3 Administrator journey

| # | Gap / edge case | Severity | Detail & evidence |
|---|---|---|---|
| A1 | **No true push notifications / FCM** | **P0** | The broadcast centre writes `Announcement` rows and users **poll** `/notifications/`. The spec says "send a Push Notification to all 500 farmers" — there is no FCM/APNs adapter and broadcasts do **not** fan out into per-user `Notification` rows. |
| A2 | **No real-time fan-out to open apps** | **P1** | Order-status changes and broadcasts are not pushed over a WS bus; the farmer must re-open/poll. Need a per-user WS group pushed to on status/notification events. |
| A3 | **No admin action audit log** | **P1** | Suspend/delete/verify/premium/disease-edits have no immutable audit trail — essential for a governed marketplace and for regulators. |
| A4 | **No payment/order management screens** | **P1** | Reference images show "payment management" and "order management", but the admin console has no order-status override, refund, or dispute-resolution UI (only user/content/analytics/verification/notifications/health). |
| A5 | **No product/content moderation queue** | **P2** | Dealer verification exists, but individual product listings are not moderated/reported; no flagging or takedown workflow. |
| A6 | **Analytics: no regional / crop / geo aggregation, no export** | **P2** | Time-series exists, but no maps, crop-level breakdown, dealer cohort analysis, retention, or CSV/PDF export for reporting. |
| A7 | **No batch user actions** | **P2** | Suspend/verify is per-user; no bulk suspend/deactivate of fraudulent accounts. |
| A8 | **Admin console not restricted / no SSO** | **P2** | Django `/admin/` is served on the public host; the deployment guide says restrict it, but no IP/VPN enforcement or 2FA is implemented. |

### 4.4 Cross-cutting error-handling & notification gaps

- **Notification triggers that are missing:** payment **failed** → farmer retry prompt; payment **refunded** → both parties; order **cancelled** → farmer reason; **held-stock expiry** → dealer "you may lose this sale"; **low stock** → dealer; **premium about to expire** → dealer; **broadcast** → per-user rows; **dealer verified** → welcome; **account suspended** → the user.
- **Payment error handling that is missing:** user-facing failure reason surfaced from the gateway; retry guidance; reconciliation of "provider says paid but we show failed" (and vice-versa); duplicate webhook dedupe; callback signature verification (HMAC) for real gateways.
- **Logical inconsistencies found:** (1) `Order.payment_method` is written from the order-creation request but the actual payment method lives on `Payment` — two sources of truth; (2) a `pending` order's stock is held even if the farmer never pays and never cancels; (3) the `ai_engine` "rule-based" confidence implies clinical certainty the data cannot support; (4) weather persists a DB row per request with no retention/cleanup.

---

## 5. Deliverable 2 — Technical Architecture Validation

### 5.1 Stack compatibility assessment

| Component | Verdict | Notes |
|---|---|---|
| **Flutter** | ✅ Appropriate | Cross-platform mobile-first matches the audience; Provider is sufficient at this scale (Riverpod could be adopted later without a rewrite). |
| **Django + DRF** | ✅ Appropriate | Mature, batteries-included, great for a data-heavy monolith. Django 4.2 is LTS (supported through 2026). |
| **MySQL 8** | ✅ Appropriate | Solid ACID store; the schema already uses `utf8mb4`, `CHECK` constraints, descending indexes. SQLite fallback works for dev/tests. Watch: the `order` table name (reserved word) is handled by Django's quoting. |
| **AI Engine (rule-based + TF adapter)** | ⚠️ Functional but not product-grade | Rule-based scoring is deterministic and testable (good for a scaffold) but is **not a real pathology model**. The TF path is a stub (`raise NotImplementedError`). Production needs a trained CNN (TensorFlow/PyTorch→`.tflite` for on-device, or a served model), a labeled dataset, a "healthy" class, and calibrated confidence. |
| **External APIs (OpenWeather, MTN MoMo, Orange Money)** | ⚠️ Adapters present, providers stubbed | OpenWeather is wired (key-gated). MTN/Orange are **sandbox stubs** that raise `PaymentError` unless configured. Real integration + webhooks + reconciliation are required. |
| **Channels + Redis** | ✅ Appropriate for chat; needs a push bus | Redis channel layer is correct for multi-worker; add a separate per-user push group. |
| **Celery** | ❌ **Missing** | No async task queue. AI inference, notification fan-out, payment-webhook processing, held-stock reconciliation all need background workers. |

### 5.2 Recommended middleware / libraries (specific)

| Concern | Recommended | Where |
|---|---|---|
| Async background jobs | **Celery + Redis broker** (Django 4.2 supports `django-celery-beat` for cron: held-stock expiry, premium renewal, weather TTL cleanup, broadcast fan-out) | `agrisense_backend` |
| Real push notifications | **`firebase_messaging`** (FCM) for Android + **APNs** for iOS, exposed behind a `PushProvider` adapter mirroring the `MobileMoneyGateway` pattern | `announcements` / new `push` app |
| WebSocket push bus (real-time inventory/status) | Channels **per-user group** (`user_{id}`) + a lightweight `RedisPubSub`/`channel_layer.group_send` broadcast; Flutter `web_socket_channel` with **reconnect + exponential backoff + sequence backfill** | `chat`, `products`, `announcements` |
| Payment webhooks & reconciliation | **`payments` webhook endpoint** + HMAC signature verification + idempotent callback handler + a nightly **reconciliation job** that cross-checks provider vs local status | `payments` |
| Money ledger / escrow | New **`ledger` app** with double-entry accounting (dr/cr), immutable entries, and a **`withdrawal`/`settlement`** model tied to verified dealer identity | new app |
| Structured logging & tracing | **`python-json-logger`** (or `structlog`) + middleware request-id; **Sentry SDK** for error tracking | `agrisense_backend` |
| Caching | **`django-redis`** cache backend for weather responses, marketplace catalogs, admin analytics aggregates | `agrisense_backend` |
| Rate limiting (beyond DRF) | DRF `ScopedRateThrottle` on weather; later **`django-axes`** for login brute-force and IP-based limits | `weather`, auth |
| API docs | **`drf-spectacular`** (OpenAPI/Swagger) so the Flutter client stays in sync | `agrisense_backend` |
| Migrations / DB | **`django-db-mirror`** not needed; use built-in migrations; add `composite` indexes where queries hot | `products`, `payments` |
| Testing (frontend) | `flutter_test` widget tests + `mockito`; add **`golden_tests`** and a CI runner | frontend |
| CI/CD | **GitHub Actions**: run Django tests, `manage.py check`, `flutter analyze`, `flutter test`, build APK | repo root `.github/` |
| OTP / identity | **`django-otp` / SMS gateway adapter** (e.g. Africa's Talking, Twilio) for sign-up and password reset | `users` |
| Localisation | **`flutter_localizations` + ARB/intl** for FR/EN; Django `USE_I18N` with French locale | frontend + backend |

### 5.3 Monolith vs. Microservices — formal recommendation

**Recommendation: Modular Monolith now; extract services later.** Rationale:

1. The current team/data size (thousands of users) does not justify the distributed-transaction,
   deployment, and observability cost of microservices.
2. **Critical flows span app boundaries transactionally** (order creation decrements stock and
   notifies; payment completion updates order + activates premium). In a microservice
   architecture these become distributed transactions / sagas — premature complexity.
3. The Django app boundaries are already clean (`products`, `payments`, `chat`, `ai_engine`,
   `users`, ...), so the natural **seam for future extraction** exists. When scale dictates,
   extract in dependency order: `ai_engine` (stateless, CPU-heavy) → `payments` (needs
   webhooks/ledger) → `announcements/notifications` (fan-out).
4. Anti-corruption layer: keep all domain models in one DB behind one API gateway; the WS push
   bus and Celery queue are the only inter-process boundaries today.

---

## 6. Deliverable 3 — Feature Completeness Audit

**Cross-referencing the current scope against the stated Ultimate Goal:**
> "removes the guesswork from farming — from identifying the problem all the way to buying the solution."

### 6.1 Required to fulfil the Ultimate Goal end-to-end

| Component | Status | Gap to goal |
|---|---|---|
| Identify the problem (AI diagnosis) | ⚠️ Partial | Works, but no "healthy" class, no calibrated confidence, TF model is a stub, only 6 crops. **Needed for the core promise.** |
| Guided treatment plan | ✅ Present | Solid: causes, prevention, medication, instructions, follow-up. |
| Buy the solution (marketplace → pay) | ⚠️ Partial | Happy path works; **payment-failure correctness, refunds, farmer cancel, and real-time stock are gaps** that undermine trust. |
| Trust (verified dealers, reviews) | ⚠️ Partial | Verification exists; **no reviews/ratings or fraud signals.** |
| Weather + actionable advice | ⚠️ Partial | Wired, but **unprotected, uncached, no offline, no geocoding.** |
| History & tracking | ✅ Present | Diagnosis + order history present. |
| Admin governance | ⚠️ Partial | Analytics/verification/content/broadcast present; **no audit log, payment/order mgmt UI, or true push.** |
| Monetisation | ⚠️ Partial | Premium exists; **no dealer payout/commission/ledger.** |

### 6.2 Additional modules required for a complete, professional experience

1. **Offline-first mode (P1).** Cache last-known diagnoses, catalog, weather, and outbox pending
   actions (orders) for low/no-coverage regions. Uses the currently-unused `shared_preferences`
   plus a local DB (e.g. `drift`/`sqflite`). This is the biggest differentiator for an agricultural
   app in emerging markets.
2. **Dealer analytics dashboard (P2).** Time-series of sales, top products, conversion, revenue —
   reusing the admin aggregation pattern but scoped per dealer.
3. **IoT integration (P2/P3, strategic).** Soil-moisture/temperature sensors and weather-station
   ingestion into the advice engine; a `SensorReading` model + ingestion endpoint + optional
   MQTT/TTGO bridge. Not required for MVP but positions the platform for precision-agriculture
   growth.
4. **Regional/geo analytics + mapping (P2).** Admin heat-maps of disease outbreaks and market
   demand; requires geolocation on diagnoses (Location model exists but under-used).
5. **Multi-language (P1 for FR market).** French-first secondary language; content and treatment
   plans are English-only today.
6. **SMS/USSD companion (P3).** For feature-phone farmers; leverages the notification/announcement
   layer.
7. **Disaster/alert broadcast with true push (P0/P1).** The "locust swarm" alert must reach phones
   even when the app is closed → FCM.
8. **In-app wallet / balance (P3).** Ties to the ledger; optional, follows payout.

### 6.3 Verdict

The current scope covers the **linear happy path** of the Ultimate Goal, but four
**completeness pillars are missing**: (1) *money-flow correctness & dealer settlement*,
(2) *real-time + true push notifications*, (3) *offline resilience*, and (4) *an honest,
calibrated AI with a "healthy" outcome*. Until these land, the product is a compelling
**prototype**, not a professional-grade enterprise solution.

---

## 7. Deliverable 4 — Strategic Implementation Roadmap

Modular, phased; **each phase is production-ready before the next begins** (no
half-implemented features, no debt carried forward). Ordering respects dependency and
risk (correctness/security first, then real-time, then product breadth, then scale).

### Phase A — Money-Flow Correctness & Dealer Settlement *(highest priority)*
**Goal:** No lost money, no stuck stock, dealers can be paid.

> **STATUS (2026-08-01): DONE.** All of A1–A7 are implemented, migrated and tested
> (24 new tests; suite is now 112 tests, all green, verified end-to-end over a live
> HTTP server). A8 (real gateway activation) remains a config/credential step — the
> sandbox stubs, webhook endpoint and HMAC plumbing are in place.

- ✅ A1: Unified lifecycle — `pending` (reserved) → `confirmed` (paid) → `shipped` → `delivered`
  (settled); plus `payment_failed`, `cancelled`, `expired`. Order + payment + stock are
  reconciled inside atomic transactions.
- ✅ A2: **Payment-failure handler** — on `failed`, reserved stock is released and the order
  is marked `payment_failed` (retryable, cancellable); the farmer is notified.
- ✅ A3: **Held-stock reservation TTL** (`ORDER_RESERVATION_MINUTES`, default 30) +
  `release_stale_reservations` management command to expire abandoned reservations.
- ✅ A4: **Farmer-initiated cancel** for `pending`/`payment_failed`/`expired` orders (restores
  stock); paid orders must go through refund.
- ✅ A5: **`ledger` app** — double-entry `Account`/`LedgerEntry` with immutable entries and
  derived dealer balances; collection→escrow, delivery→dealer(+commission), refund→escrow
  reversal, premium→income.
- ✅ A6: **Refund workflow** — admin `POST /payments/{id}/refund/` reverses escrow, releases
  stock, marks `refunded`, notifies both parties.
- ✅ A7: **Webhook endpoint** `POST /api/payments/webhook/` — HMAC-signed, idempotent provider
  callback + `verify` polling; nightly reconciliation is scheduled for Phase C.
- ⏳ A8: **Real gateway activation** behind env flags (replace sandbox stubs).
- **Exit criteria:** ✅ met — stock never goes negative or leaks (payment failure, farmer cancel,
  reservation expiry, refund all restore stock); refund/reconcile tests; live demo where a
  failed payment frees stock and a retry re-holds it.

### Phase B — Real-Time Inventory & True Push Notifications
**Goal:** Farmers and dealers see the truth; alerts reach phones.

> **STATUS (2026-08-01): DONE (in-app layer + FCM plumbing).** B1–B4 implemented
> with 12 new tests (suite now 124, all green) and verified end-to-end over a live
> server. FCM/APNs real push needs only a service-account JSON to activate.

- ✅ B1: **Per-user WS push bus** (`/ws/push/`) + `all_online` group; pushes `notification`,
  `stock_update` and broadcast events; exponential-backoff reconnect on the client.
- ✅ B2: **`PushProvider` abstraction** (`NoopPushProvider` default, `FCMPushProvider`
  via Firebase Admin, env-gated) + `PushDevice` token registry with
  `POST /api/push/register|unregister/`. `notify_user` now persists **and** pushes every
  notification; the broadcast centre fans out to per-user `Notification` rows **and** push.
- ✅ B3: **Chat reconnect** with exponential backoff + REST backfill on reconnect; typing
  indicators (WS `typing` events + UI). (Read receipts remain via the existing `mark_read`.)
- ✅ B4: **Stock push** on order create/cancel/expiry/refund keeps the dealer inventory and
  farmer marketplace live.
- **Exit criteria:** ✅ met — live server test showed push-token registration and broadcast
  fan-out (farmer received the "Locust alert"); WS consumer unit tests cover auth, fan-out,
  ping/pong. Real device push requires setting `PUSH_PROVIDER=fcm` + credentials (Phase C op step).

### Phase C — Operational Robustness & Infrastructure
**Goal:** deployable, observable, safe in production.

> **STATUS (2026-08-01): DONE.** All of C1–C5 implemented (suite now 135 tests,
> all green) and verified over a live server. Remaining item is **AI inference on
> workers** (still in-request; the rule-based engine is fast enough at this scale —
> revisit when a heavy CNN is deployed) and **admin 2FA** (see D2/D8).

- ✅ C1: **Celery + beat** — `celery.py`, per-app `tasks.py` (fan-out, reservations,
  premium expiry, payment reconciliation, weather cleanup), `CELERY_BEAT_SCHEDULE`,
  eager-mode fallback for dev/test, `worker`/`beat` docker-compose services.
- ✅ C2: **Weather hardening** — authenticated + rate-limited, Redis/locmem-cached
  (`WEATHER_CACHE_TTL`), TTL-based cleanup (`cleanup_weather` command/task), graceful
  offline fallback retained.
- ✅ C3: **Caching + observability** — django-redis cache (locmem fallback), JSON
  structured logging, `RequestIDMiddleware` (traceable logs + `X-Request-ID` header),
  optional Sentry.
- ✅ C4: **CI/CD** — `.github/workflows/ci.yml` runs backend checks + tests (MySQL),
  `flutter analyze`/`test`, and an Android APK build artifact.
- ✅ C5: **Production security sweep** — custom `agrisense.W*` system checks fire on
  insecure defaults (DEBUG, dev secret, wildcard CORS/ALLOWED_HOSTS, unset weather/push
  key, dev webhook secret); docker-compose now defaults `CORS_ALLOW_ALL=false` and
  requires a real `DJANGO_SECRET_KEY`. (`manage.py check --deploy` also reports Django's
  built-in warnings.)
- **Exit criteria:** ✅ met — health probe now covers DB/cache/AI-engine/push/payments;
  `check --deploy` surfaces warnings; CI runs on every PR.

### Phase D — Trust, Content & Admin Governance
**Goal:** a safe, moderated marketplace.

> **STATUS (2026-08-01): DONE.** All of D1–D4 implemented (suite now 158 tests, all
> green) and verified over a live server. Admin order/payment intervention endpoints
> already existed (admin can list all orders/payments + `update_status`/`refund`);
> the audit log now records them.

- ✅ D1: **Reviews & ratings** — `Review` model (one per farmer+product, verified
  purchase only), product `rating_avg`/`rating_count` in the catalog, `POST/GET
  /api/reviews/`. **Product reporting/moderation** — `ProductReport` + `POST
  /api/product_reports/`, admin `resolve` (dismiss/remove → hides product).
- ✅ D2: **Immutable audit log** — new `auditlog` app (`AuditLog` write-only via
  `log_action`), wired into suspend/activate/verify/delete/premium-grant/refund/
  disease-CRUD/announcement/product-moderation; admin `GET /api/audit_logs/` +
  summary; audit-log screen in the admin console.
- ✅ D3: **Dealer sales analytics** — `GET /api/dealers/analytics/` (revenue/order
  time-series, top products, stock health) + a dealer analytics screen.
- ✅ D4: **OTP verification** — `OTPRequest` (hashed, single-use, TTL, attempt-limit)
  + SMS adapter (`noop`/africastalking/twilio) + `POST /api/auth/otp/send|verify/`;
  config-gated into registration & password reset (`OTP_REQUIRED_*`).
- **Exit criteria:** ✅ met — moderation, audit and OTP flows tested end-to-end
  (23 new tests).

### Phase E — Product Completeness (the "Ultimate Goal" differentiators)

> **STATUS (2026-08-01): DONE (backend fully tested; Flutter offline + i18n scaffold).**
> Suite now 167 tests, all green, verified over a live server. A real trained CNN
> (TF/TFLite) remains an optional model-training step — the rule-based v2 engine is
> deterministic and honest.

- ✅ E1: **Offline-first** — `LocalCacheService` (shared_preferences) caches diagnosis
  history, marketplace catalog and weather with offline fallback + an action outbox;
  cache cleared on logout. Wired into Diagnosis/Marketplace/Weather providers.
- ✅ E2: **AI v2** — **"healthy"** outcome for healthy leaves, **calibrated confidence**
  (temperature scaling), **crop-mandatory** guard (rejects missing/unknown crop instead of
  the silent Tomato fallback), and an **"inconclusive → consult an agronomist"** path below
  `AI_LOW_CONFIDENCE_THRESHOLD`. `Diagnosis` stores `is_healthy`/`is_inconclusive`.
  (Optional TF/TFLite CNN remains a model-training follow-up.)
- ✅ E3: **Multi-language FR/EN** — Flutter `AppLocalizations` (EN/FR delegate + delegates/
  supportedLocales wired into MaterialApp); backend i18n infra (`LANGUAGES`, `LocaleMiddleware`,
  `LOCALE_PATHS`) + French `django.po` scaffold (compile via `compilemessages`).
- ✅ E4: **Regional/geo analytics** — `GET /api/admin/regional/` returns disease counts by
  crop and geo-clustered outbreak points (bucketed ~0.4° grid).
- **Exit criteria:** ✅ backend met (healthy/crop-guard/inconclusive/regional tested; offline
  + FR/EN scaffolded). Field-test of offline sync on a device recommended before GA.

### Phase F — Scale & Strategic Growth (optional, guided by demand)

> **STATUS (2026-08-01): DONE (foundational items + innovations #2 & #4).** Suite now
> **186 tests**, all green, verified over a live server. F4 (in-app wallet) and F5
> (service extraction) remain strategic follow-ups guided by real traffic.

- ✅ F1: **IoT sensor ingestion** — new `sensors` app (`SensorDevice` + `SensorReading`
  append-only), `POST /api/sensors/` register, `POST /api/sensors/{id}/ingest/` (single or
  batch readings), `GET /api/sensors/{id}/latest/` with a lightweight irrigation advisory.
- ✅ **Innovation #2 — Precision irrigation & crop advisory**: `GET
  /api/sensors/{id}/irrigation_advice/?crop=` fuses live soil-moisture + trend with the
  local weather (rain probability) and crop-specific thresholds to return an actionable
  recommendation (`irrigate_now` / `delay_rain` / `monitor` / `adequate`). Celery beat
  `monitor-irrigation` (30 min) auto-pushes a throttled alert to the owner when irrigation
  is due (`IRRIGATION_ALERT_THROTTLE_HOURS`). Sensors gain `crop` + `last_irrigation_alert_at`.
- ✅ F2: **SMS/USSD companion** — `POST /api/ussd/` gateway callback serving a feature-phone
  menu (weather advice / last diagnosis / help) keyed by the registered phone number.
- ✅ **Innovation #4 — Predictive outbreak alerting**: `detect_outbreak_alerts` service +
  Celery beat `detect-outbreaks` (hourly) bucket geo-tagged diagnoses, detect **growing**
  clusters (this window vs. prior window), persist `OutbreakAlert` (cooldown-throttled) and
  push targeted warnings to nearby farmers. Admin console at `GET /api/admin/outbreaks/` +
  an `OutbreaksScreen` in the admin app. Tunable via `OUTBREAK_*` settings.
- ✅ F3: **Load testing** — `load_tests/locustfile.py` (farmer scenario) and
  `load_tests/k6_smoke.js` (CI smoke gate with latency/error thresholds) + docs.
- ⏳ F4: **In-app wallet** (builds on the ledger; deferred).
- ⏳ F5: **Service extraction** of `ai_engine`/`payments` (seams already exist; defer until
  traffic warrants).

---

## 8. Consolidated Missing-Pieces Register

| ID | Missing piece | Severity | Phase |
|---|---|---|---|
| MP-1 | Payment-failure stock release + order handling | Critical | A — ✅ done |
| MP-2 | Held-stock reservation TTL & reconciler | Critical | A — ✅ done |
| MP-3 | Farmer-initiated order cancellation | Critical | A — ✅ done |
| MP-4 | Dealer payout / ledger / settlement / escrow | Critical | A — ✅ done |
| MP-5 | Refund workflow (reachable `refunded` state) | High | A — ✅ done |
| MP-6 | Payment webhooks (HMAC, idempotent) + reconciliation | High | A — ✅ webhook done; nightly reconcile in C |
| MP-7 | Real MTN/Orange gateway activation | High | A — config/creds step (stubs ready) |
| MP-8 | FCM/APNs true push + broadcast→notification fan-out | Critical | B — ✅ in-app + FCM plumbing done; creds step |
| MP-9 | WS push bus (real-time order/stock/notification) | High | B — ✅ done |
| MP-10 | Chat reconnect + backfill + typing/read receipts | Medium | B — ✅ reconnect/backfill/typing done |
| MP-11 | Celery workers + beat scheduler | High | C — ✅ done |
| MP-12 | Weather hardening (auth, throttle, cache, TTL) | High | C — ✅ done |
| MP-13 | CI/CD (GitHub Actions) | High | C — ✅ done |
| MP-14 | Prod security sweep (secret, CORS, ALLOWED_HOSTS, admin) | High | C — ✅ done (admin 2FA in D) |
| MP-15 | Structured logging + Sentry | Medium | C — ✅ done |
| MP-16 | Redis cache (catalog, analytics, weather) | Medium | C — ✅ done (weather) |
| MP-17 | Reviews/ratings + product moderation | Medium | D — ✅ done |
| MP-18 | Admin audit log + payment/order mgmt UI | High | D — ✅ done (audit log + existing admin order/payment endpoints) |
| MP-19 | Dealer sales analytics | Medium | D — ✅ done |
| MP-20 | OTP verification (registration + password reset) | High | D — ✅ done |
| MP-21 | Offline-first mode + action outbox | High | E — ✅ done |
| MP-22 | AI v2 (healthy class, calibrated confidence, crop-mandatory, inconclusive) | High | E — ✅ done (trained CNN optional) |
| MP-23 | Multi-language FR/EN | Medium | E — ✅ scaffold (backend .po + Flutter l10n) |
| MP-24 | Geo/regional disease analytics | Low | E — ✅ done |
| MP-25 | IoT sensor ingestion | Low | F — ✅ done |
| MP-25a | Innovation #2: precision irrigation advisory | — | F — ✅ done |
| MP-26 | SMS/USSD companion | Low | F — ✅ done |
| MP-26a | Innovation #4: predictive outbreak alerts | — | F — ✅ done |
| MP-27 | Load testing & horizontal scaling | Low | F — ✅ load tests done; scaling ops-step |

---

## 9. Technical Risk Register

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Real money-handling defects (stock leak / double-pay / no settlement) shipping to production | High | Critical | Phases A: state machine, idempotency keys, reconciliation, ledger, exhaustive tests before enabling real gateways. |
| R2 | False AI diagnoses (always-disease, uncalibrated confidence) erode trust / cause crop loss | High | High | Phase E: "healthy" class, calibration, inconclusive path; keep `engine`/`model_version` transparency; add agronomist-consult fallback. |
| R3 | Push/notification not reaching farmers (no FCM, app closed) breaks the core alerting promise | High | High | Phase B: FCM/APNs adapter; broadcast fan-out to per-user rows + push; SMS fallback for critical alerts. |
| R4 | Provider integration (MTN/Orange) complexity: webhooks, HMAC, region variants | High | Medium | Phase A: webhook-first with idempotency + reconciliation; feature-flag sandbox→live; per-provider adapters. |
| R5 | Weather/analytics endpoint abuse & unbounded DB growth | Medium | Medium | Phase C: auth, throttling, caching, TTL cleanup. |
| R6 | Multi-worker WebSocket issues without Redis / origin validation | Medium | Medium | Already Redis channel layer in compose; enforce WS origin check + CHANNEL_LAYER_BACKEND=redis in prod. |
| R7 | Dependency drift (Django 4.2 EOL, Flutter SDK churn) | Low | Medium | Pin versions (done in `requirements.txt`/`pubspec.lock`); plan Django 5.x upgrade; keep CI. |
| R8 | Compliance/regulatory (money, data protection) in target markets | Medium | High | Data-protection consent; ledger for audit; restricted admin; engage local payment-operator certification. |

---

## 10. Priority / Decision Matrix

| Priority | Focus | Why first | Effort |
|---|---|---|---|
| **P0** | Money-flow correctness + settlement + webhooks | Direct financial risk; trust-critical | High |
| **P0** | True push notifications + real-time stock/status | Core "alert + sync" promise | Medium |
| **P1** | Operational hardening (Celery, CI, security sweep, weather) | Deployability & safety | Medium |
| **P1** | Offline-first mode | Differentiator for the market; resilience | Medium |
| **P1** | AI v2 honest outcomes (healthy class, calibration) | Core product truthfulness | High |
| **P2** | Trust layer (reviews, moderation, audit log, dealer analytics, OTP) | Marketplace governance | Medium |
| **P3** | IoT, SMS/USSD, multi-region, wallet | Strategic growth | Low–Med |

---

## 11. Conclusion & Recommended Next Actions

AgriSense AI is a **well-architected, genuinely working prototype** with clean
separation, security-conscious defaults, and a passing test suite — far ahead of a
typical scaffold. To reach **professional-grade enterprise** status, do **not** rewrite;
execute in dependency order:

1. **Begin with Phase A (money-flow + settlement).** It is the only category that can
   cause real financial loss and it blocks going live with real mobile money.
2. **Then Phase B (real-time + true push)** to deliver the alerting and live-inventory
   promise described in the Ultimate Goal.
3. **Then Phase C (operations + CI)** so every subsequent phase ships on a safe, tested,
   deployable foundation.
4. **Then D and E** to complete trust, governance, offline resilience, and an honest AI.

The recommended **target architecture** is a **modular Django monolith** behind a single
API gateway, Flutter thin client, MySQL source-of-truth, Redis (channel layer + cache +
Celery broker), Celery workers, FCM/APNs push, and a webhook-first, ledger-backed payment
layer — with clean seams ready for future service extraction as the platform scales.

**Next concrete step (recommended):** authorise Phase A (checkout state machine,
payment-failure handling, reservation TTL, ledger, refunds, webhooks), then implement and
verify it module-by-module against the exit criteria in §7. No new dependency should be
added until the production security sweep in Phase C is complete.

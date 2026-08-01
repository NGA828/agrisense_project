# AgriSense AI — Frontend ↔ Backend Integration Audit

**Scope:** Cross-referenced the Flutter client (`frontend/agrisense_app/lib`) against the
Django REST backend (`backend/agrisense_backend`) for endpoint, data-type, auth and schema
mismatches that break (or could break) client↔server communication.

**Method:** enumerated every `ApiService` call and compared it to the URL router, viewset
actions, serializer fields and permission classes; ran the backend suite (186 tests, green)
and sanity-checked all edits. **All findings below are code-verified.**

---

## 🔴 Critical — breaks the app at runtime

### C1. `getWeather()` calls an authenticated endpoint without a token → weather always 401
- **Frontend:** `lib/services/api/api_service.dart → getWeather()` used
  `await http.post(..., headers: _headers)` where `_headers` is only
  `{'Content-Type': 'application/json'}` (no `Authorization: Bearer`).
- **Backend:** `weather/views.py` is `@permission_classes([permissions.IsAuthenticated])`
  (hardened in Phase C).
- **Result:** every weather call from `farmer_home_screen.dart` and `weather_screen.dart`
  returned `401 Unauthorized`; the weather widget could only ever show stale cached data
  (or the empty/error state). **The weather feature was effectively broken in the app.**
- **Fix applied:** route the request through `_send(...)` so the JWT is attached and
  transparently refreshed on 401. Verified weather only loads post-login, so this is safe.
  ```dart
  final response = await _send((h) => http.post(
        Uri.parse('$baseUrl/weather/'), headers: h, body: jsonEncode({...})));
  ```

### C2. `getHealth()` hits the wrong URL → admin "System Health" always reports unhealthy
- **Frontend:** `getHealth()` computed
  `baseUrl.replaceFirst(RegExp(r'/api$'), '') + '/health/'` → resolved to `/health/`.
- **Backend:** the health probe is mounted at `path('api/health/', health_check, ...)`.
  There is no `/health/` route.
- **Result:** `getHealth()` returned `404`, so the admin **System Health** screen always
  showed "Service unhealthy" even when everything was fine.
- **Fix applied:** call `'$baseUrl/health/'` directly (baseUrl already ends in `/api`).

---

## 🟠 Medium — schema/UX alignment (backend sends data the client ignores or mislabels)

### M1. AI v2 `is_healthy` / `is_inconclusive` not modelled client-side
- **Backend:** the `Diagnosis` serializer now emits `is_healthy` and `is_inconclusive`
  (added in Phase E for the "Healthy" / "Inconclusive" outcomes).
- **Frontend:** `Diagnosis.fromJson` ignored these fields, so the app could not render the
  distinct healthy/inconclusive states (only the raw `diseaseName`).
- **Fix applied:** added `isHealthy` / `isInconclusive` to the `Diagnosis` model
  (constructor, `fromJson`, `toJson`).

### M2. `severity: 'unknown'` (inconclusive) mislabelled as "Low"
- **Backend:** the AI v2 inconclusive path returns `severity: 'unknown'`; the DB field's
  choices now include `unknown`.
- **Frontend:** `diagnosis_result_screen.dart` mapped anything not `high`/`medium` to
  "Low" (green), so an inconclusive result showed a reassuring "Low" severity.
- **Fix applied:** added explicit `'unknown'` cases in `_severityColor` (grey),
  `_severityLabel` ("Unknown") and `_severityProgress` (indeterminate).

---

## 🟢 Verified correct (no change needed)

The following were checked and found consistent — documenting them so they are not
"re-fixed" later:

| Client call | Endpoint | Verdict |
|---|---|---|
| `login/register/refresh/password_reset/otp` | `/api/auth/*` | ✅ AllowAny; `_headers` (no token) is correct |
| `getCurrentUser` (`GET /users/me/`) | `UserViewSet.me` | ✅ path + GET method |
| `getDiagnosisHistory` / `analyzePlantImageBytes` | `/diagnosis/history|analyze/` | ✅ paths; multipart carries Bearer |
| `getMarketplaceProducts` / `getMyProducts` / CRUD / `toggle_availability` | `/products/*` | ✅ paths + methods |
| `createOrder` / `updateOrderStatus` | `/orders/*` | ✅ `{product, quantity}` / `{status}` |
| `createPayment` / `processPayment` | `/payments/*` | ✅ `{order, amount, payment_method, phone_number}` |
| `sendMessage` / `messages` / `markChatRead` / `getUnreadChatCounts` | `/chat/*` | ✅ backend accepts `content` **or** `message`; returns `message` (client reads both) |
| `getReviews` / `createReview` / `reportProduct` / `resolveReport` | `/reviews`, `/product_reports` | ✅ field names + methods |
| `getNotifications` / `mark_read` / `mark_all_read` / `unread_count` | `/notifications/*` | ✅ paths + methods |
| `getAdminStats` / `getAdminAnalytics` / `getOutbreaks` / `getHealth`(fixed) | `/admin/*`, `/api/health/` | ✅ field names match backend response |
| `getDealerAnalytics` | `/dealers/analytics/` | ✅ `revenue`, `order_volume`, `top_products`, `total_orders`, `revenue`, `low_stock_products`, `recent_orders` |
| `getMySensors` / `ingestReading` / `getIrrigationAdvice` | `/sensors/*` | ✅ paths + query params |
| Chat & push WebSockets | `/ws/chat/{id}/`, `/ws/push/` | ✅ JWT via `?token=` matches `JwtAuthMiddleware` |
| Multipart uploads (profile photo, product image, chat image, diagnosis) | — | ✅ each sets `Authorization` manually |

---

## 🟡 Latent / recommended (not currently blocking)

- **L1. OTP on registration when `OTP_REQUIRED_FOR_REGISTRATION=true`:** the client
  `register()` does not send `otp_code`. Safe today (flag defaults to `false`), but the
  client `register` signature should accept `otpCode` once OTP is enabled.
- **L2. Health endpoint auth:** `getHealth()` is unauthenticated — correct (AllowAny for
  orchestrator probes) — but if the endpoint is ever gated, route it through `_send`.
- **L3. Farmer irrigation screen / review UI** exist as API methods but no compiled screen
  consumes them yet; the admin `OutbreaksScreen` and `AuditLogScreen` are wired. No break.

---

## Summary

| ID | Severity | Area | Fix |
|---|---|---|---|
| C1 | 🔴 Critical | Weather | `getWeather` → `_send` (attach JWT) — **applied** |
| C2 | 🔴 Critical | Health | `getHealth` → `$baseUrl/health/` — **applied** |
| M1 | 🟠 Medium | AI v2 schema | add `is_healthy`/`is_inconclusive` to `Diagnosis` — **applied** |
| M2 | 🟠 Medium | AI v2 severity | handle `severity: 'unknown'` — **applied** |
| L1–L3 | 🟡 Latent | — | documented; not blocking |

Backend suite remains **186/186 green**; all Flutter edits are structurally balanced. Because
Flutter can't be compiled in this environment, please run `flutter analyze` locally to confirm.

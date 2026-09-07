# AgriSense API — Postman Testing Guide

> A complete guide to testing every AgriSense backend API endpoint in Postman.
> Covers environment setup, authentication, sample requests, and a ready-to-import
> Postman collection with environment variables and pre-request scripts.

---

## 1. Prerequisites

| Requirement | Notes |
|---|---|
| **Postman** (Desktop or Web) | https://www.postman.com/downloads/ |
| **Backend running** | Django dev server on `http://localhost:8000` |
| **Database seeded** | `python manage.py migrate && python manage.py seed_data` |

### 1.1 Start the backend

```bash
cd backend/agrisense_backend
source venv/bin/activate                 # Windows: venv\Scripts\activate
python manage.py runserver 0.0.0.0:8000
```

Sanity check the server is up:

```
GET http://localhost:8000/api/health/
```

Expected 200 response:

```json
{
  "status": "ok",
  "database": "ok",
  "cache": "ok",
  "ai_engine": "ok"
}
```

### 1.2 Demo accounts (after `seed_data`)

| Role | Username | Password | Notes |
|---|---|---|---|
| Farmer | `farmer1` | `password123` | regular farmer |
| Farmer | `farmer2` | `password123` | second farmer for chat |
| Dealer (premium) | `dealer1` | `password123` | products rank first |
| Dealer | `dealer2` | `password123` | regular dealer |
| Dealer (pending) | `dealer3` | `password123` | needs admin verification |
| Admin | `admin1` | `password123` | full access |

> **Payment simulator:** enabled local sandbox payments **always succeed** (any valid
> Cameroon number, e.g. `+237 670 00 00 08`). To test the failure flow, use a number
> ending in **0000** (e.g. `+237 670 00 00 00`) — it simulates a declined payment.

---

## 2. Set up a Postman Environment

This is the most important step — it lets every request auto-attach the JWT token
and base URL.

### 2.1 Create a new Environment

1. In Postman click **Environments** → **+** (new).
2. Name it `AgriSense Local`.
3. Add these variables:

| Variable | Initial Value | Current Value | Scope |
|---|---|---|---|
| `base_url` | `http://localhost:8000` | `http://localhost:8000` | default |
| `access_token` | _(empty)_ | _(empty)_ | default |
| `refresh_token` | _(empty)_ | _(empty)_ | default |
| `username` | `farmer1` | `farmer1` | default |
| `password` | `password123` | `password123` | default |

4. Click **Save** and select the environment from the dropdown in the top-right.

### 2.2 Add a Collection-level Auth helper

1. Right-click **Collections** → **New collection** → name it `AgriSense API`.
2. Open the collection → **Authorization** tab.
3. Type = **Bearer Token**, Token = `{{access_token}}`.
4. Open the collection → **Pre-request Scripts** tab and paste:

```javascript
// Auto-refresh JWT if it's about to expire (rough 5-min buffer)
const expiry = pm.environment.get("access_token_expiry");
if (expiry && Date.now() > Number(expiry) - 5 * 60 * 1000) {
  pm.sendRequest({
    url: pm.environment.get("base_url") + "/api/auth/refresh/",
    method: "POST",
    header: { "Content-Type": "application/json" },
    body: { mode: "raw", raw: JSON.stringify({
      refresh: pm.environment.get("refresh_token")
    })}
  }, (err, res) => {
    if (!err && res.code === 200) {
      const json = res.json();
      pm.environment.set("access_token", json.access);
      // SimpleJWT default lifetime is 5 min; adjust if you change SIMPLE_JWT
      pm.environment.set("access_token_expiry", Date.now() + 5 * 60 * 1000);
    }
  });
}
```

Now every request in the collection automatically picks up the bearer token and
re-uses it for the lifetime of the session.

---

## 3. Step 1 — Log in (get the JWT)

This is the only call that does **not** require a token.

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `{{base_url}}/api/auth/login/` |
| Headers | `Content-Type: application/json` |
| Body (raw → JSON) | See below |

```json
{
  "username": "{{username}}",
  "password": "{{password}}"
}
```

**Tests tab** — add this to capture the tokens automatically:

```javascript
pm.test("Login returns 200", () => pm.response.to.have.status(200));
const json = pm.response.json();
pm.environment.set("access_token", json.access);
pm.environment.set("refresh_token", json.refresh);
// SimpleJWT default access lifetime is 5 min
pm.environment.set("access_token_expiry", Date.now() + 5 * 60 * 1000);
pm.environment.set("user_id", json.user_id || json.id || "");
```

Send the request. You should see:

```json
{
  "access": "eyJ0eXAiOiJKV1Qi...",
  "refresh": "eyJ0eXAiOiJKV1Qi...",
  "user_id": 1
}
```

Repeat with `username=dealer1` then `username=admin1` to get all three roles'
tokens — or just log in once and use Postman's environment swap.

### 3.1 Refresh token (when access expires)

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `{{base_url}}/api/auth/refresh/` |
| Body (raw JSON) | `{"refresh": "{{refresh_token}}"}` |

Returns a fresh `access` token (and possibly a new `refresh` if rotation is on).

### 3.2 Register a new farmer

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `{{base_url}}/api/auth/register/` |
| Body (raw JSON) | See below |

```json
{
  "username": "newfarmer",
  "email": "newfarmer@example.com",
  "password": "password123",
  "password_confirm": "password123",
  "first_name": "New",
  "last_name": "Farmer",
  "phone_number": "+237670000000",
  "role": "farmer",
  "region": "Centre"
}
```

> **Important:** admin accounts cannot self-register — `role` must be
> `farmer` or `dealer`.

### 3.3 Phone OTP (registration / password reset)

```http
POST {{base_url}}/api/auth/otp/send/
Content-Type: application/json

{ "phone_number": "+237670000000" }
```

```http
POST {{base_url}}/api/auth/otp/verify/
Content-Type: application/json

{ "phone_number": "+237670000000", "code": "123456" }
```

---

## 4. Step 2 — User profile

### Get the logged-in user

```
GET {{base_url}}/api/users/me/
```

### Update profile

```
PATCH {{base_url}}/api/users/me/
Content-Type: application/json

{
  "first_name": "Updated",
  "phone_number": "+237677112233",
  "region": "Adamawa"
}
```

### Admin-only — list users / dealer requests

```
GET {{base_url}}/api/users/
GET {{base_url}}/api/users/dealer_requests/
```

### Admin actions on a user (replace `{id}` with a real user ID)

```
POST {{base_url}}/api/users/{id}/suspend/
POST {{base_url}}/api/users/{id}/activate/
POST {{base_url}}/api/users/{id}/verify_dealer/
POST {{base_url}}/api/users/{id}/upgrade_premium/
DELETE {{base_url}}/api/users/{id}/
```

---

## 5. Step 3 — Disease knowledge base & AI diagnosis

### 5.1 Get crops the AI can diagnose (DB-backed)

```
GET {{base_url}}/api/diseases/supported_crops/
```

This is the canonical list of crop names to use in the `crop_type` field of
any diagnosis request.

### 5.2 Admin — list / add / edit diseases

```
GET    {{base_url}}/api/diseases/list_diseases/
POST   {{base_url}}/api/diseases/add_disease/
GET    {{base_url}}/api/diseases/{id}/
PUT    {{base_url}}/api/diseases/{id}/
PATCH  {{base_url}}/api/diseases/{id}/
DELETE {{base_url}}/api/diseases/{id}/
```

Example `add_disease` body:

```json
{
  "name": "Tomato Early Blight",
  "crop": "Tomato",
  "symptoms": "Dark concentric spots on lower leaves",
  "causes": "Alternaria solani fungus in warm humid weather",
  "prevention": "Rotate crops, remove debris, water at the base",
  "medication": "Mancozeb 80WP — 2 g/L water",
  "instructions": "Spray every 7-10 days, 3 applications",
  "severity": "moderate"
}
```

### 5.3 Run an AI diagnosis on a leaf photo

This is the most important endpoint in the app.

| Field | Value |
|---|---|
| Method | `POST` |
| URL | `{{base_url}}/api/diagnosis/analyze/` |
| Body | **form-data** (not raw JSON) |

Form fields:

| Key | Type | Value |
|---|---|---|
| `image` | File | pick a `.jpg`/`.png` leaf photo |
| `crop_type` | Text | `Tomato` (must be in the supported crops list) |
| `latitude` | Text | _(optional)_ `4.0511` |
| `longitude` | Text | _(optional)_ `9.7679` |

> The `crop_type` field is **required** — the API will return 400 without it.
> In Postman make sure the field is **Text**, not File, for `crop_type`.

A successful response:

```json
{
  "id": 42,
  "result": "Tomato Early Blight",
  "is_healthy": false,
  "confidence": 0.87,
  "severity": "moderate",
  "engine": "openrouter",
  "trained_model": "dots-studio/dots-3-note-preview:free",
  "model_version": "v1",
  "model_label": "dots-3-note-preview",
  "alternatives": [
    {"name": "Tomato Septoria Leaf Spot", "confidence": 0.09}
  ],
  "treatment": {
    "causes": "Alternaria solani fungus...",
    "prevention": "Rotate crops...",
    "medication": "Mancozeb 80WP — 2 g/L water",
    "instructions": "Spray every 7-10 days..."
  },
  "recommended_products": [
    {"id": 7, "name": "Mancozeb 80WP", "price": "3500.00", "dealer": "AgroCare Center"}
  ]
}
```

### 5.4 Diagnosis history

```
GET {{base_url}}/api/diagnosis/history/
```

---

## 6. Step 4 — Marketplace & products

### 6.1 Browse the catalog (farmer)

```
GET {{base_url}}/api/products/marketplace/?category=Fungicide
GET {{base_url}}/api/products/marketplace/?search=mancozeb
```

Premium dealers' products are auto-ranked first.

### 6.2 Read a single product

```
GET {{base_url}}/api/products/{id}/
```

### 6.3 Dealer — my products (CRUD)

```
GET    {{base_url}}/api/products/my_products/
POST   {{base_url}}/api/products/                    # create
GET    {{base_url}}/api/products/{id}/               # read
PUT    {{base_url}}/api/products/{id}/               # full update
PATCH  {{base_url}}/api/products/{id}/               # partial update
DELETE {{base_url}}/api/products/{id}/               # delete
POST   {{base_url}}/api/products/{id}/toggle_availability/
```

`POST /api/products/` body (form-data so you can also upload an image):

| Key | Type | Value |
|---|---|---|
| `name` | Text | `Copper Fungicide 50WP` |
| `description` | Text | `Broad-spectrum fungicide for vegetables` |
| `category` | Text | `Fungicide` |
| `price` | Text | `4200` |
| `stock` | Text | `50` |
| `image` | File | _(optional)_ product photo |

### 6.4 Reviews (farmers, verified purchases only)

```
GET  {{base_url}}/api/reviews/?product=7
POST {{base_url}}/api/reviews/
```

Body:

```json
{ "product": 7, "rating": 5, "comment": "Worked great on my tomatoes" }
```

One review per farmer+product.

### 6.5 Product reports (moderation)

```
POST {{base_url}}/api/product_reports/
{ "product": 7, "reason": "Counterfeit packaging" }

POST {{base_url}}/api/product_reports/{id}/resolve/    # admin
{ "decision": "removed", "notes": "Confirmed counterfeit" }
```

---

## 7. Step 5 — Orders

### 7.1 Place an order (farmer)

```
POST {{base_url}}/api/orders/
Content-Type: application/json

{
  "items": [
    {"product": 7, "quantity": 2}
  ],
  "shipping_address": "Carrefour Bastos, Yaoundé",
  "phone_number": "+237670000000"
}
```

The server reserves stock using `SELECT ... FOR UPDATE` — quantity cannot
exceed available stock. Response contains the new order with status
`pending_payment`.

### 7.2 List orders (filtered by role automatically)

```
GET {{base_url}}/api/orders/
```

### 7.3 Dealer / farmer order actions

```
GET  {{base_url}}/api/orders/{id}/
POST {{base_url}}/api/orders/{id}/update_status/    # ship / deliver
{ "status": "shipped" }

POST {{base_url}}/api/orders/{id}/cancel/           # farmer / dealer / admin
{}
```

---

## 8. Step 6 — Payments (MTN MoMo / Orange Money)

### 8.1 Create a payment for an order

```
POST {{base_url}}/api/payments/
Content-Type: application/json

{
  "order": 17,
  "provider": "mtn_momo",
  "phone_number": "+237670000000"
}
```

> The server **re-validates the amount** against the order total — you cannot
> pay less or more.

### 8.2 Process the payment

```
POST {{base_url}}/api/payments/{id}/process_payment/
Content-Type: application/json

{ "phone_number": "+237670000000" }
```

**Sandbox rule:** phone numbers ending in an **even digit** succeed, **odd** fail.
Try `+237670000002` for success and `+237670000001` for failure.

Successful response (status 200):

```json
{
  "status": "completed",
  "transaction_id": "MTN-20250827-000123",
  "order": 17
}
```

Failure response (status 402):

```json
{
  "status": "failed",
  "reason": "Insufficient funds"
}
```

### 8.3 Verify a payment

```
GET {{base_url}}/api/payments/{id}/verify/
```

### 8.4 Refund (admin only)

```
POST {{base_url}}/api/payments/{id}/refund/
{ "reason": "Customer returned goods" }
```

### 8.5 My payments

```
GET {{base_url}}/api/payments/my_payments/
```

### 8.6 Webhook (HMAC-signed, idempotent)

The provider posts back here — useful for integration tests.

```
POST {{base_url}}/api/payments/webhook/
Headers:
  X-Signature: <HMAC-SHA256 of body using WEBHOOK_SECRET>
  X-Idempotency-Key: <unique uuid>
Body:
  { "transaction_id": "...", "status": "completed", "order": 17 }
```

---

## 9. Step 7 — Chat (REST + WebSocket)

### 9.1 REST endpoints

```
GET  {{base_url}}/api/chat/                     # list my rooms
POST {{base_url}}/api/chat/                     # create/open a room with a dealer
     { "dealer": 3 }
GET  {{base_url}}/api/chat/{id}/messages/       # paginated history
POST {{base_url}}/api/chat/{id}/send_message/   # send a message
     { "text": "Hello, is this still available?", "image": "<optional url>" }
POST {{base_url}}/api/chat/{id}/mark_read/
```

### 9.2 WebSocket (use Postman → New → WebSocket Request)

```
WS  ws://{{base_url}}/ws/chat/{room_id}/?token={{access_token}}
```

Send a message:

```json
{ "type": "message", "text": "Hi there", "temp_id": "abc-123" }
```

Receive typing events, read receipts, and new messages. The server validates
the JWT and the user's membership in the room on connect.

---

## 10. Step 8 — Weather, Announcements, Notifications

### 10.1 Weather (POST — coordinates in body)

```
POST {{base_url}}/api/weather/
Content-Type: application/json

{ "latitude": 4.0511, "longitude": 9.7679, "city": "Yaoundé" }
```

Returns a 5-day forecast with farming advice (irrigation, spraying windows,
disease pressure index).

### 10.2 Announcements (admin POST, all users GET)

```
GET  {{base_url}}/api/announcements/
GET  {{base_url}}/api/announcements/active/
POST {{base_url}}/api/announcements/         # admin
{ "title": "Frost warning", "body": "...", "audience": "farmers", "is_active": true }
```

Activating a broadcast fans out to the target users' in-app notifications
+ push bus.

### 10.3 Notifications

```
GET  {{base_url}}/api/notifications/
GET  {{base_url}}/api/notifications/unread_count/
POST {{base_url}}/api/notifications/{id}/mark_read/
```

---

## 11. Step 9 — Admin analytics & audit log

```
GET  {{base_url}}/api/admin/stats/                              # KPI cards
GET  {{base_url}}/api/admin/analytics/?period=30d               # time-series
GET  {{base_url}}/api/admin/regional/?period=7d                # disease + geo clusters
GET  {{base_url}}/api/admin/outbreaks/                          # predictive outbreak console
GET  {{base_url}}/api/audit_logs/?category=user                 # immutable log
GET  {{base_url}}/api/audit_logs/summary/
```

`period` accepts `7d | 30d | 90d | 1y`.

---

## 12. Step 10 — IoT sensors & irrigation advice

### Register a sensor (admin or dealer)

```
POST {{base_url}}/api/sensors/
{ "device_id": "SENSOR-001", "name": "Field A", "crop": "Tomato",
  "latitude": 4.0511, "longitude": 9.7679 }
```

### Ingest a reading

```
POST {{base_url}}/api/sensors/{id}/ingest/
{ "moisture": 38.2, "temperature": 27.4, "humidity": 65,
  "rainfall": 0.0, "recorded_at": "2026-08-27T10:00:00Z" }
```

You can also POST a **batch** by sending `readings: [...]` instead of a single
object.

### Get the latest reading + advice

```
GET {{base_url}}/api/sensors/{id}/latest/
```

### Precision irrigation advice (with crop)

```
GET {{base_url}}/api/sensors/{id}/irrigation_advice/?crop=Tomato
```

Possible verdicts: `irrigate_now` / `delay_rain` / `monitor` / `adequate`.

---

## 13. Step 11 — Realtime push bus (WebSocket)

For push-style live updates (new orders, stock changes, broadcasts):

```
WS  ws://{{base_url}}/ws/push/?token={{access_token}}
```

Send:

```json
{ "type": "ping" }
```

Receive (examples):

```json
{ "type": "notification", "title": "New order", "body": "..." }
{ "type": "stock_update", "product_id": 7, "stock": 48 }
{ "type": "broadcast", "title": "Frost warning", "body": "..." }
```

Register an FCM/APNs device token (so the server can push even when the app
is closed):

```
POST {{base_url}}/api/push/register/
{ "token": "fcm-device-token-here", "platform": "android" }

POST {{base_url}}/api/push/unregister/
{ "token": "fcm-device-token-here" }
```

---

## 14. Step 12 — USSD / SMS companion (feature phones)

```
POST {{base_url}}/api/ussd/
Content-Type: application/json

{ "phoneNumber": "+237670000000", "text": "1" }
```

The body mimics an Africa Talking / Hubtel callback. Send `"text": ""` to get
the menu, then `"1"`, `"1*Tomato"`, etc. The endpoint serves weather and
diagnosis menus to feature-phone farmers.

---

## 15. Step 13 — Health check (no auth)

```
GET {{base_url}}/api/health/
```

Probes DB, cache/Redis, AI engine, push and payments. The first request in
your collection should be this one — if it fails, nothing else will work.

---

## 16. End-to-end Postman test scenario

Run these in order with the same farmer session:

1. `GET  /api/health/` — server is up
2. `POST /api/auth/login/` — capture `access_token`
3. `GET  /api/users/me/` — confirm role = `farmer`
4. `GET  /api/products/marketplace/` — pick a product id
5. `POST /api/orders/` — place an order
6. `POST /api/payments/` — create a payment
7. `POST /api/payments/{id}/process_payment/` — even phone = success
8. `GET  /api/payments/{id}/verify/` — confirm `completed`
9. `POST /api/diagnosis/analyze/` — upload a leaf image with `crop_type=Tomato`
10. `GET  /api/diagnosis/history/` — see the new diagnosis
11. `POST /api/chat/` — open a room with `dealer1`
12. `POST /api/chat/{id}/send_message/` — say hello

If you swap `username` to `dealer1` and re-run login:

13. `GET  /api/products/my_products/`
14. `GET  /api/orders/` — see the new order
15. `POST /api/orders/{id}/update_status/` — `{ "status": "shipped" }`

If you swap to `admin1`:

16. `GET  /api/admin/stats/`
17. `GET  /api/admin/analytics/?period=7d`
18. `GET  /api/audit_logs/summary/`

That's the complete happy-path smoke test for the entire backend.

---

## 17. Common gotchas

| Symptom | Fix |
|---|---|
| `401 Unauthorized` everywhere | Your `access_token` expired — re-run **Login** or hit `/api/auth/refresh/`. |
| `403 Forbidden` on `/api/admin/...` | You're logged in as a farmer/dealer — switch the environment's `username` to `admin1` and re-login. |
| `400` on diagnosis saying "crop_type is required" | In Postman form-data, set the `crop_type` key type to **Text**, not File. |
| `404` on `/api/diseases/supported_crops/` | You didn't run `seed_data` — the disease table is empty. |
| Payments always fail | Phone number must end in an **even** digit for success, **odd** for failure (sandbox rule). |
| WebSocket can't connect in Postman | Make sure the URL starts with `ws://` (or `wss://` for HTTPS) and ends with `?token=<jwt>`. |
| `ImageField` uploads return 400 | File must be ≤ 10 MB (`DATA_UPLOAD_MAX_MEMORY_SIZE`) and a real image MIME type. |
| CORS errors from a web client | Add your origin to `CORS_ALLOWED_ORIGINS` in `settings.py` (or `.env`). |

---

## 18. Importing the bundled collection

Two files ship in this repo's `docs/postman/` folder:

- **`AgriSense_API.postman_collection.json`** — every endpoint above, grouped by
  feature, with pre-built request bodies.
- **`AgriSense_Local.postman_environment.json`** — the environment variables
  from section 2.

To import in Postman:

1. **File → Import…** → drag both JSON files in (or click the folder icon).
2. Open the collection, set the `AgriSense Local` environment as active.
3. Open **Auth** on the collection — paste `{{access_token}}` in the Bearer Token field.
4. Open the **Login** request → **Send**. Tokens auto-save to the environment.
5. Run the rest of the collection in order (right-click → **Run collection**)
   for a full smoke test.

You now have a clickable, reusable test harness for the entire AgriSense
backend.

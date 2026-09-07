# Payment setup and safe checkout

## The important distinction

| Mode | Real funds? | Requirements |
|---|---|---|
| Local simulator (dev default) | **No** | `DEBUG=True` (on by default there; set `PAYMENT_SIMULATOR_ENABLED=false` to disable) |
| Local simulator outside DEBUG | **No** | `PAYMENT_SIMULATOR_ENABLED=true` AND `PAYMENT_SIMULATOR_ALLOW_NON_DEBUG=true` (explicit, warned-about opt-in) |
| MTN sandbox | **No** | MTN Collection sandbox credentials |
| MTN Cameroon live Collection | Yes, on verified payer approval | Approved live merchant account, live Collection credentials and deployment configuration |

**Orange Money and card collection are not implemented.** They remain unavailable unless explicitly using the local test simulator. Setting an Orange environment flag cannot activate a real integration.

This code implements **collection**, not automatic dealer wallet payouts or live refunds. The internal ledger records balances; it does not transfer money. Live refund requests are refused rather than reporting a fictitious refund. Agree on merchant settlement/refund operations with your provider before launching a multi-dealer marketplace.

## What was fixed

- Opening checkout no longer creates an order or decrements stock. Pressing Pay creates a **buyer-only reservation** with an idempotency key and a server-calculated total.
- If the product price changed, the app shows the new total and requires another confirmation **before submitting a collection**.
- An unpaid or failed reservation is not shown in the dealer's order list/analytics and does not send a dealer new-order notification.
- `202 Accepted` from MTN means **processing**, not payment success. A phone/network timeout does not prove that a charge failed.
- Only an authenticated provider status that matches the saved reference, amount, currency and payer can confirm a real payment. Callbacks are hints; their status text is not trusted.
- Products with checkout history cannot be deleted through the API; disable them instead to retain financial records.
- Repeated taps, callbacks and verification calls reuse an unresolved attempt and record completion once. A definitively failed payment gets a new reference on retry.
- A definite failure releases stock once. Processing/review payments retain their reservation until verified; they cannot be cancelled/expired merely because a timer elapsed.
- If money arrives for a closed, already-paid or unreserved legacy order, the payment becomes `review_required`. It does **not** send the dealer a fulfilment order. The payer and administrators are notified.

## 1. Configure privately

Django reads `backend/agrisense_backend/.env`. Copy `.env.example` if needed and fill values **on the server only**. Do not paste keys into chat, commit them, include them in an APK/web build, or embed them in an image. The Docker ignore file excludes private environment files.

### Local development, no provider account

```dotenv
DEBUG=True
# The simulator is on by default in DEBUG; this line is shown for clarity.
PAYMENT_SIMULATOR_ENABLED=true
MTN_MOMO_ENABLED=false
```

Restart Django. Use any valid Cameroon mobile number, for example `+237 670 00 00 08` — **every simulated payment now completes** so demos and training sessions don't randomly fail. To exercise the failure path (declined payment, stock release, "no order was sent to the dealer"), pay from a number ending in `0000`, e.g. `+237 670 00 00 00`.

The app/notifications explicitly label successful tests as no money transferred. A failed or unpaid checkout is **never** sent to the dealer: it does not appear in the dealer's order list, analytics or notifications, and its stock reservation is released. This is only a way to exercise the workflow, **not a fix for live payments**. Never enable it for a real launch.

To keep simulated checkout working on a staging/demo server that runs with `DEBUG=False`, set `PAYMENT_SIMULATOR_ALLOW_NON_DEBUG=true` as well. This is an explicit, warned-about opt-in: Django's system checks flag it, every payment remains labelled `[TEST]`, and it must be removed before real launch.

### MTN sandbox

1. Register at the [MTN developer portal](https://momodeveloper.mtn.com/) and subscribe to the **Collection** product.
2. Follow the portal's sandbox provisioning flow to create an API user (UUID) and generate that user's API key. A Collection subscription key alone is not enough; a Disbursement key is not a Collection key.
3. Store all three values privately:

```dotenv
PAYMENT_SIMULATOR_ENABLED=false
MTN_MOMO_ENABLED=true
MTN_MOMO_ENVIRONMENT=sandbox
MTN_MOMO_PRIMARY_KEY=replace-with-collection-subscription-key
MTN_MOMO_API_USER=replace-with-provisioned-api-user-uuid
MTN_MOMO_API_KEY=replace-with-that-users-api-key
MTN_MOMO_BASE_URL=https://sandbox.momodeveloper.mtn.com
MTN_MOMO_CALLBACK_URL=
PAYMENT_PROVIDER_TIMEOUT_SECONDS=12
```

Use the scenarios/test MSISDNs supplied by the current MTN portal. The adapter accepts the MTN test-number family `46733123450`–`46733123454` in sandbox without rewriting it as a Cameroon number, as well as normal Cameroon numbers. The external sandbox uses **EUR test amounts**, not XAF and not a currency conversion. A displayed 2,000 FCFA demo order is sent as 2,000 EUR **test units only**. Do not infer a live debit or real phone approval from a sandbox result.

### MTN Cameroon live

Obtain approval and **live Collection** credentials from MTN Cameroon. Sandbox credentials do not become live by changing a flag. Confirm the assigned API host, wallet/currency, registered callback host and onboarding requirements with your MTN account manager.

```dotenv
DEBUG=False
PAYMENT_SIMULATOR_ENABLED=false
MTN_MOMO_ENABLED=true
MTN_MOMO_ENVIRONMENT=mtncameroon
MTN_MOMO_PRIMARY_KEY=replace-privately-with-live-collection-key
MTN_MOMO_API_USER=replace-privately-with-live-api-user
MTN_MOMO_API_KEY=replace-privately-with-live-api-key
MTN_MOMO_BASE_URL=https://proxy.momoapi.mtn.com
MTN_MOMO_CALLBACK_URL=https://YOUR-API-HOST/api/payments/mtn/callback/
```

The country target header is **`mtncameroon`**, not the literal word `live`; the live adapter uses XAF. Incorrect target environments and unregistered callback hosts are common MTN integration errors. [1](https://momodevelopercommunity.mtn.com/knowledge-base)

The proxy host above is the adapter's default, not proof of your merchant's onboarding configuration. Override it if MTN assigns another HTTPS host. Configure strong Django/webhook secrets, allowed hosts, trusted HTTPS origins and a production database/cache before launch. The generic HMAC bridge at `/api/payments/webhook/` is **not MTN's native callback protocol**.

## 2. Apply the update and check configuration

Back up the application database first. Then, in your existing backend environment:

```bash
cd backend/agrisense_backend
python manage.py migrate
python manage.py check_payments
python manage.py check_payments --check-auth
```

`--check-auth` obtains/verifies a Collection token; **it does not initiate a charge** and does not print credentials. A successful token proves authentication, not that a future payer will approve a collection.

For Compose, use the same private environment file for all services. From the repository root:

```bash
docker compose --env-file backend/agrisense_backend/.env up -d --build
docker compose --env-file backend/agrisense_backend/.env exec backend python manage.py check_payments --check-auth
```

The backend entrypoint runs migrations. The backend, worker and beat inherit the same payment settings. Rebuild/install the updated Flutter app as well; old clients do not know the pending/test/retry contract.

On a physical phone, build with the public HTTPS backend URL, for example:

```bash
flutter build apk --dart-define=API_BASE_URL=https://YOUR-API-HOST/api
```

On Flutter web, the default is the **browser's own origin**. Reverse-proxy `/api/`, `/media/` and `/ws/` to Django, or supply `API_BASE_URL` explicitly and configure CORS/WebSocket origins. Never point browser/phone requests at a server-side `localhost` address. If the API is behind another proxy, preserve the correct scheme/host and permit your preview/production hostname in Django.

## 3. Keep confirmation running

Run Redis, a Celery worker and Celery beat in production (already included in Compose). Beat reconciles processing payments every 60 seconds with authenticated status queries. This handles delayed/missing callbacks and farmers closing the app.

Without Celery, schedule the same one-shot command, for example once per minute:

```bash
python manage.py reconcile_payments
```

It checks unresolved submissions and expires **safe, unpaid, non-processing** reservations. It does not initiate a second collection. A provider timeout, unknown reference, unavailable gateway, amount mismatch or an old payment is **not** automatically labelled failed. Investigate persistent pending/review records against the merchant portal and provider reference.

MTN token caching is best-effort: a cache failure does not strand an attempt before contacting MTN, and never causes a second collection request. API throttling still fails closed during a cache outage, so users may temporarily receive a retryable 503. After an ambiguous payment response, check the same payment reference; do not assume failure.

Do not change environment/API-user credentials while old payments are unresolved without a reconciliation plan. Sandbox/live environment mismatches deliberately prevent verification against the wrong account.

## 4. Audit historical records before live use

Earlier versions implicitly simulated missing gateways and created dealer-visible orders before payment. Existing `completed`/`paid` rows therefore are **not proof that real money arrived**. This migration preserves historical provider references and does not retroactively invent bank confirmation or rewrite historical balances.

- Reconcile prior completed orders and dealer notifications against actual merchant statements.
- Unresolved legacy UUID5 payment references are retained for verification, never silently replaced with a new charge reference. Support must reconcile them before a new attempt.
- Review legacy orders with no reservation. New collections on those orders are refused; cancel/recreate safely after checking stock.
- Resolve `review_required` payments with the customer/provider before fulfilling or collecting again.
- Do not relabel sandbox collections as live or use the test ledger-refund action as evidence of a transfer.

## Acceptance checks before launch

1. Missing configuration: both checkout and premium purchase are unavailable; no order is sent to a dealer.
2. Simulator/sandbox success is clearly labelled **TEST**. A failure releases stock and remains invisible to the dealer.
3. With a pending payment, tap again, leave/reopen order history, or disconnect/reconnect. The same payment reference is checked; no duplicate collection/order appears.
4. A forged success callback cannot publish an order. One verified success creates one ledger entry and one dealer notification.
5. A changed product total requires confirmation before charging.
6. Test a small live collection only with the payer's explicit approval, and check the merchant statement as well as the app. Validate your live settlement/refund process separately.

Provider requests and callback behavior should be checked against the current [MTN documentation](https://momoapi.mtn.com/). Backend regression tests use mocks/SQLite; they do not substitute for sandbox, production-database concurrency, or authorised live-payment testing.

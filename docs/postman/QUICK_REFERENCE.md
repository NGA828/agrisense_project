# AgriSense — Postman Quick Reference Card

> Single-page cheat sheet for the most common test flows. For full details see
> [`POSTMAN_API_GUIDE.md`](../POSTMAN_API_GUIDE.md).

## Files to import into Postman

| File | What it is |
|---|---|
| `AgriSense_API.postman_collection.json` | 68 ready-to-send requests in 12 folders |
| `AgriSense_Local.postman_environment.json` | `base_url`, `access_token`, etc. |

## The 3 things you must do (in order)

1. **Start the server** — `python manage.py runserver` (after `migrate` + `seed_data`).
2. **Import** both JSON files (drag them into Postman, or File → Import).
3. **Send `01 - Auth → Login`** — this auto-captures the JWT and from then on
   every request in the collection is authenticated.

## The collection (the "screens" you'll test)

```
00 - Health (no auth)             1 request
01 - Auth                          5   login, refresh, register, OTP
02 - Users                         8   profile CRUD + admin actions
03 - Diagnosis & Diseases          5   AI scan, history, supported crops
04 - Products & Marketplace       11   catalog, CRUD, reviews, reports
05 - Orders                        5   create, list, status, cancel
06 - Payments                      6   create, process, verify, refund, webhook
07 - Chat (REST)                   5   rooms, messages, mark-read
08 - Weather / Announcements /…    7   weather, broadcasts, notifications
09 - Admin analytics & audit log   7   stats, analytics, outbreaks, audit
10 - IoT Sensors & Irrigation      4   register, ingest, advice
11 - Push & USSD                   4   FCM token, USSD menus
```

**Total: 68 pre-built requests across 12 folders.**

## Demo accounts (after `seed_data`)

| Role | Username | Password |
|---|---|---|
| Farmer | `farmer1`, `farmer2` | `password123` |
| Dealer (premium) | `dealer1` | `password123` |
| Dealer | `dealer2` | `password123` |
| Dealer (pending) | `dealer3` | `password123` |
| Admin | `admin1` | `password123` |

Switch the `username` in the **AgriSense Local** environment and re-run
**Login** to test each role.

## Happy-path smoke test (15 clicks)

Run in this order with `username=farmer1`:

1.  `00 → Health check` — server up
2.  `01 → Login` — captures token
3.  `02 → Get me`
4.  `04 → Marketplace (search)` — note a `product_id`
5.  Set the `product_id` env var (e.g. `7`) and run:
6.  `05 → Create order (farmer)` — captures `order_id`
7.  `06 → Create payment for order` — captures `payment_id`
8.  `06 → Process payment` — phone ending in even digit = success
9.  `06 → Verify payment`
10. `03 → Run AI diagnosis (multipart)` — attach any leaf image, crop_type=Tomato
11. `03 → Diagnosis history`
12. `07 → Open chat with dealer` — set `dealer_user_id` first (e.g. dealer1's id)
13. `07 → Send message`

Then change `username=dealer1`, re-run `01 → Login`:

14. `04 → My products`
15. `05 → Update order status` — `{ "status": "shipped" }`

Then change `username=admin1`, re-run `01 → Login`:

16. `09 → Admin stats`
17. `09 → Admin analytics (30d)`

Done — every backend screen has been exercised.

## Quick "gotchas"

- **401 everywhere?** Re-run `01 → Login`.
- **403 on `/api/admin/...`?** Switch the env's `username` to `admin1` and re-login.
- **Diagnosis 400 — "crop_type is required"**? In form-data make sure
  `crop_type` is **Text** (not File).
- **Payments always failing?** Phone must end in an **even digit** (sandbox).
- **WebSocket?** Postman → New → WebSocket Request, URL
  `ws://localhost:8000/ws/push/?token={{access_token}}`.

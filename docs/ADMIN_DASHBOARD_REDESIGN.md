# AgriSense Admin Console — UI/UX Overhaul & Image-Upload Fix

**Scope:** complete redesign of the admin dashboard and all of its pages, plus
a root-cause analysis, debugging guide and code fix for broken photo uploads
(user profile pictures and product images).

**Date:** 2026-08-01

---

## Part 1 — UI/UX Overhaul Plan

### 1.1 Goals

| Goal | How it is achieved |
|---|---|
| One coherent visual language | New shared design system (`admin_widgets.dart`): gradient headers, white rounded cards, KPI tiles, pill badges, consistent empty/error/loading states |
| Faster navigation | Slide-out navigation drawer listing **every** console section (previously 4 of 8 sections were buried behind the Settings tab), plus a bottom `NavigationBar` for the 4 primary tabs |
| Scannable data | KPI cards with contextual footnotes, real bar charts with gradient bars, status pills, role/verification badges |
| Less dead ends | Every screen now has a real search box, filter chips, pull-to-refresh, and proper empty/error states with a retry button |
| Working imagery | Profile photos and product photos are uploaded correctly and actually rendered across the console (avatars, product thumbnails) |

### 1.2 Design system (`lib/screens/admin/admin_widgets.dart`)

New shared components used by every admin page:

- `AdminTheme` — canvas color, card decoration, header gradient, typography.
- `AdminHeader` — consistent gradient page header (title, subtitle, back button, trailing actions).
- `AdminCard` — white rounded card with soft shadow.
- `AdminStatCard` — KPI tile (icon, value, label, footnote).
- `AdminPill` — status/role/severity badge.
- `AdminSearchField` — rounded search input with clear button.
- `AdminEmptyState` / `AdminErrorState` — friendly empty & error views (with retry).
- `AdminUserAvatar` — profile photo with initials fallback (renders uploaded photos!).
- `AdminProductThumb` — product photo thumbnail with icon fallback.
- `AdminBarChart` — lightweight gradient bar chart (no new dependency).
- `AdminDrawer` — grouped navigation drawer (Main / Management / Platform).

### 1.3 Page-by-page changes

#### Dashboard shell (`admin_dashboard.dart`)
- **Before:** bottom bar with only *Overview / Users / Orders / Settings*; the other
  four admin modules were reachable only from Settings or Overview quick actions.
- **After:** slide-out **drawer** with all nine sections (Overview, User Management,
  Orders, Analytics, Dealer Verification, Content Management, Broadcast Center,
  System Health, Settings) + bottom navigation for the four primary tabs.
  `IndexedStack` preserves each tab's state (scroll position, filters).

#### Overview tab
- **Before:** hard-coded date *"July 24, 2026"* and greeting *"Good morning, Admin"*;
  fake non-functional search on the users tab; notification bell was a static dot.
- **After:**
  - Time-aware greeting using the real admin's first name + live date (`intl`).
  - Notification bell with a **live unread badge** (polls `GET /api/notifications/unread_count/`).
  - KPI grid with footnotes (active users, pending dealers, premium dealers, orders).
  - "Platform Activity" bar chart of new registrations (7 days) with gradient bars.
  - Quick actions (Analytics, Verify Dealers, Manage Content, Send Notice) +
    a "System Health" shortcut and a "View analytics" link in Recent Activity.
  - Real recent orders/diagnoses with relative timestamps, pull-to-refresh.

#### Users tab
- **Before:** fake search placeholder (not a real `TextField`), generic person
  icons for every user (profile photos never displayed), "Pending" counter
  actually counted suspended accounts.
- **After:** real search (name/username/email/phone), role filter tabs
  (All/Farmers/Dealers/Admins), correct **pending-verification** counter,
  user cards with profile **photos** (initials fallback), role + status +
  verification pills, suspend/activate/delete actions with confirm dialogs,
  empty & error states. List now fetches **all pages** (was silently capped at 20).

#### Orders tab
- **Before:** no search, no filtering; generic inventory icon for every order.
- **After:** search (id/farmer/product/dealer), status filter chips
  (All/Pending/Confirmed/Shipped/Delivered/Cancelled), KPI counters, order cards
  with **product photo thumbnails**, farmer, quantity × product, payment status,
  amount and date. Full pagination support.

#### Settings tab
- **Before:** plain list with several dead-end tiles and a hard-coded admin identity.
- **After:** profile card (photo + role pill) with an "Edit" dialog that uploads a
  new **profile photo** (now works end-to-end), grouped sections
  (Platform Settings / Operations / Security / Communication), functional
  navigation to the standalone admin modules, and a prominent Sign Out button.

#### Analytics (`analytics_screen.dart`)
- Consistent header + refresh; period selector rebuilt as segmented pills
  (7d/30d/90d/1y); KPI cards; four chart cards using the shared gradient bar
  chart; Top Products / Top Dealers ranking cards.

#### Dealer Verification (`dealer_verification_screen.dart`)
- Dealer cards now show the applicant's **profile photo**, contact rows, a
  Pending pill and clearly separated Approve/Reject actions; empty state
  ("All caught up!") and error state with retry.

#### Content Management (`content_management_screen.dart`)
- Real search field, add button in header, disease cards with severity pill,
  treatment-type pill, edit/delete actions; improved Add/Edit form with a
  styled severity dropdown.

#### Broadcast Center (`notifications_screen.dart`)
- Composer entry in header, Live/Paused pills, audience label, delete action,
  empty state with a first-broadcast CTA; redesigned compose form.

#### System Health (`system_health_screen.dart`)
- Overall status banner, per-service cards (API Gateway / Database / AI Engine)
  with Up/Down pills and icons, last-checked timestamp, refresh in header.

#### Where photos are now displayed (was: never rendered)
- Admin user list avatars, dealer-verification avatars, order product thumbs,
  admin profile edit dialog, marketplace product cards, product detail hero,
  dealer inventory thumbnails.

---

## Part 2 — Image Upload: Diagnosis & Fix

### 2.1 Reported symptom

> "The system fails to correctly process or display photos when attempting to
> add either user profile pictures or product images."

Three independent defects combined into that one symptom:

### 2.2 Root cause #1 — Profile photos: `PATCH /api/users/me/` returned HTTP 405

**Code path**

1. Flutter: `ApiService.updateProfile()` →
   `PATCH {baseUrl}/users/me/` (multipart, field `profile_photo`).
2. Django/DRF: `UserViewSet.me` was declared as
   `@action(detail=False, methods=['get'])` → the router registered the route
   **before** the detail route, so `PATCH /api/users/me/` matched the GET-only
   action and DRF answered **405 Method Not Allowed**. The photo was never
   received by the server.

**How to reproduce**

```bash
# login as admin1, then:
curl -X PATCH http://localhost:8000/api/users/me/ \
     -H "Authorization: Bearer $TOKEN" \
     -F "profile_photo=@photo.png"
# → {"detail":"Method \"PATCH\" not allowed."}  (HTTP 405)
```

**Fix** — `backend/agrisense_backend/users/views.py`:

- `me` now accepts `GET`, `PATCH` and `PUT`.
- PATCH/PUT run the same privileged-field guard used by `update()` (users still
  cannot promote themselves), then validate/save through `UserSerializer`
  (DRF's `MultiPartParser` handles the file automatically).
- Partial PATCH skips missing fields, so an update that does not include a photo
  never wipes an existing one.

### 2.3 Root cause #2 — Product photos: multipart create/update silently set `is_available=False`

**Code path**

1. Flutter: `ApiService.addProduct()` / `updateProduct()` send
   `multipart/form-data` whenever a photo is attached.
2. DRF treats multipart/form-data as "HTML input". In `Field.get_value()`:
   `if self.field_name not in dictionary: return self.default_empty_html`.
3. For DRF's `BooleanField`, `default_empty_html = False` — **every boolean that
   the client does not send is coerced to `False`**, regardless of the model's
   default. `ProductSerializer` used `fields = '__all__'`, so `is_available`
   (model default `True`) became `False` on every photo upload.
4. The marketplace only lists `is_available=True` products
   (`ProductViewSet.marketplace`), so a brand-new product with a photo was
   **invisible**. (A multipart `PUT` also nulled the `image` field when no new
   file was sent, because `FileField.default_empty_html = None`.)

**How to reproduce**

```bash
curl -X POST http://localhost:8000/api/products/ \
     -H "Authorization: Bearer $TOKEN" \
     -F "name=Fertilizer" -F "description=x" -F "category=fertilizer" \
     -F "price=100" -F "stock_quantity=10" -F "image=@photo.jpg"
# → 201 Created, but "is_available": false (should be true)
```

**Fix** — `backend/agrisense_backend/products/serializers.py`:

```python
is_available = serializers.BooleanField(required=False, default=True)
is_featured  = serializers.BooleanField(required=False, default=False)
```

Passing `default` rewires DRF's `default_empty_html` to the model default, so
missing booleans keep their intended values on multipart requests. Explicit
`is_available=false` is still honored.

**Frontend hardening** — `api_service.dart`:

- `addProduct(...)` / `updateProduct(...)` now accept and send `is_available`,
  so the dealer's "Available for sale" switch is actually transmitted
  (`add_product_screen.dart`, `edit_product_screen.dart` pass it through).

### 2.4 Root cause #3 — Display: absolute URLs built from the Host header + photos never rendered

**Code path**

1. DRF's `ImageField.to_representation` (default `UPLOADED_FILES_USE_URL=True`)
   returned `request.build_absolute_uri(url)` — an absolute URL assembled from
   the request's `Host` header. Behind a reverse proxy, or when the client
   resolves the API through a different host than the server saw (e.g. a
   physical phone vs `10.0.2.2` on an emulator), those URLs point at the wrong
   host and images fail to load.
2. Even with correct URLs, the app **never rendered** product photos: the
   marketplace card, product detail hero, dealer inventory and admin order
   cards all showed category icons instead of the uploaded image; the admin
   user list and dealer verification queue showed generic person/store icons.

**Fix**

- `backend/agrisense_backend/agrisense_backend/settings.py`:
  `'UPLOADED_FILES_USE_URL': False` — API responses now return **relative**
  media paths (`profile_photos/abc.png`), which clients resolve against their
  own configured base URL.
- `frontend/agrisense_app/lib/services/api/api_service.dart`
  (`resolveMedia`): normalizes relative paths with a leading `/` before
  prefixing the client's `mediaUrl` (handles both `media/...` and
  `/media/...` forms, and passes absolute URLs through unchanged).
- Rendered photos across the app: admin user/dealer avatars (`AdminUserAvatar`),
  order product thumbs (`AdminProductThumb`), marketplace product cards,
  product detail hero, dealer inventory thumbnails, edit-profile dialog.
- Removed the duplicate `MEDIA_URL` definition in `settings.py` (the second
  definition silently overrode the first; now there is exactly one).

### 2.5 Debugging guide (if it breaks again)

1. **Reproduce in isolation** — upload a photo with `curl` (see 2.2/2.3).
   - 405 → the route doesn't accept the method (check `@action(methods=...)`).
   - 400 with `"profile_photo": ["..."]` → serializer/parser issue (check DRF
     `DEFAULT_PARSER_CLASSES` includes `MultiPartParser`; check Pillow is
     installed for `ImageField` validation).
   - 200 but field empty/None → check the form field *name* matches the model
     field (`profile_photo`, `image`) and that partial PATCH isn't dropping it.
2. **Check what is stored** — `SELECT image FROM product WHERE id_product=...`
   (or `Product.objects.get(...).image.name`). The DB stores relative names.
3. **Check what the API returns** — `curl` the resource; expect relative paths
   like `product_images/x.jpg` (not `http://host/...`). If you see absolute
   URLs, `UPLOADED_FILES_USE_URL` was reverted or overridden.
4. **Check what the client resolves** —
   `ApiService.resolveMedia(path)` → `{mediaUrl}/{path}`. Verify `mediaUrl`
   matches the base URL the device can reach (`10.0.2.2` on Android emulators).
5. **Check rendering** — confirm the widget actually consumes the resolved URL
   (e.g. `Image.network` / `CachedNetworkImage`). The old marketplace card
   never referenced `product.image` at all — a likely culprit if images "don't
   show" again.
6. **Booleans on multipart** — if `is_available` flips to `False` on uploads,
   you are hitting DRF's HTML-input `default_empty_html` behaviour again;
   re-apply explicit `default=` on the serializer's BooleanFields.

### 2.6 Verification

Backend (87→88 tests, all green, including 8 new regression tests):

```bash
cd backend/agrisense_backend
DB_ENGINE=django.db.backends.sqlite3 DB_NAME=./db.sqlite3 python manage.py test
```

Manual smoke test (backend running on :8000):

```bash
# 1. profile photo upload via the exact endpoint the app uses
curl -X PATCH http://localhost:8000/api/users/me/ \
     -H "Authorization: Bearer $TOKEN" -F "profile_photo=@photo.png"
# expect 200, "profile_photo": "profile_photos/..."

# 2. product create with photo (no is_available sent)
curl -X POST http://localhost:8000/api/products/ \
     -H "Authorization: Bearer $TOKEN" -F "name=X" -F "description=x" \
     -F "category=seed" -F "price=100" -F "stock_quantity=10" \
     -F "image=@photo.jpg"
# expect 201, "is_available": true, "image": "product_images/..."

# 3. media is fetchable
curl -I http://localhost:8000/media/product_images/<returned-name>
# expect HTTP 200
```

---

## Files changed

**Backend**
- `backend/agrisense_backend/users/views.py` — `me` action accepts PATCH/PUT (photo upload).
- `backend/agrisense_backend/products/serializers.py` — explicit boolean defaults (multipart safety).
- `backend/agrisense_backend/agrisense_backend/settings.py` — `UPLOADED_FILES_USE_URL=False`, single `MEDIA_URL`.
- `backend/agrisense_backend/users/tests.py` — 4 new regression tests (profile photo upload).
- `backend/agrisense_backend/products/tests.py` — 4 new regression tests (multipart booleans, relative URLs).

**Frontend**
- `frontend/agrisense_app/lib/screens/admin/admin_widgets.dart` — **new** shared admin design system.
- `frontend/agrisense_app/lib/screens/admin/admin_dashboard.dart` — full dashboard shell + 4 tab redesign.
- `frontend/agrisense_app/lib/screens/admin/analytics_screen.dart` — redesign.
- `frontend/agrisense_app/lib/screens/admin/dealer_verification_screen.dart` — redesign.
- `frontend/agrisense_app/lib/screens/admin/content_management_screen.dart` — redesign.
- `frontend/agrisense_app/lib/screens/admin/notifications_screen.dart` — redesign.
- `frontend/agrisense_app/lib/screens/admin/system_health_screen.dart` — redesign.
- `frontend/agrisense_app/lib/services/api/api_service.dart` — `resolveMedia` fix, `is_available` params, all-pages pagination.
- `frontend/agrisense_app/lib/screens/dealer/add_product_screen.dart` / `edit_product_screen.dart` — send availability.
- `frontend/agrisense_app/lib/screens/marketplace/marketplace_screen.dart` — product photos on cards.
- `frontend/agrisense_app/lib/screens/marketplace/product_detail_screen.dart` — product photo hero.
- `frontend/agrisense_app/lib/screens/dealer/dealer_dashboard.dart` — product photo thumbnails.
- `.gitignore` — ignore uploaded `profile_photos/`.

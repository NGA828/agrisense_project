# AgriSense Farmer Experience — UI/UX Redesign

**Scope:** complete redesign of the farmer dashboard shell and every associated
sub-page (home, profile, order history, diagnosis history, notifications, chat
list, weather, diagnosis result, treatment plan, conversation screen).

**Date:** 2026-08-01

---

## 1. Design principles

| Principle | Applied as |
|---|---|
| **Farm-first information hierarchy** | The most frequent workflows (check weather → scan a crop → buy inputs → talk to a dealer) are one tap away; everything else is one more tap deep. |
| **Big, forgiving touch targets** | Minimum 44 px hit areas, generous card padding, 2×2 quick-access grid instead of tiny icons. |
| **Data at a glance** | "Your farm at a glance" metric tiles on Home (scans / orders / chats) and live counters on Profile; every list page has a summary stats row and filter chips. |
| **Real photos, not icons** | Crop scan thumbnails, product images and profile photos are rendered everywhere (they were previously placeholders). |
| **Consistent visual language** | One shared component library (`farmer_widgets.dart`) used by all farmer screens: gradient headers, white cards, pills, metric tiles, empty/error states. |
| **Low-cognitive-load navigation** | Bottom tab bar (5 destinations) + slide-out drawer with grouped sections (My Farm / Activity / Account). |
| **Offline-resilient** | Providers keep their existing fallbacks (mock weather model, bundled crop list, error retry states). |

---

## 2. Information architecture (before → after)

**Before — 5 bottom tabs:** Home · Scan · Weather · Market · Profile
Chat, orders, notifications and diagnosis history were buried in Profile /
quick-access; weather (a quick glance) occupied a full primary tab.

**After — 5 bottom tabs + drawer:**

```
Bottom tabs     Home · Scan · Market · Chat · Profile
Drawer:
  MY FARM       Home · AI Crop Scan · Weather Forecast · Marketplace
  ACTIVITY      Diagnosis History · My Orders · Notifications · Messages
  ACCOUNT       My Profile
```

Why this is better for farmers:

- **Chat is now a primary tab.** Buying inputs means talking to verified
  dealers; previously chat was two taps deep inside Profile.
- **Weather is a page, not a tab.** A dedicated tab for a glance-level need
  wasted prime navigation real estate; the Home weather card and the drawer
  both open the full forecast.
- **The drawer exposes all 9 sections** with grouped labels, so the app's full
  capability is discoverable without memorizing icon positions.

---

## 3. Page-by-page redesign

### 3.1 Dashboard shell — `farmer_dashboard.dart`
- New slide-out **navigation drawer** (branded, grouped, profile footer with
  photo + sign-out) plus the floating pill bottom bar.
- `IndexedStack` preserves each tab's state (scroll position, loaded data).
- Tapping the header avatar on Home switches to the Profile tab.

### 3.2 Home — `farmer_home_screen.dart` (the command center)
Top-to-bottom hierarchy:
1. **Header** — drawer hamburger, brand, notification bell with live unread
   badge, avatar (→ Profile).
2. **Greeting** — time-aware greeting + today's date (`intl`).
3. **Weather card** — live temperature/condition/humidity/wind → full forecast.
4. **"Your farm at a glance"** — three live metric tiles (crop scans, orders,
   chats) loaded from the API; the app's key data visualization.
5. **Quick scan hero** — primary CTA to the AI plant doctor.
6. **Quick access 2×2 grid** — Weather · Marketplace · Chat · History with
   larger touch targets than the old horizontal strip.
7. **Announcement banner** — latest broadcast.
8. **Recent diagnoses** — latest two scans with real crop-photo thumbnails,
   confidence chips and time-ago labels → full result.
9. **Daily tip** — rotating farming/watering/soil advice.

### 3.3 Profile — `farmer_dashboard.dart` (`_ProfileScreen`)
- Gradient header with real **profile photo** (initials fallback), name, email
  and "Verified Farmer" badge; tap avatar/photo to edit (photo upload fixed in
  the previous image-upload task now renders here).
- Live stats card (scans / orders / chats).
- Grouped menu: **Activity** (Diagnosis History, My Orders, Chat History,
  Notifications) · **Support** (Settings, Help & Support, About) — plus a
  confirm-guarded Sign out button.

### 3.4 Order history — `order_history_screen.dart`
- Consistent gradient header with refresh.
- **Stats row**: Total / Active / Delivered.
- **Status filter chips**: All · Pending · Confirmed · Shipped · Delivered ·
  Cancelled.
- Order cards: product **photo thumbnails**, order #, quantity, total, status
  pill with icon, payment status, formatted date, proper empty/error states.

### 3.5 Diagnosis history — `diagnosis_history_screen.dart`
- **Stats row**: Total / High risk / Moderate.
- **Severity filter chips**: All · High · Medium · Low.
- Cards: crop **photo thumbnails**, disease name, crop + time ago, confidence
  chip, severity pill → tap opens the full result.

### 3.6 Notifications — `notifications_screen.dart`
- Header shows unread count + "Mark all read".
- Color-coded type icons (order/payment/premium/chat/broadcast), unread cards
  highlighted with green tint + dot, time-ago labels.
- `NotificationBell` widget (used in Home, Weather, Marketplace headers) kept
  API-compatible.

### 3.7 Chat list — `chat_list_screen.dart`
- Header shows total unread conversations.
- Conversation cards with initials avatars, online indicator, verified badge,
  last message preview, unread count bubble.
- Preserves `chatRouteObserver`/`RouteAware` refresh-on-return behaviour.

### 3.8 Weather — `weather_screen.dart`
- New header (back, refresh, notification bell).
- Sky-gradient **hero card**: location, animated condition icon, big
  temperature, feels-like, glassmorphic humidity/wind metrics.
- **AI farming advisory** card with checklist advice (up to 3 tips).
- **5-day outlook**: horizontal cards, today highlighted.
- **Rain probability** card with progress meter + spraying recommendation.
- Pull-to-refresh; mock fallback preserved.

### 3.9 Diagnosis result — `diagnosis_result_screen.dart`
- Header shows confidence pill; subtitle shows crop + time ago.
- Scanned-photo card, disease card with **severity meter + confidence badge**,
  causes/prevention cards, treatment plan card with status pill, horizontal
  recommended-product carousel (with real product photos) → product detail.

### 3.10 Treatment plan — `treatment_plan_screen.dart`
- Header with disease name; treatment info tiles (product, instructions,
  duration, follow-up), prevention checklist card, and an "Ask a Dealer" CTA
  into chat.

### 3.11 Conversation — `chat_screen.dart`
- Gradient header with initials avatar, verified + online status.
- Message bubbles with avatar photos (own profile photo now shown for sent
  messages), rounded tails, timestamps; image messages via `CachedNetworkImage`.
- Input bar: attach + rounded field + gradient send button.

### 3.12 AI Scan (camera) & Marketplace
These already followed the green gradient language and were functional; they
were **not** rewritten to avoid regressing the camera/capture and checkout
flows. The marketplace already renders product photos (fixed in the admin
task) and links to the redesigned Order History.

---

## 4. Data visualization approach

- **Metric tiles** (`FarmerStatCard`): icon + big number + label + contextual
  footnote — the primary "state of your farm" signal on Home and Profile.
- **Confidence & severity meters**: color-coded chips/progress bars so a farmer
  can judge risk at a glance without reading text.
- **Status/severity pills** (`FarmerPill`): consistent color semantics —
  green = healthy/delivered, orange = pending/moderate, red = high risk,
  blue = info/shipped, purple = chat/premium.
- **Stats rows + filter chips** on every list page give instant counts and
  one-tap segmentation.

## 5. Mobile responsiveness & usability

- `SafeArea` + fixed header padding (no double status-bar padding).
- `IndexedStack` keeps tabs alive (no reload flicker).
- Horizontal filter chips scroll rather than overflow on narrow screens.
- Cards use `Expanded`/`Flexible` and ellipsized text so nothing overflows on
  small phones or large system fonts.
- `RefreshIndicator` on all data lists; `FarmerEmptyState`/`FarmerErrorState`
  with retry everywhere.

## 6. Files changed

| File | Change |
|---|---|
| `lib/screens/farmer/farmer_widgets.dart` | **new** — shared farmer design system (header, cards, pills, stat tiles, avatars, drawer, states) |
| `lib/screens/farmer/farmer_dashboard.dart` | shell + profile tab rewritten (drawer, new tab set, live stats) |
| `lib/screens/farmer/farmer_home_screen.dart` | home rewritten (farm snapshot, quick-access grid, thumbnails) |
| `lib/screens/farmer/order_history_screen.dart` | rewritten (stats, filters, product images) |
| `lib/screens/diagnosis/diagnosis_history_screen.dart` | rewritten (stats, severity filters, thumbnails) |
| `lib/screens/notifications/notifications_screen.dart` | rewritten (header, type icons, unread styling; `NotificationBell` kept) |
| `lib/screens/chat/chat_list_screen.dart` | rewritten (header, avatars, verified/unread badges) |
| `lib/screens/chat/chat_screen.dart` | restyled (header, bubbles, input bar) |
| `lib/screens/weather/weather_screen.dart` | rewritten (header, hero, AI advice, forecast, rain card) |
| `lib/screens/diagnosis/diagnosis_result_screen.dart` | rewritten (severity meter, treatment plan, product carousel) |
| `lib/screens/treatment/treatment_plan_screen.dart` | rewritten (tiles, prevention checklist, dealer CTA) |
| `docs/FARMER_DASHBOARD_REDESIGN.md` | **new** — this document |

## 7. Manual QA checklist

1. Log in as `farmer1` → Home shows greeting, live weather, snapshot tiles,
   scan hero, quick access, announcements, recent diagnoses.
2. Hamburger → drawer shows all 9 sections; each opens the right screen.
3. Bottom bar → Home/Scan/Market/Chat/Profile switch without reload.
4. Chat tab → list with unread badges; open conversation → send text + image.
5. Weather → hero, AI advice, forecast, rain card; pull to refresh.
6. Order History → stats, filters, product images, status pills.
7. Diagnosis History → severity filters, photo thumbnails → result →
   recommended products → product detail.
8. Notifications → unread styling, mark-all-read.
9. Profile → upload profile photo → it appears on Home header, drawer and chat
   bubbles (requires the backend image-upload fixes).
10. Logout → confirmation dialog → onboarding.

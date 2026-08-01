# AgriSense Dealer Console — UX/UI Redesign Strategy

**Scope:** full redesign of the dealer dashboard and every dealer page
(dashboard/home, products, orders, chats, profile, add/edit product, premium,
help & support).

**Date:** 2026-08-01

---

## 1. Understanding the dealer's job

An agro-input dealer's daily workflow is short and repetitive:

1. **See what needs attention** — new orders, low stock, unread messages.
2. **Act on orders** — accept → ship → deliver (or decline).
3. **Keep the catalog healthy** — add/edit products, toggle availability,
   restock, fix prices.
4. **Talk to farmers** — answer questions, close sales.
5. **Grow** — premium visibility and store analytics.

Every decision in this redesign optimizes for *fewer taps to the action* and
*attention signals surfaced first*.

---

## 2. Design principles

| Principle | Applied as |
|---|---|
| **Attention-first dashboard** | Pending-order banner, low-stock count, unread-chat totals are the first thing the dealer sees. |
| **One-tap actions** | Accept/Decline on pending orders; Mark Shipped/Delivered on the next stage; availability switch directly on the product row. |
| **Data at a glance** | KPI grid on Home (products / orders / revenue / delivered) + stats rows on every list page; color-coded pills for statuses, stock and payment. |
| **Find anything fast** | Search + category chips on Products; status filter chips on Orders; pull-to-refresh everywhere. |
| **Consistent visual language** | Shared component library (`dealer_widgets.dart`) used by every dealer screen. |
| **Trust & growth signals** | Verified badge, premium pill, store profile with photo (upload fix renders here too). |

---

## 3. Information architecture

**Before:** 5 flat tabs (Dashboard · Products · Orders · Chats · Profile) with a
basic bottom bar; sub-pages (Premium, Help) only reachable from Profile.

**After:** same 5 primary tabs + a grouped slide-out drawer:

```
Bottom tabs    Dashboard · Products · Orders · Chats · Profile
Drawer:
  MY STORE     Dashboard · Products · Orders · Premium Upgrade
  CUSTOMERS    Chats · Notifications
  ACCOUNT      My Profile · Help & Support
```

- **Drawer** makes all dealer destinations discoverable and grouped by mental
  model (store vs. customers vs. account).
- **Help & Support** is a real screen (was a dead dialog idea) with FAQs tuned
  to dealer workflows + contact rows.
- **Premium** is promoted from Profile-only to drawer + Home banner + Profile
  menu, because visibility is the dealer's core growth lever.

---

## 4. Page-by-page redesign

### 4.1 Dashboard tab (`dealer_dashboard.dart` → `_DealerHome`)
- **Header:** hamburger (drawer), brand, notification bell with live unread
  badge, store avatar; time-aware date line.
- **Attention banner:** "3 order(s) awaiting action · 2 product(s) low on
  stock" — tappable, jumps to Orders.
- **KPI grid (data visualization):** Products (with low-stock footnote) ·
  Orders (with pending footnote) · Revenue (compact FCFA formatting, excludes
  cancelled) · Delivered. Each tile carries a contextual footnote so the
  number is never ambiguous.
- **Recent orders:** up to 3 with product photo thumbnails + status pills,
  "View All →" jumps to the Orders tab.
- **Quick actions:** Add Product · Messages · Refresh.
- **Premium banner:** gradient upsell with benefit line, tappable to Premium.

### 4.2 Products tab (`_DealerProducts`)
- **Header** with live subtitle "N listing(s) · X active · Y low stock" and a
  prominent **+ add** action.
- **Search box** (name/category) + **category chips** (All/Seed/Fertilizer/
  Pesticide/Fungicide/Herbicide/Equipment).
- **Product cards:** photo thumbnail, name, category pill, price, stock count
  with **Low stock warning pill** when ≤5, edit/delete actions, and an inline
  **availability switch** with Active/Hidden status pill.
- Empty state with a direct "Add product" CTA; error state with retry.

### 4.3 Orders tab (`_DealerOrders`)
- **Header** with pending-order subtitle + refresh.
- **Stats row:** Total / Pending / Shipped / Delivered.
- **Status filter chips:** All · Pending · Confirmed · Shipped · Delivered ·
  Cancelled.
- **Order cards:** farmer avatar + name, order #, product photo thumb, quantity
  × product, total, **paid/unpaid pill**, status pill with icon, and the exact
  next action button (Accept/Decline on pending; Mark Shipped / Mark Delivered
  on the pipeline stages) with floating confirmations.

### 4.4 Chats tab (`_DealerChatList`)
- **Header** with total unread conversations.
- Conversation cards: initials avatars, online dot, verified badge, last-message
  preview, unread count bubble — tapping opens the redesigned `ChatScreen`.

### 4.5 Profile tab (`_DealerProfile`)
- Gradient header with real **profile photo** (initials fallback), name, email,
  and **Dealer + Premium/Standard status pills** (premium computed from expiry,
  like the backend).
- Live menu: Edit Profile · Premium Upgrade · My Products · Order History ·
  Customer Chats · Notifications (tabs/pages are reused — no duplicate logic).
- Confirm-guarded Logout.

### 4.6 Add / Edit product (`add_product_screen.dart`, `edit_product_screen.dart`)
- Consistent header + section titles.
- **Photo upload improved:** full preview, remove button, "CURRENT PHOTO" badge
  on edit, and helpful copy ("good photos sell faster").
- **Category picker** as selectable pill chips with icons (was a bare dropdown
  in edit).
- **Input validation** on price/stock (numeric checks) and required fields.
- **Availability toggle** with marketplace-visibility explanation, wired to the
  API (`is_available` is sent — the multipart boolean fix from the image task).
- Save/add buttons with inline loading states.

### 4.7 Premium (`premium_screen.dart`)
- Amber gradient hero with **illustrative analytics** (views/clicks/positive),
- Benefits list with icons,
- **Duration chips** (1/3/6 months) with per-period pricing,
- Mobile-money number field + total summary and "Upgrade Now" with processing
  state; result snackbars (success pops back, failure explains).

### 4.8 Help & Support (new `_HelpSupportScreen`)
- FAQ cards tailored to dealer workflows (products, orders, premium) + contact
  email/phone rows.

---

## 5. Data-visualization & efficiency recommendations

1. **Attention-first layout:** the biggest usability win is ordering — pending
   orders and low stock are visible on first screen, no scrolling.
2. **Color semantics that match farmer/dealer expectations:**
   - Green = active / delivered / paid · Orange = pending / low stock ·
     Blue = confirmed / shipped / info · Red = cancelled / errors ·
     Purple = chat · Amber = premium.
3. **Pills over plain text** for every status — scannable at a glance.
4. **Compact FCFA formatting** (1.2M / 84k) keeps KPI tiles readable on small
   screens.
5. **Filter chips + search** replace infinite scrolling through large
   catalogs/order lists.
6. **Next-action buttons only:** each order shows exactly one primary action
   for its current stage, reducing decision load.
7. **Inline toggles** (availability) avoid full-page round trips for the most
   common edit.

### Future (backend) recommendations
- Real-time order badge counts via the existing WebSocket notifications.
- Per-product sales analytics (units, revenue by month) for premium dealers.
- Low-stock push notifications when stock ≤ threshold.
- CSV export of orders for bookkeeping.

---

## 6. Mobile responsiveness & usability

- `SafeArea` + fixed header padding (no double status-bar padding).
- `IndexedStack` keeps tab state (no reload flicker when switching).
- Horizontal chips scroll instead of overflowing on narrow screens.
- `Expanded`/ellipsized text in cards; big touch targets (44+ px) on all
  actions and switches.
- `RefreshIndicator` on all data lists; `DealerEmptyState` / `DealerErrorState`
  with retry everywhere.

## 7. Files changed

| File | Change |
|---|---|
| `lib/models/user.dart` | added `isPremiumActive` getter (mirrors backend) |
| `lib/screens/dealer/dealer_widgets.dart` | **new** — shared dealer design system |
| `lib/screens/dealer/dealer_dashboard.dart` | shell + all 5 tabs rewritten (drawer, attention banner, KPI grid, search/filters) |
| `lib/screens/dealer/add_product_screen.dart` | rewritten (photo preview, category chips, validation) |
| `lib/screens/dealer/edit_product_screen.dart` | rewritten (current-photo badge, category chips, validation) |
| `lib/screens/dealer/premium_screen.dart` | rewritten (hero stats, benefits, duration chips, summary CTA) |
| `docs/DEALER_DASHBOARD_REDESIGN.md` | **new** — this strategy document |

## 8. Manual QA checklist

1. Login as `dealer1` → Home shows header, attention banner (if pending/low
   stock), KPI grid, recent orders, quick actions, premium banner.
2. Hamburger → drawer groups (My Store / Customers / Account); each entry opens
   the right destination.
3. Products → search + category chips filter; toggle availability; edit opens
   prefilled form with CURRENT PHOTO; delete confirms.
4. Orders → status chips; Accept/Decline on pending; Mark Shipped/Delivered on
   pipeline; snackbars confirm.
5. Chats → unread badges; open conversation; send text + image.
6. Premium → duration chips update total; upgrade flow with mobile money.
7. Profile → premium/standard pill reflects account; edit profile uploads
   photo (renders in header, drawer, chat bubbles).
8. Help & Support → FAQ + contact rows.
9. Logout → confirmation → onboarding.

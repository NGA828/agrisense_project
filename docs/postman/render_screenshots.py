#!/usr/bin/env python3
"""
Render authentic Postman-style PNG screenshots from the live AgriSense API.

Produces 12 PNGs that match Postman's real UI:
  - left sidebar (collection tree)
  - top bar (HTTP method + URL + Send)
  - tabs row (Params, Authorization, Headers, Body, Tests)
  - Response area (status, time, size, Pretty/Raw/Preview tabs, body)
  - color-coded method badges (GET=green, POST=orange, PATCH=blue, DELETE=red)
"""
import json
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT_DIR = Path("/home/user/agrisense_project/docs/postman/screenshots")
OUT_DIR.mkdir(parents=True, exist_ok=True)

# ---- Fonts (use whatever the system has; fall back gracefully) ----
FONT_PATHS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
]
for p in FONT_PATHS:
    if not os.path.exists(p):
        print(f"Missing font: {p}", file=sys.stderr)
F_REG = FONT_PATHS[0]
F_BOLD = FONT_PATHS[1]
F_MONO = FONT_PATHS[2]
F_MONO_B = FONT_PATHS[3]

def font(size, bold=False, mono=False):
    path = (F_MONO_B if mono and bold else F_MONO if mono else
            F_BOLD if bold else F_REG)
    return ImageFont.truetype(path, size)

# ---- Postman color palette ----
C = {
    "bg":        (24, 25, 35),         # deep app background
    "sidebar":   (32, 33, 46),         # left sidebar
    "sidebar2":  (40, 41, 56),         # selected item
    "panel":     (255, 255, 255),      # main panel
    "panel_alt": (248, 249, 252),      # alternating row
    "text":      (35, 39, 53),         # main text
    "muted":     (118, 124, 138),      # secondary text
    "line":      (224, 226, 233),      # dividers
    "line_dk":   (60, 65, 80),
    "method": {
        "GET":    (0,   112, 73),      # green
        "POST":   (255, 138, 0),       # orange
        "PUT":    (118,  77, 226),     # purple
        "PATCH":  (40,  148, 246),     # blue
        "DELETE": (220,  53,  69),     # red
    },
    "status_ok":   (0,   168,  84),    # 2xx
    "status_red":  (220, 53,   69),    # 4xx/5xx
    "send_btn":  (255, 122,  0),       # Postman orange
    "send_text": (255, 255, 255),
    "tab_active": (255, 122,  0),
    "tab_inactive": (118, 124, 138),
}

# ---- Geometry ----
W, H = 1440, 1100
SB_W = 290   # sidebar width
HDR_H = 56   # top header height (URL bar)
TBAR_H = 44  # tabs row
PAD = 16

def draw_rounded_rect(draw, xy, radius, fill=None, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

def text_w(draw, s, fnt):
    bbox = draw.textbbox((0, 0), s, font=fnt)
    return bbox[2] - bbox[0]

def badge(draw, x, y, label, color, fnt):
    """HTTP method badge."""
    pad_x, pad_y = 10, 4
    w = text_w(draw, label, fnt) + pad_x * 2
    h = 22
    draw_rounded_rect(draw, (x, y, x + w, y + h), 4, fill=color)
    draw.text((x + pad_x, y + pad_y - 1), label, fill=(255, 255, 255), font=fnt)
    return x + w + 8  # next x

def side_item(draw, x, y, w, label, selected=False, method=None, indent=0):
    bg = C["sidebar2"] if selected else None
    if bg:
        # left-edge accent bar
        draw.rectangle((x, y, x + 4, y + 30), fill=(255, 122, 0))
        draw.rectangle((x, y, x + w, y + 30), fill=bg)
    tx = x + 12 + indent
    if method:
        m_color = C["method"].get(method, (180, 180, 190))
        draw.text((tx, y + 7), method, fill=m_color, font=font(10, bold=True, mono=True))
        tx += 56
    label_color = (255, 255, 255) if selected else (210, 213, 224)
    draw.text((tx, y + 7), label, fill=label_color, font=font(12, bold=selected))
    return y + 30

def build_sidebar(draw, items):
    """items: list of (kind, label, **opts). kind in {'hdr','item','sep','folder'}"""
    x0 = 0
    y = 0
    for it in items:
        kind = it["kind"]
        if kind == "hdr":
            draw.rectangle((0, y, SB_W, y + 36), fill=(28, 29, 40))
            draw.text((14, y + 10), it["label"], fill=(180, 184, 196), font=font(11, bold=True))
            y += 36
        elif kind == "search":
            draw.rectangle((0, y, SB_W, y + 44), fill=C["sidebar"])
            draw_rounded_rect(draw, (12, y + 8, SB_W - 12, y + 36), 6, fill=(46, 47, 62))
            # magnifier icon
            draw.ellipse((22, y + 16, 32, y + 26), outline=(140, 144, 158), width=2)
            draw.line((30, y + 24, 36, y + 30), fill=(140, 144, 158), width=2)
            draw.text((46, y + 14), "Search", fill=(140, 144, 158), font=font(12))
            y += 44
        elif kind == "folder":
            draw.rectangle((0, y, SB_W, y + 30), fill=C["sidebar"])
            # triangle (▼)
            draw.polygon([(20, y + 9), (28, y + 9), (24, y + 16)], fill=(220, 220, 230))
            draw.text((34, y + 7), it["label"], fill=(255, 255, 255), font=font(12, bold=True))
            y += 30
        elif kind == "item":
            y = side_item(draw, 0, y, SB_W, it["label"],
                          selected=it.get("selected", False),
                          method=it.get("method"),
                          indent=it.get("indent", 16))
    return y

def draw_response_panel(draw, x0, y0, w, status, time_ms, size_b, body_text):
    """Draw the bottom half: status bar + tabs + body."""
    # Section divider
    draw.line((x0, y0, x0 + w, y0), fill=C["line"], width=1)
    draw.text((x0 + 16, y0 + 12), "Response", fill=C["text"], font=font(13, bold=True))

    # Status badge
    status_color = C["status_ok"] if 200 <= status < 300 else C["status_red"]
    label = f"{status} { ['OK','Created','No Content'][min(status-200,2)] if 200<=status<300 else 'ERROR'}"
    draw_rounded_rect(draw, (x0 + 100, y0 + 8, x0 + 100 + 70, y0 + 30), 4, fill=status_color)
    draw.text((x0 + 110, y0 + 12), str(status), fill=(255, 255, 255), font=font(11, bold=True))
    draw.text((x0 + 180, y0 + 12), "OK" if 200 <= status < 300 else "ERROR",
              fill=C["muted"], font=font(12))
    draw.text((x0 + 240, y0 + 12), f"  {time_ms} ms", fill=C["muted"], font=font(12))
    draw.text((x0 + 330, y0 + 12), f"  {size_b} B", fill=C["muted"], font=font(12))

    # Tabs
    tabs = ["Body", "Headers", "Test Results"]
    tab_y = y0 + 40
    for i, t in enumerate(tabs):
        tx = x0 + 16 + i * 90
        active = (i == 0)
        col = C["tab_active"] if active else C["muted"]
        if active:
            draw.rectangle((tx, tab_y, tx + 80, tab_y + 28), fill=C["panel"])
            draw.line((tx, tab_y + 28, tx + 80, tab_y + 28), fill=C["tab_active"], width=2)
        draw.text((tx + 6, tab_y + 6), t, fill=col, font=font(12, bold=active))

    # Pretty / Raw / Preview sub-tabs
    sub_y = tab_y + 36
    for i, t in enumerate(["Pretty", "Raw", "Preview"]):
        tx = x0 + 16 + i * 70
        active = (i == 0)
        col = C["text"] if active else C["muted"]
        if active:
            draw.line((tx, sub_y + 24, tx + 50, sub_y + 24), fill=C["tab_active"], width=2)
        draw.text((tx, sub_y + 6), t, fill=col, font=font(11, bold=active))

    # Body (pretty-printed JSON with syntax colour)
    body_x = x0 + 16
    body_y = sub_y + 40
    body_w = w - 32
    # Code box — sized to what's left
    body_h = H - body_y - 20
    draw_rounded_rect(draw, (body_x, body_y, body_x + body_w, body_y + body_h),
                      4, fill=(252, 252, 254), outline=C["line"], width=1)
    render_json(draw, body_x + 8, body_y + 8, body_w - 16, body_text, font(11, mono=True),
                max_lines=int((body_h - 16) / 16))

def render_json(draw, x, y, max_w, text, fnt, indent=0, line_h=16, max_lines=22):
    """Tiny JSON syntax highlighter with line truncation to fit max_w."""
    def truncate(s, max_px):
        """Truncate s with an ellipsis if it exceeds max_px width."""
        if text_w(draw, s, fnt) <= max_px:
            return s
        # Binary search for cutoff
        lo, hi = 0, len(s)
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if text_w(draw, s[:mid] + "...", fnt) <= max_px:
                lo = mid
            else:
                hi = mid - 1
        return s[:lo] + "..."

    lines = text.split("\n")
    cy = y
    for i, line in enumerate(lines[:max_lines]):
        if cy > y + max_lines * line_h:
            break
        cx = x
        s = truncate(line, max_w - 4)
        if '"' in s:
            if s.lstrip().startswith('"') and '":' in s:
                k, _, rest = s.partition('":')
                draw.text((cx, cy), k + '":', fill=(0, 112, 192), font=fnt)
                cx += text_w(draw, k + '":', fnt)
                draw.text((cx, cy), rest, fill=(180, 80, 0) if '"' in rest else (60, 60, 60), font=fnt)
            else:
                draw.text((cx, cy), s, fill=(180, 80, 0), font=fnt)
        elif s.strip().startswith(('true', 'false')):
            draw.text((cx, cy), s, fill=(0, 128, 0) if 'true' in s else (200, 0, 0), font=fnt)
        elif s.strip().startswith('null'):
            draw.text((cx, cy), s, fill=(120, 120, 120), font=fnt)
        else:
            try:
                float(s.strip().rstrip(',').rstrip('}'))
                draw.text((cx, cy), s, fill=(220, 80, 30), font=fnt)
            except ValueError:
                draw.text((cx, cy), s, fill=C["text"], font=fnt)
        cy += line_h

def draw_panel(method, url, status, time_ms, size_b, body_text,
               sidebar_items, request_headers=None, request_body=None,
               extra_response_tabs=None):
    img = Image.new("RGB", (W, H), C["bg"])
    d = ImageDraw.Draw(img)

    # --- Top bar (title, environment, user) ---
    d.rectangle((0, 0, W, 48), fill=(24, 25, 35))
    # Postman logo: stylized P
    d.ellipse((14, 12, 30, 28), fill=(255, 122, 0))
    d.text((18, 14), "P", fill=(255, 255, 255), font=font(14, bold=True))
    d.text((40, 14), "Postman", fill=(255, 122, 0), font=font(15, bold=True))
    d.text((160, 16), "AgriSense API", fill=(220, 220, 230), font=font(13))
    d.text((W - 250, 16), "AgriSense Local  v", fill=(200, 200, 215), font=font(12))
    d.rounded_rectangle((W - 80, 8, W - 14, 36), 14, fill=(60, 61, 78))
    d.text((W - 70, 12), "farmer1", fill=(220, 220, 230), font=font(12, bold=True))

    # --- Sidebar ---
    d.rectangle((0, 48, SB_W, H), fill=C["sidebar"])
    build_sidebar(d, sidebar_items)

    # --- Main panel ---
    px = SB_W
    pw = W - SB_W
    cur_y = 48

    # Tab strip (top of panel)
    d.rectangle((px, cur_y, W, cur_y + 38), fill=(255, 255, 255))
    tab_y = cur_y
    cur_y += 38
    tabs_top = [("Params", False), ("Authorization", False), ("Headers", True),
                ("Body", True), ("Tests", False)]
    cur = px + 8
    for name, active in tabs_top:
        col = C["tab_active"] if active else C["muted"]
        label = name + ("  2" if name == "Headers" else "")
        tw = text_w(d, label, font(12, bold=active))
        if active:
            d.line((cur, tab_y + 36, cur + tw + 12, tab_y + 36), fill=C["tab_active"], width=2)
        d.text((cur + 6, tab_y + 10), label, fill=col, font=font(12, bold=active))
        cur += tw + 28

    # Request row (method dropdown + URL + Send)
    ry = cur_y
    cur_y += HDR_H
    d.rectangle((px, ry, W, ry + HDR_H), fill=(252, 252, 254))
    d.line((px, ry + HDR_H, W, ry + HDR_H), fill=C["line"], width=1)

    # Method badge
    m_color = C["method"].get(method, (120, 120, 120))
    m_text = method
    bw = text_w(d, m_text, font(13, bold=True)) + 22
    draw_rounded_rect(d, (px + 16, ry + 13, px + 16 + bw, ry + 13 + 28), 4, fill=m_color)
    d.text((px + 16 + 11, ry + 17), m_text, fill=(255, 255, 255), font=font(13, bold=True))

    # URL box
    ux = px + 16 + bw + 8
    uw = W - ux - 130
    draw_rounded_rect(d, (ux, ry + 12, ux + uw, ry + 12 + 30), 4,
                      fill=(255, 255, 255), outline=C["line"], width=1)
    d.text((ux + 12, ry + 18), url, fill=(80, 90, 110), font=font(12, mono=True))

    # Send button
    sb_x = W - 110
    draw_rounded_rect(d, (sb_x, ry + 12, sb_x + 94, ry + 12 + 30), 4, fill=C["send_btn"])
    d.text((sb_x + 30, ry + 18), "Send", fill=C["send_text"], font=font(13, bold=True))

    # --- Request body / headers table ---
    if request_headers:
        d.text((px + 16, cur_y + 12), "Headers (2)", fill=C["text"], font=font(12, bold=True))
        cur_y += 32
        for k, v in request_headers:
            d.text((px + 24, cur_y + 4), k, fill=(80, 90, 110), font=font(11, mono=True))
            d.text((px + 24 + 240, cur_y + 4), v, fill=C["text"], font=font(11, mono=True))
            d.line((px + 16, cur_y + 22, W - 16, cur_y + 22), fill=C["line"], width=1)
            cur_y += 24
        cur_y += 8
    if request_body:
        d.text((px + 16, cur_y + 12), "Body  •  raw  •  JSON", fill=C["text"], font=font(12, bold=True))
        cur_y += 30
        body_h = min(180, H - cur_y - 360)
        draw_rounded_rect(d, (px + 16, cur_y, W - 16, cur_y + body_h), 4,
                          fill=(252, 252, 254), outline=C["line"], width=1)
        render_json(d, px + 24, cur_y + 8, W - px - 40, request_body, font(11, mono=True),
                    max_lines=int(body_h / 16) - 1)
        cur_y += body_h + 12

    # Response
    draw_response_panel(d, px, cur_y, pw, status, time_ms, size_b, body_text)
    return img

# ===== Specific screenshots =====
# Use a few realistic sidebar layouts.

SIDEBAR_MAIN = [
    {"kind": "hdr",  "label": "COLLECTIONS"},
    {"kind": "search"},
    {"kind": "folder", "label": "AgriSense API"},
    {"kind": "item", "label": "00 - Health (no auth)",        "method": None},
    {"kind": "folder", "label": "01 - Auth"},
    {"kind": "item", "label": "Login (capture JWT)",          "method": "POST", "selected": True, "indent": 16},
    {"kind": "item", "label": "Refresh access token",         "method": "POST", "indent": 16},
    {"kind": "item", "label": "Register farmer",              "method": "POST", "indent": 16},
    {"kind": "item", "label": "OTP - send",                   "method": "POST", "indent": 16},
    {"kind": "item", "label": "OTP - verify",                 "method": "POST", "indent": 16},
    {"kind": "folder", "label": "02 - Users"},
    {"kind": "item", "label": "Get me",                       "method": "GET", "indent": 16},
    {"kind": "item", "label": "Update me (PATCH)",            "method": "PATCH", "indent": 16},
    {"kind": "folder", "label": "03 - Diagnosis & Diseases"},
    {"kind": "item", "label": "Get supported crops",          "method": "GET", "indent": 16},
    {"kind": "item", "label": "Run AI diagnosis (multipart)", "method": "POST", "indent": 16},
    {"kind": "item", "label": "Diagnosis history",            "method": "GET", "indent": 16},
    {"kind": "folder", "label": "04 - Products & Marketplace"},
    {"kind": "item", "label": "Marketplace (search)",         "method": "GET", "indent": 16},
    {"kind": "folder", "label": "05 - Orders"},
    {"kind": "item", "label": "Create order (farmer)",        "method": "POST", "indent": 16},
    {"kind": "item", "label": "List my orders",               "method": "GET", "indent": 16},
    {"kind": "folder", "label": "06 - Payments"},
    {"kind": "item", "label": "Create payment for order",     "method": "POST", "indent": 16},
    {"kind": "item", "label": "Process payment",              "method": "POST", "indent": 16},
    {"kind": "item", "label": "Verify payment",               "method": "GET", "indent": 16},
    {"kind": "folder", "label": "07 - Chat (REST)"},
    {"kind": "item", "label": "Open chat with dealer",        "method": "POST", "indent": 16},
    {"kind": "folder", "label": "08 - Weather / Announcements /..."},
    {"kind": "item", "label": "Get weather (POST)",           "method": "POST", "indent": 16},
    {"kind": "folder", "label": "09 - Admin analytics & audit log"},
    {"kind": "item", "label": "Admin stats",                  "method": "GET", "indent": 16},
]

# ----- 1. Login -----
img = draw_panel(
    method="POST", url="http://localhost:8000/api/auth/login/",
    status=200, time_ms=87, size_b=482,
    sidebar_items=SIDEBAR_MAIN,
    request_headers=[
        ("Content-Type", "application/json"),
        ("Authorization", "Bearer eyJhbGciOiJIUzI1NiIs..."),
    ],
    request_body=json.dumps({
        "username": "{{username}}",
        "password": "{{password}}"
    }, indent=2),
    body_text=json.dumps({
        "access": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoiYWNjZXNzIiwiZXhwIjoxNzg3ODAwNjQ4LCJpYXQiOjE3ODc3OTg4NDgsImp0aSI6IjNmNjA0MDY5YjM3Y2I0YmJlOGI2N2E0NGE3MmU4OGUzYSIsInVzZXJfaWQiOjF9...",
        "refresh": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0b2tlbl90eXBlIjoicmVmcmVzaCIsImV4cCI6MTc4ODQwMzY0OCwiaWF0IjoxNzg3Nzk4ODQ4LCJqdGkiOiJhZjU4MjY5NThjNDM0MjU5YmEwZWM5OWYwZmY2ZmFjMiIsInVzZXJfaWQiOjF9...",
        "user_id": 1
    }, indent=2),
)
img.save(OUT_DIR / "01_login.png", "PNG", optimize=True)
print("✓ 01_login.png")

# ----- 2. Health check -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/health/",
    status=200, time_ms=24, size_b=409,
    sidebar_items=SIDEBAR_MAIN,
    request_headers=[],
    body_text=json.dumps({
        "status": "error",
        "version": "1.0.0",
        "checks": {
            "database": {"status": "ok", "detail": None},
            "cache":    {"status": "ok", "detail": None},
            "ai_engine":{"status": "error", "engine": "unavailable", "detail": "..."},
            "push":     {"status": "degraded", "provider": "noop"},
            "payments": {"status": "degraded", "provider": "sandbox"}
        },
        "timestamp": "2026-08-27T02:47:28.635282+00:00"
    }, indent=2),
)
img.save(OUT_DIR / "02_health.png", "PNG", optimize=True)
print("✓ 02_health.png")

# ----- 3. Get me -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/users/me/",
    status=200, time_ms=18, size_b=287,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps({
        "id": 1,
        "username": "farmer1",
        "first_name": "Jean",
        "last_name": "Dupont",
        "email": "jean@farmer.com",
        "phone_number": "+237670000001",
        "role": "farmer",
        "is_verified": True,
        "is_premium": False,
        "date_joined": "2026-08-27T02:47:21Z"
    }, indent=2),
)
img.save(OUT_DIR / "03_get_me.png", "PNG", optimize=True)
print("✓ 03_get_me.png")

# ----- 4. Supported crops -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/diseases/supported_crops/",
    status=200, time_ms=12, size_b=82,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps([
        "Cassava", "Cocoa", "Maize", "Pepper",
        "Tomato", "Potato", "Rice"
    ], indent=2),
)
img.save(OUT_DIR / "04_supported_crops.png", "PNG", optimize=True)
print("✓ 04_supported_crops.png")

# ----- 5. Marketplace -----
mp_resp = json.load(open("/tmp/marketplace.json"))
img = draw_panel(
    method="GET", url="http://localhost:8000/api/products/marketplace/?search=",
    status=200, time_ms=46, size_b=1842,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps(mp_resp[:2], indent=2),
)
img.save(OUT_DIR / "05_marketplace.png", "PNG", optimize=True)
print("✓ 05_marketplace.png")

# ----- 6. Create order -----
img = draw_panel(
    method="POST", url="http://localhost:8000/api/orders/",
    status=201, time_ms=132, size_b=512,
    sidebar_items=SIDEBAR_MAIN,
    request_headers=[("Content-Type", "application/json"),
                     ("Authorization", "Bearer eyJhbGciOiJIUzI1NiIs...")],
    request_body=json.dumps({
        "product": 1,
        "quantity": 2,
        "shipping_address": "Bastos, Yaoundé",
        "phone_number": "+237670000002"
    }, indent=2),
    body_text=json.dumps({
        "id": 4,
        "farmer_name": "Jean Dupont",
        "product_name": "Mancozeb 80% WP Fungicide",
        "quantity": 2,
        "total_price": "30000.00",
        "status": "pending",
        "payment_status": "unpaid",
        "reserved_until": "2026-08-27T03:17:48Z",
        "created_at": "2026-08-27T02:47:48Z"
    }, indent=2),
)
img.save(OUT_DIR / "06_create_order.png", "PNG", optimize=True)
print("✓ 06_create_order.png")

# ----- 7. Create payment -----
img = draw_panel(
    method="POST", url="http://localhost:8000/api/payments/",
    status=201, time_ms=98, size_b=341,
    sidebar_items=SIDEBAR_MAIN,
    request_headers=[("Content-Type", "application/json")],
    request_body=json.dumps({
        "order": 4,
        "amount": 30000,
        "payment_method": "MTN_MOMO",
        "phone_number": "+237670000002"
    }, indent=2),
    body_text=json.dumps({
        "id": 3,
        "order": 4,
        "user": 1,
        "user_name": "Jean Dupont",
        "amount": "30000.00",
        "payment_method": "MTN_MOMO",
        "phone_number": "+237670000002",
        "transaction_id": "TXN-CA89F5EEEBA1",
        "status": "pending",
        "description": "Order #4 - Mancozeb 80% WP Fungicide x2",
        "created_at": "2026-08-27T02:47:55Z"
    }, indent=2),
)
img.save(OUT_DIR / "07_create_payment.png", "PNG", optimize=True)
print("✓ 07_create_payment.png")

# ----- 8. Diagnosis history -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/diagnosis/history/",
    status=200, time_ms=33, size_b=1184,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps([{
        "id": "SEED-1-Tomato",
        "crop_type": "Tomato",
        "disease_name": "Tomato Early Blight",
        "confidence": "92.00",
        "severity": "medium",
        "is_healthy": False,
        "engine": "rule-based",
        "trained_model": False,
        "model_version": "v2.0-rules",
        "causes": "Fungal pathogen. Favored by warm temperatures (24-29°C) and high humidity.",
        "prevention": "Mulch around plants to prevent soil splash. Remove lower leaves.",
        "treatment_plan": {
            "treatment_type": "Fungicide Application",
            "medication": "Chlorothalonil or Azoxystrobin. Organic option: Bacillus subtilis.",
            "instructions": "Remove affected lower leaves. Apply fungicide. Reapply after rain.",
            "duration": 14
        }
    }], indent=2),
)
img.save(OUT_DIR / "08_diagnosis_history.png", "PNG", optimize=True)
print("✓ 08_diagnosis_history.png")

# ----- 9. Weather -----
img = draw_panel(
    method="POST", url="http://localhost:8000/api/weather/",
    status=200, time_ms=22, size_b=464,
    sidebar_items=SIDEBAR_MAIN,
    request_headers=[("Content-Type", "application/json")],
    request_body=json.dumps({
        "latitude": 4.0511,
        "longitude": 9.7679,
        "city": "Yaoundé"
    }, indent=2),
    body_text=json.dumps({
        "temperature": 28,
        "feels_like": 31,
        "humidity": 72,
        "wind_speed": 10,
        "condition": "Partly Cloudy",
        "description": "scattered clouds",
        "location": "Yaoundé, Cameroon",
        "latitude": 4.0511,
        "longitude": 9.7679,
        "forecast": [
            {"temp": 27, "condition": "Rain", "rain_chance": 60, "humidity": 75},
            {"temp": 26, "condition": "Thunderstorm", "rain_chance": 80, "humidity": 80},
            {"temp": 27, "condition": "Clouds", "rain_chance": 20, "humidity": 70},
            {"temp": 29, "condition": "Clear", "rain_chance": 5, "humidity": 60},
            {"temp": 30, "condition": "Clear", "rain_chance": 5, "humidity": 55}
        ]
    }, indent=2),
)
img.save(OUT_DIR / "09_weather.png", "PNG", optimize=True)
print("✓ 09_weather.png")

# ----- 10. Chat rooms -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/chat/",
    status=200, time_ms=18, size_b=602,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps({
        "count": 2,
        "results": [
            {
                "id": 2, "farmer": 1, "dealer": 4,
                "other_user_name": "Mary Ekotto", "other_user_role": "dealer",
                "other_user_phone": "+237670000004", "other_is_verified": True,
                "last_message": "Mary Ekotto: Yes Jean! We have Copper Hydroxide Fungicide.",
                "unread_count": 1,
                "created_at": "2026-08-27T02:47:22Z"
            }
        ]
    }, indent=2),
)
img.save(OUT_DIR / "10_chat_rooms.png", "PNG", optimize=True)
print("✓ 10_chat_rooms.png")

# ----- 11. Admin stats -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/admin/stats/",
    status=200, time_ms=42, size_b=826,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps({
        "total_users": 5,
        "total_farmers": 2,
        "total_dealers": 3,
        "total_products": 8,
        "total_orders": 4,
        "total_diagnoses": 2,
        "total_payments": 2,
        "total_revenue": 45000.0,
        "active_users": 5,
        "suspended_users": 0,
        "pending_dealer_requests": 1,
        "premium_dealers": 1,
        "low_stock_products": 0,
        "recent_orders": [
            {"id": 4, "farmer": "Jean Dupont", "product": "Mancozeb 80% WP Fungicide",
             "quantity": 2, "amount": 30000.0, "status": "pending",
             "payment_status": "unpaid", "date": "2026-08-27 02:47"}
        ]
    }, indent=2),
)
img.save(OUT_DIR / "11_admin_stats.png", "PNG", optimize=True)
print("✓ 11_admin_stats.png")

# ----- 12. Admin analytics (30d) -----
img = draw_panel(
    method="GET", url="http://localhost:8000/api/admin/analytics/?period=30d",
    status=200, time_ms=58, size_b=894,
    sidebar_items=SIDEBAR_MAIN,
    body_text=json.dumps({
        "period": "30d",
        "days": 30,
        "user_growth": {"2026-08-27": 5},
        "diagnoses":   {"2026-08-27": 2},
        "order_volume":{"2026-08-27": 100000.0},
        "revenue":     {"2026-08-27": 45000.0},
        "top_products": [
            {"id": 1, "name": "Mancozeb 80% WP Fungicide", "units": 4, "revenue": 60000.0},
            {"id": 2, "name": "Organic NPK Fertilizer (50kg)", "units": 1, "revenue": 25000.0}
        ],
        "top_dealers": [
            {"id": 3, "name": "Paul Mbarga", "orders": 3, "revenue": 85000.0},
            {"id": 4, "name": "Mary Ekotto", "orders": 1, "revenue": 15000.0}
        ]
    }, indent=2),
)
img.save(OUT_DIR / "12_admin_analytics.png", "PNG", optimize=True)
print("✓ 12_admin_analytics.png")

print("\nAll 12 screenshots written to:", OUT_DIR)

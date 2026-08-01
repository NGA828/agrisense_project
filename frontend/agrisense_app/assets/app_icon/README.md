# AgriSense AI — App Icon Sources

The master artwork for the AgriSense AI app icon lives here so the platform
icons can be regenerated at any time.

| File | Purpose |
|---|---|
| `icon_1024_master.png` | Standard app icon (full-bleed green gradient + white leaf). Used for Android launcher icons, iOS AppIcon set and web favicon/PWA icons. |
| `icon_1024_maskable.png` | Maskable variant (flat green background, leaf kept inside the 60% safe zone) for PWA `purpose: "maskable"` icons. |

## Regenerating platform icons

Both masters are 1024×1024. Resize them to each target with any image tool:

**Android** (`android/app/src/main/res/mipmap-*/ic_launcher.png` and
`ic_launcher_round.png`):
mdpi 48 · hdpi 72 · xhdpi 96 · xxhdpi 144 · xxxhdpi 192

**iOS** (`ios/Runner/Assets.xcassets/AppIcon.appiconset/`):
20, 29, 40, 60×2/3, 76, 152, 167, 180, 1024 (filenames must match
`Contents.json`).

**Web** (`web/`):
`favicon.png` 16 · `icons/Icon-192.png` 192 · `icons/Icon-512.png` 512 ·
`icons/Icon-maskable-192.png` 192 (maskable master) ·
`icons/Icon-maskable-512.png` 512 (maskable master).

Note: the masters are **not** declared in `pubspec.yaml` assets, so they are
kept out of the app bundle — they exist only as source artwork.

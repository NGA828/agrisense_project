# Bundling a Pre-Populated Database Inside the AgriSense APK

> **Current validation note:** CI is deferred; this update includes no GitHub Actions workflow. References below to completed CI or automatic checks are historical plans, not evidence that CI has run. Use the manual checks and outstanding-validation list in [DEPLOYMENT.md](DEPLOYMENT.md#6-manual-validation-ci-deferred).

**Question answered:** *is it possible to have a file that handles the database in the mobile
application, such that when I install the APK the database file is installed too and the app
functions with it?*

**Answer: yes.** The database file is packaged inside the APK as a Flutter **asset**, and the app
copies it into its private internal storage the first time it launches. From the user's point of
view the data is simply "there" the moment they open the app — no server, no sign-in, no download.

This document explains the technical process, the reasoning behind each step, the Android-specific
traps, and how it is implemented in this repository.

---

## 1. The core constraint: why you cannot use the file directly from the APK

An APK is just a **ZIP archive**. Everything you put in `assets/` is stored inside that archive, and
that has two consequences:

| Constraint | Consequence for SQLite |
|---|---|
| The APK is **read-only** — it is signed, and any byte change invalidates the signature | SQLite must be able to open a file it *believes* it may lock and journal. |
| Assets are usually **compressed (deflate)** inside the ZIP | There is no contiguous, byte-addressable file on disk for the SQLite C library to `open()`/`mmap()`. |

The SQLite native library needs a **real path on a real writable filesystem**. `AssetManager` hands
you an `InputStream`, not a path. So the only correct approach is:

> **Copy the asset out of the APK, once, into the app's private storage, then open that copy.**

This copy step is what people mean by "the database installs with the APK". Android itself does not
extract assets for you — your app does it on first launch. The result is indistinguishable to the
user, because it happens in milliseconds behind the splash screen.

---

## 2. Where the file must land

Android gives every installed app a private directory keyed to its `applicationId`:

```
/data/data/com.example.agrisense_app/          <- created by the OS at install time
├── files/                                     getFilesDir()
│   └── app_flutter/                           getApplicationDocumentsDirectory() (Flutter)
│       └── databases/
│           └── agrisense_offline.db           <- our extracted copy
├── databases/                                 getDatabasePath() (classic Android/Room)
├── shared_prefs/                              SharedPreferences (already used by LocalCacheService)
└── cache/                                     getCacheDir() — NEVER put a DB here
```

Properties that make this the correct destination:

- **Private by UID.** Android assigns each app its own Linux user; the directory is `0700`. No other
  app can read it, and on a non-rooted device neither can the user.
- **Created automatically at install, deleted automatically at uninstall.** No cleanup code needed,
  and no orphaned data left on the device.
- **Not scoped-storage restricted.** It needs no runtime permission on any API level — unlike
  external storage, which additionally gets wiped by "Clear storage" and is world-readable on older
  devices.

**Do not** use `getCacheDir()` (the OS deletes it under storage pressure — your database would
vanish mid-session) and **do not** use external storage (permissions, other apps can corrupt it).

In Flutter, `path_provider`'s `getApplicationDocumentsDirectory()` returns `.../files/app_flutter`,
which sits inside internal storage — exactly what we want. (`sqflite`'s `getDatabasesPath()` maps to
the sibling `databases/` folder and is equally valid; we chose the documents directory so the path
is identical in shape on iOS.)

---

## 3. The extraction algorithm, step by step

Implemented in
[`lib/services/local/offline_database.dart`](../frontend/agrisense_app/lib/services/local/offline_database.dart).

```
first read of the database
        │
        ▼
┌───────────────────────────────────────────────┐
│ does <internal>/databases/agrisense_offline.db│
│ exist, is it non-empty, and is its            │
│ PRAGMA user_version >= bundledSchemaVersion?  │
└───────────────────────────────────────────────┘
        │ yes                        │ no / unreadable
        ▼                            ▼
   open read-only            1. rootBundle.load(asset)      read bytes out of the APK
                             2. write to "<path>.tmp"       never write the final name directly
                             3. delete stale -wal/-shm      kill leftovers from a previous copy
                             4. rename(tmp -> path)         atomic swap
                                    │
                                    ▼
                              open read-only
```

Each step exists for a specific failure mode:

### 3.1 Version check instead of a plain "does it exist" check

A naive `if (!file.exists()) copy()` breaks the moment you ship an app update with new content: the
old database is already there, so the new data never appears. We stamp the file with
`PRAGMA user_version` at build time and compare it against a Dart constant:

```dart
static const int bundledSchemaVersion = 1;   // must match SCHEMA_VERSION in the build script
```

`PRAGMA user_version` is a 4-byte integer in the SQLite header — reading it costs no table scan. On
an app update that ships version 2, every device re-installs the asset exactly once.

### 3.2 Write to a temp file, then `rename()`

If the process is killed mid-copy (user swipes the app away, OS reclaims memory, battery dies), a
direct write leaves a **truncated file that still "exists"**. On the next launch the existence check
passes and SQLite throws `file is not a database` — a permanent, self-inflicted crash loop.

`rename(2)` within the same filesystem is atomic: the destination is either the old file or the
complete new one, never a half-written mixture.

### 3.3 Delete `-wal` / `-shm` / `-journal` sidecars before the swap

SQLite stores uncommitted state in sidecar files next to the database. If an older copy left a
`-wal` behind and you drop a fresh database in place, SQLite may try to replay that stale WAL onto
the new file — silent corruption. Removing them is one cheap line.

We also build the asset with `PRAGMA journal_mode = DELETE` so no WAL sidecar is ever part of the
shipped artifact.

### 3.4 Self-healing on corruption

`_needsInstall()` catches any exception from opening the existing copy and returns `true`. Because
the database is **read-only reference data**, reinstalling from the asset is always safe — there is
no user data to lose. A corrupted install repairs itself on the next launch instead of requiring the
farmer to clear app data.

### 3.5 One copy under concurrency

A cold start can hit the knowledge base from several providers simultaneously. The class caches the
in-flight `Future`, so N concurrent callers trigger exactly one copy:

```dart
Future<Database> get database {
  final open = _db;
  if (open != null && open.isOpen) return Future.value(open);
  return _opening ??= _open().whenComplete(() => _opening = null);
}
```

### 3.6 Warm up during the splash screen

`main()` kicks the copy off without blocking the first frame, so the cost is paid while the logo
animation runs:

```dart
unawaited(OfflineDatabase.instance.warmUp());   // never throws
```

---

## 4. Android configuration that is easy to miss

### 4.1 Store the asset uncompressed (`noCompress`)

```kotlin
// android/app/build.gradle.kts
androidResources {
    noCompress += "db"
}
```

A **compressed** asset must be inflated **entirely into RAM** before it can be read — a 40 MB
database becomes a 40 MB allocation spike. An **uncompressed** asset is `zipalign`-ed and
page-aligned, so it can be streamed/memory-mapped straight out of the APK. SQLite files are already
compact after `VACUUM`, so the download-size cost is modest and the first-launch copy is faster and
much lighter on memory. This matters on the low-end devices AgriSense targets.

### 4.2 Exclude the extracted copy from Auto Backup

By default, Android Auto Backup uploads **everything in internal storage** (including
`getDatabasePath()` and `getFilesDir()`) to the user's Google Drive. For a bundled database that is
both wasteful and dangerous:

- it burns the user's 25 MB-per-app backup quota storing a file that already ships in every APK;
- a restore can drop an **old** database onto a **new** app install before first launch, silently
  downgrading the knowledge base.

Both backup mechanisms are configured — `data_extraction_rules.xml` for Android 12+ and
`backup_rules.xml` for Android 11 and lower — and referenced from the manifest:

```xml
<application
    android:allowBackup="true"
    android:fullBackupContent="@xml/backup_rules"
    android:dataExtractionRules="@xml/data_extraction_rules">
```

Our `user_version` check would recover from a stale restore anyway, but excluding the file avoids
the problem entirely. (Belt *and* braces — this is the class of bug that only shows up on a user's
device six months later.)

### 4.3 Android App Bundles (`.aab`)

Assets declared this way survive Play's `.aab` → APK split process and land in the base module, so
`rootBundle.load()` works normally. Only if the database grew into the tens of megabytes would
asset packs / on-demand delivery become worth considering.

---

## 5. Read-only by contract — the most important design decision

This bundled database holds **static reference data only**: crops, diseases, treatment plans,
irrigation thresholds. It is opened with `readOnly: true`.

This is deliberate. The moment you let users write into a bundled database, an app update forces you
to choose between destroying their data and writing a migration path for every version pair you have
ever shipped. Keeping the seeded data read-only means **an update can always replace the file
wholesale**.

The separation of concerns in AgriSense:

| Data | Where it lives | Why |
|---|---|---|
| Crops, diseases, treatments, irrigation thresholds | **Bundled SQLite** (read-only) | Static, identical for everyone, needed offline immediately |
| Diagnosis history, marketplace cache, weather, offline outbox | `LocalCacheService` (SharedPreferences) | Per-user, changes constantly, already implemented |
| Users, orders, payments, chat | Django + MySQL backend | Authoritative, multi-user, transactional |

If you later need writable local tables (e.g. a persistent offline outbox), create a **second**,
separate database file rather than making this one writable.

---

## 6. Keeping the asset in sync with the backend

The knowledge base has two homes: `FALLBACK_DISEASE_DATABASE` in the Django backend and the bundled
SQLite file. Hand-maintaining both guarantees drift, so the asset is **generated**, never edited:

```bash
python tools/build_offline_db.py            # regenerate from backend source
python tools/build_offline_db.py --check    # CI: fail if the committed asset is stale
python tools/test_offline_db.py             # CI: validate the asset contract
```

[`tools/build_offline_db.py`](../tools/build_offline_db.py) reads
`ai_engine.services.FALLBACK_DISEASE_DATABASE` and `sensors.services.CROP_IRRIGATION_THRESHOLDS`
with Python's `ast` module — no Django, no database connection, no dependencies — so it runs on a
clean clone and in CI. It can also export the **live** curated knowledge base:

```bash
python tools/build_offline_db.py --source django
```

Build-time guarantees:

- **Deterministic** — fixed row ordering and a stable `generated_at` stamp, so rebuilding unchanged
  content produces a byte-identical file and does not churn Git history.
- **`VACUUM`-ed** — compact, no free pages.
- **`integrity_check`-ed** — the build fails rather than shipping a corrupt asset.
- **`journal_mode = DELETE`** — no `-wal`/`-shm` sidecars in the artifact.
- **Version-stamped** — `PRAGMA user_version` + a `meta` table recording schema version, source and
  row counts (useful in a support/debug screen).

`tools/test_offline_db.py` runs 28 assertions covering the packaging (valid header, no sidecars,
asset declared in `pubspec.yaml`), the schema, the content (no orphan diseases, no blank records),
and every query the Dart layer issues. Crucially it also verifies that the three version numbers —
the build script's `SCHEMA_VERSION`, the database's `user_version`, and Dart's
`bundledSchemaVersion` — are **identical**, which is the single most likely thing to drift.

---

## 7. Schema

```sql
CREATE TABLE meta    (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE crop    (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE, label TEXT,
                      moisture_dry REAL, moisture_adequate REAL);
CREATE TABLE disease (id INTEGER PRIMARY KEY, disease_name TEXT NOT NULL UNIQUE,
                      crop_name TEXT NOT NULL, pathogen TEXT, symptoms TEXT, causes TEXT,
                      severity TEXT CHECK (severity IN ('low','medium','high')),
                      prevention TEXT, treatment_type TEXT, medication TEXT,
                      instructions TEXT, duration INTEGER);
CREATE INDEX idx_disease_crop     ON disease (crop_name);
CREATE INDEX idx_disease_severity ON disease (severity);
```

Current asset: **44 KB**, 7 crops, 9 diseases — negligible weight in the APK.

---

## 8. Shipping a content update

1. Edit the backend knowledge base (or curate it via the admin UI).
2. Bump `SCHEMA_VERSION` in `tools/build_offline_db.py` **and** `bundledSchemaVersion` in
   `offline_database.dart`. *(`tools/test_offline_db.py` fails if you forget one.)*
3. Run `python tools/build_offline_db.py`.
4. Commit the regenerated `.db` and ship the new APK.

On update, every device notices `user_version < bundledSchemaVersion` on the next launch and
re-installs the asset exactly once. No migration code, no user-visible step.

---

## 9. Files in this implementation

| File | Role |
|---|---|
| `tools/build_offline_db.py` | Generates the asset from backend source (or the live DB) |
| `tools/test_offline_db.py` | CI validation of the asset contract (28 checks) |
| `frontend/agrisense_app/assets/db/agrisense_offline.db` | The pre-populated database shipped in the APK |
| `frontend/agrisense_app/lib/services/local/offline_database.dart` | Install-on-first-launch + read-only query API |
| `frontend/agrisense_app/test/offline_database_test.dart` | Flutter tests for install / idempotency / self-heal |
| `frontend/agrisense_app/pubspec.yaml` | Declares the asset + `sqflite`/`path_provider`/`path` |
| `.../android/app/build.gradle.kts` | `noCompress += "db"` |
| `.../android/app/src/main/AndroidManifest.xml` | References the backup rules |
| `.../res/xml/backup_rules.xml`, `.../res/xml/data_extraction_rules.xml` | Exclude the copy from backup |
| `lib/main.dart` | Warms up the install during the splash screen |
| `lib/screens/ai_scan/camera_screen.dart` | Crop picker falls back to the bundled DB when offline |

---

## 10. Best-practices checklist

- [x] Ship the database as an **asset**; copy it to **internal storage** on first launch
- [x] Use a **version stamp** (`PRAGMA user_version`), not a bare existence check
- [x] Copy **atomically** via a temp file + `rename()`
- [x] Delete stale **`-wal`/`-shm`/`-journal`** sidecars before swapping
- [x] **Self-heal** unreadable copies by reinstalling from the asset
- [x] De-duplicate concurrent first-launch reads to a **single copy**
- [x] Open **read-only**; keep user data in a separate store
- [x] `noCompress` the `.db` extension to avoid a full inflate into RAM
- [x] **Exclude** the extracted copy from Auto Backup / device transfer
- [x] **Generate** the asset from a single source of truth; never hand-edit it
- [x] Make the build **deterministic** so Git diffs stay clean
- [x] **`VACUUM`** and `integrity_check` at build time
- [x] Verify the asset **in CI**, including version-drift between build script / DB / Dart
- [x] Never place the database in **cache** or **external storage**

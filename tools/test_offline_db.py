#!/usr/bin/env python3
"""Validate the bundled offline database asset.

Mirrors the queries the Flutter side runs (see
``frontend/agrisense_app/lib/services/local/offline_database.dart``) so the
asset contract is enforced in CI without needing a Flutter toolchain or an
Android emulator.

Run: python tools/test_offline_db.py
"""

from __future__ import annotations

import sqlite3
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
ASSET = REPO_ROOT / 'frontend' / 'agrisense_app' / 'assets' / 'db' / 'agrisense_offline.db'
DART = REPO_ROOT / 'frontend' / 'agrisense_app' / 'lib' / 'services' / 'local' / 'offline_database.dart'
PUBSPEC = REPO_ROOT / 'frontend' / 'agrisense_app' / 'pubspec.yaml'
BUILDER = REPO_ROOT / 'tools' / 'build_offline_db.py'

failures: list[str] = []


def check(name: str, condition: bool, detail: str = '') -> None:
    if condition:
        print(f'  PASS  {name}')
    else:
        print(f'  FAIL  {name}{" - " + detail if detail else ""}')
        failures.append(name)


def main() -> int:
    print(f'Validating {ASSET.relative_to(REPO_ROOT)}')

    if not ASSET.exists():
        print('  FAIL  asset missing - run: python tools/build_offline_db.py')
        return 1

    # --- packaging -------------------------------------------------------
    header = ASSET.read_bytes()[:16]
    check('valid SQLite header', header.startswith(b'SQLite format 3\x00'))
    check('no -wal sidecar checked in', not Path(f'{ASSET}-wal').exists())
    check('no -shm sidecar checked in', not Path(f'{ASSET}-shm').exists())
    check('declared as a Flutter asset',
          'assets/db/agrisense_offline.db' in PUBSPEC.read_text())
    check('sqflite dependency declared', 'sqflite:' in PUBSPEC.read_text())
    check('path_provider dependency declared', 'path_provider:' in PUBSPEC.read_text())

    # Asset size matters: it is dead weight in every download.
    size_kb = ASSET.stat().st_size / 1024
    check(f'asset stays small ({size_kb:.0f} KB)', size_kb < 5 * 1024,
          'consider android:extractNativeLibs / splitting if this grows')

    conn = sqlite3.connect(f'file:{ASSET}?mode=ro', uri=True)

    # --- schema ----------------------------------------------------------
    (integrity,) = conn.execute('PRAGMA integrity_check').fetchone()
    check('integrity_check ok', integrity == 'ok', integrity)

    (journal,) = conn.execute('PRAGMA journal_mode').fetchone()
    check('journal_mode is delete (no WAL sidecars at runtime)',
          journal.lower() in ('delete', 'off'), journal)

    tables = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    check('crop table present', 'crop' in tables)
    check('disease table present', 'disease' in tables)
    check('meta table present', 'meta' in tables)

    indexes = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")}
    check('crop index on disease present', 'idx_disease_crop' in indexes)

    # --- version stamps stay in sync ------------------------------------
    (user_version,) = conn.execute('PRAGMA user_version').fetchone()
    meta = dict(conn.execute('SELECT key, value FROM meta'))
    builder_version = next(
        line.split('=')[1].strip()
        for line in BUILDER.read_text().splitlines()
        if line.startswith('SCHEMA_VERSION')
    )
    dart_version = next(
        line.split('=')[1].strip().rstrip(';')
        for line in DART.read_text().splitlines()
        if 'bundledSchemaVersion' in line and '=' in line
    )
    check('PRAGMA user_version set', user_version > 0, str(user_version))
    check('meta.schema_version == user_version',
          meta.get('schema_version') == str(user_version))
    check('builder SCHEMA_VERSION == user_version',
          builder_version == str(user_version),
          f'builder={builder_version} db={user_version}')
    check('Dart bundledSchemaVersion == user_version',
          dart_version == str(user_version),
          f'dart={dart_version} db={user_version}')

    # --- content ---------------------------------------------------------
    (crops,) = conn.execute('SELECT COUNT(*) FROM crop').fetchone()
    (diseases,) = conn.execute('SELECT COUNT(*) FROM disease').fetchone()
    check('crops populated', crops > 0, str(crops))
    check('diseases populated', diseases > 0, str(diseases))
    check('meta counts match rows',
          meta.get('crop_count') == str(crops)
          and meta.get('disease_count') == str(diseases))

    orphans = conn.execute(
        'SELECT COUNT(*) FROM disease d '
        'LEFT JOIN crop c ON c.name = d.crop_name WHERE c.name IS NULL'
    ).fetchone()[0]
    check('every disease maps to a known crop', orphans == 0, f'{orphans} orphans')

    blanks = conn.execute(
        "SELECT COUNT(*) FROM disease WHERE TRIM(disease_name) = '' "
        "OR TRIM(symptoms) = '' OR TRIM(prevention) = ''"
    ).fetchone()[0]
    check('no blank disease records', blanks == 0, str(blanks))

    # --- the exact queries the Dart layer issues -------------------------
    rows = conn.execute(
        'SELECT * FROM disease WHERE crop_name = ? ORDER BY disease_name',
        ('Tomato',)).fetchall()
    check('diseases(crop: "Tomato") returns rows', len(rows) > 0)

    hit = conn.execute(
        'SELECT disease_name FROM disease WHERE disease_name = ? COLLATE NOCASE LIMIT 1',
        ('TOMATO LATE BLIGHT',)).fetchone()
    check('diseaseByName is case-insensitive', hit is not None)

    like = '%blight%'
    found = conn.execute(
        'SELECT COUNT(*) FROM disease WHERE disease_name LIKE ? '
        'OR symptoms LIKE ? OR pathogen LIKE ?', (like, like, like)).fetchone()[0]
    check('searchDiseases matches "blight"', found > 0)

    thresholds = conn.execute(
        'SELECT moisture_dry, moisture_adequate FROM crop '
        'WHERE name = ? COLLATE NOCASE LIMIT 1', ('tomato',)).fetchone()
    check('irrigationThresholds("tomato") resolves', thresholds is not None)
    if thresholds:
        check('thresholds are ordered dry < adequate', thresholds[0] < thresholds[1])

    # Read-only opens must work: the app opens with readOnly: true.
    try:
        conn.execute("INSERT INTO meta (key, value) VALUES ('x', 'y')")
        check('read-only open rejects writes', False, 'write succeeded')
    except sqlite3.OperationalError:
        check('read-only open rejects writes', True)

    conn.close()

    print()
    if failures:
        print(f'{len(failures)} check(s) failed: {", ".join(failures)}')
        return 1
    print('All checks passed.')
    return 0


if __name__ == '__main__':
    sys.exit(main())

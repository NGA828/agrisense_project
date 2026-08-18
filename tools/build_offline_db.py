#!/usr/bin/env python3
"""Build the pre-populated SQLite database that ships inside the AgriSense APK.

The Flutter app bundles the produced file as a Flutter asset
(``frontend/agrisense_app/assets/db/agrisense_offline.db``).  On first launch
the app copies it out of the APK into its private internal storage and then
uses it read-only, so a farmer with no connectivity still gets the crop list,
the disease knowledge base, treatment plans and irrigation thresholds.

Two data sources are supported:

* ``--source static`` (default) - parse ``ai_engine.services.FALLBACK_DISEASE_DATABASE``
  and ``sensors.services.CROP_IRRIGATION_THRESHOLDS`` straight from the source
  files with :mod:`ast`.  No Django, no database, no dependencies: it runs in
  CI and on a clean clone.
* ``--source django`` - boot Django and export the live ``diagnosis.Disease``
  rows, i.e. the knowledge base an administrator has curated in production.

The output is deterministic (fixed row order, fixed ``generated_at`` unless
``--timestamp`` is given) so rebuilding without content changes produces a
byte-identical file and does not churn Git history.

Usage::

    python tools/build_offline_db.py                     # static source
    python tools/build_offline_db.py --source django     # live DB export
    python tools/build_offline_db.py --check             # verify checked-in file is current
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import os
import sqlite3
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND = REPO_ROOT / 'backend' / 'agrisense_backend'
AI_SERVICES = BACKEND / 'ai_engine' / 'services.py'
SENSOR_SERVICES = BACKEND / 'sensors' / 'services.py'
DEFAULT_OUTPUT = REPO_ROOT / 'frontend' / 'agrisense_app' / 'assets' / 'db' / 'agrisense_offline.db'

# Bump this whenever the *schema* or the seeded content changes.  The Flutter
# side compares it against the copy already installed on the device and
# re-installs when the bundled asset is newer (see OfflineDatabase in
# lib/services/local/offline_database.dart) - keep the two values in sync.
SCHEMA_VERSION = 1

DISEASE_COLUMNS = (
    'disease_name', 'crop_name', 'pathogen', 'symptoms', 'causes', 'severity',
    'prevention', 'treatment_type', 'medication', 'instructions', 'duration',
)

SCHEMA = """
PRAGMA journal_mode = DELETE;

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE crop (
    id                  INTEGER PRIMARY KEY,
    name                TEXT NOT NULL UNIQUE,
    label               TEXT NOT NULL DEFAULT '',
    moisture_dry        REAL,
    moisture_adequate   REAL
);

CREATE TABLE disease (
    id              INTEGER PRIMARY KEY,
    disease_name    TEXT NOT NULL UNIQUE,
    crop_name       TEXT NOT NULL,
    pathogen        TEXT NOT NULL DEFAULT '',
    symptoms        TEXT NOT NULL DEFAULT '',
    causes          TEXT NOT NULL DEFAULT '',
    severity        TEXT NOT NULL DEFAULT 'low'
                    CHECK (severity IN ('low', 'medium', 'high')),
    prevention      TEXT NOT NULL DEFAULT '',
    treatment_type  TEXT NOT NULL DEFAULT '',
    medication      TEXT NOT NULL DEFAULT '',
    instructions    TEXT NOT NULL DEFAULT '',
    duration        INTEGER NOT NULL DEFAULT 14
);

CREATE INDEX idx_disease_crop ON disease (crop_name);
CREATE INDEX idx_disease_severity ON disease (severity);
"""


# ---------------------------------------------------------------------------
# Data sources
# ---------------------------------------------------------------------------
def _literal_from_module(path: Path, name: str):
    """Read a module-level literal assignment without importing the module."""
    tree = ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == name for t in node.targets
        ):
            return ast.literal_eval(node.value)
    raise SystemExit(f'{name} not found in {path}')


def load_static_diseases() -> list[dict]:
    raw = _literal_from_module(AI_SERVICES, 'FALLBACK_DISEASE_DATABASE')
    rows = []
    for crop, diseases in raw.items():
        for entry in diseases:
            row = {key: entry.get(key, '') for key in DISEASE_COLUMNS}
            row['crop_name'] = crop
            row['severity'] = entry.get('severity', 'low')
            row['duration'] = int(entry.get('duration', 14) or 0)
            rows.append(row)
    return rows


def load_django_diseases() -> list[dict]:
    sys.path.insert(0, str(BACKEND))
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'agrisense_backend.settings')
    import django  # noqa: PLC0415 - optional dependency, imported on demand

    django.setup()
    from diagnosis.models import Disease  # noqa: PLC0415

    rows = []
    for obj in Disease.objects.all().order_by('crop_name', 'disease_name'):
        rows.append({
            'disease_name': obj.disease_name,
            'crop_name': obj.crop_name,
            'pathogen': obj.pathogen or '',
            'symptoms': obj.symptoms or '',
            'causes': obj.causes or '',
            'severity': obj.severity or 'low',
            'prevention': obj.prevention or '',
            'treatment_type': obj.treatment_type or '',
            'medication': obj.medication or '',
            'instructions': obj.instructions or '',
            'duration': int(obj.duration or 0),
        })
    return rows


def load_crops(disease_rows: list[dict]) -> list[dict]:
    thresholds = _literal_from_module(SENSOR_SERVICES, 'CROP_IRRIGATION_THRESHOLDS')
    default = _literal_from_module(SENSOR_SERVICES, 'DEFAULT_THRESHOLDS')
    supported = _literal_from_module(AI_SERVICES, 'DEFAULT_SUPPORTED_CROPS')

    names = sorted({r['crop_name'] for r in disease_rows} | set(thresholds) | set(supported))
    crops = []
    for name in names:
        t = thresholds.get(name, default)
        crops.append({
            'name': name,
            'label': t.get('label', name),
            'moisture_dry': float(t['dry']),
            'moisture_adequate': float(t['adequate']),
        })
    return crops


# ---------------------------------------------------------------------------
# Builder
# ---------------------------------------------------------------------------
def build(output: Path, source: str, timestamp: str) -> Path:
    diseases = load_django_diseases() if source == 'django' else load_static_diseases()
    diseases.sort(key=lambda r: (r['crop_name'], r['disease_name']))
    crops = load_crops(diseases)

    output.parent.mkdir(parents=True, exist_ok=True)
    tmp_fd, tmp_name = tempfile.mkstemp(suffix='.db', dir=output.parent)
    os.close(tmp_fd)
    tmp_path = Path(tmp_name)
    tmp_path.unlink(missing_ok=True)

    conn = sqlite3.connect(tmp_path)
    try:
        conn.executescript(SCHEMA)
        conn.executemany(
            'INSERT INTO crop (name, label, moisture_dry, moisture_adequate) VALUES (?, ?, ?, ?)',
            [(c['name'], c['label'], c['moisture_dry'], c['moisture_adequate']) for c in crops],
        )
        conn.executemany(
            f'INSERT INTO disease ({", ".join(DISEASE_COLUMNS)}) '
            f'VALUES ({", ".join("?" * len(DISEASE_COLUMNS))})',
            [tuple(r[c] for c in DISEASE_COLUMNS) for r in diseases],
        )
        conn.executemany(
            'INSERT INTO meta (key, value) VALUES (?, ?)',
            [
                ('schema_version', str(SCHEMA_VERSION)),
                ('generated_at', timestamp),
                ('source', source),
                ('disease_count', str(len(diseases))),
                ('crop_count', str(len(crops))),
                ('app', 'agrisense'),
            ],
        )
        # `PRAGMA user_version` is the cheapest possible version probe on the
        # device: sqflite can read it without a table scan.
        conn.execute(f'PRAGMA user_version = {SCHEMA_VERSION}')
        conn.commit()

        (integrity,) = conn.execute('PRAGMA integrity_check').fetchone()
        if integrity != 'ok':
            raise SystemExit(f'integrity_check failed: {integrity}')

        # VACUUM rewrites the file compactly and, combined with journal_mode
        # DELETE, guarantees no -wal/-shm sidecars end up in the asset.
        conn.execute('VACUUM')
    finally:
        conn.close()

    tmp_path.replace(output)
    return output


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--source', choices=('static', 'django'), default='static')
    parser.add_argument('--timestamp', default=f'schema-v{SCHEMA_VERSION}',
                        help='value stored in meta.generated_at (kept stable for '
                             'reproducible builds; pass an ISO date for releases)')
    parser.add_argument('--check', action='store_true',
                        help='fail if the checked-in asset differs from a fresh build')
    args = parser.parse_args()

    if args.check:
        if not args.output.exists():
            print(f'MISSING: {args.output}', file=sys.stderr)
            return 1
        before = digest(args.output)
        with tempfile.TemporaryDirectory() as tmp:
            fresh = build(Path(tmp) / 'fresh.db', args.source, args.timestamp)
            after = digest(fresh)
        if before != after:
            print('STALE: regenerate with `python tools/build_offline_db.py`', file=sys.stderr)
            return 1
        print(f'OK: {args.output} is up to date ({before[:12]})')
        return 0

    out = build(args.output, args.source, args.timestamp)
    conn = sqlite3.connect(out)
    (crops,) = conn.execute('SELECT COUNT(*) FROM crop').fetchone()
    (diseases,) = conn.execute('SELECT COUNT(*) FROM disease').fetchone()
    conn.close()
    print(f'Wrote {out.relative_to(REPO_ROOT)}')
    print(f'  size            : {out.stat().st_size:,} bytes')
    print(f'  schema_version  : {SCHEMA_VERSION}')
    print(f'  crops / diseases: {crops} / {diseases}')
    print(f'  sha256          : {digest(out)}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

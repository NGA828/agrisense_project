import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Read-only, pre-populated knowledge base that ships **inside the APK**.
///
/// ## Why
/// AgriSense targets farmers in low/no-coverage areas. The crop list, the
/// disease knowledge base, treatment plans and irrigation thresholds are static
/// reference data, so there is no reason to make a farmer's first launch depend
/// on a network round-trip. The database is generated at build time by
/// `tools/build_offline_db.py`, declared as a Flutter asset, and therefore
/// travels with the APK.
///
/// ## How the "install" works
/// An APK is a ZIP; assets inside it are *not* writable and, on Android, a
/// compressed asset has no stable on-disk path a native library can open.
/// SQLite needs a real file on a writable filesystem, so on first launch the
/// asset is copied into the app's private internal storage
/// (`/data/data/<applicationId>/app_flutter/databases/agrisense_offline.db`).
/// That directory is created by the OS at install time, is private to the app's
/// UID, and is deleted automatically when the app is uninstalled.
///
/// The copy is:
/// * **idempotent** - a version stamp (`PRAGMA user_version`) is compared with
///   [bundledSchemaVersion]; the copy only happens on first run or after an app
///   update that ships a newer database;
/// * **atomic** - written to a `.tmp` sibling and then renamed, so a process
///   kill mid-copy can never leave a truncated database behind;
/// * **crash-safe** - any stale `-wal` / `-shm` / `-journal` sidecars from a
///   previous install are removed before the rename.
///
/// ## Read-only by contract
/// User-generated data belongs in the backend (and in `LocalCacheService` for
/// the offline cache/outbox). This database is opened `readOnly: true` so an
/// app update can always replace it wholesale without a migration path.
class OfflineDatabase {
  OfflineDatabase._();

  static final OfflineDatabase instance = OfflineDatabase._();

  /// Must match `SCHEMA_VERSION` in `tools/build_offline_db.py`.
  static const int bundledSchemaVersion = 1;

  static const String assetPath = 'assets/db/agrisense_offline.db';
  static const String fileName = 'agrisense_offline.db';

  Database? _db;
  Future<Database>? _opening;

  /// Opens the database, installing it from the bundled asset if needed.
  ///
  /// Concurrent callers share a single in-flight future, so a cold start that
  /// hits the knowledge base from several providers at once still performs
  /// exactly one copy.
  Future<Database> get database {
    final open = _db;
    if (open != null && open.isOpen) return Future.value(open);
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final path = await _ensureInstalled();
    final db = await openDatabase(path, readOnly: true);
    _db = db;
    return db;
  }

  /// Resolves the on-device path, copying the asset over when required.
  Future<String> _ensureInstalled() async {
    final dir = Directory(p.join(
      (await getApplicationDocumentsDirectory()).path,
      'databases',
    ));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    final path = p.join(dir.path, fileName);

    if (!await _needsInstall(path)) return path;

    // 1. Read the asset out of the APK (Flutter decompresses it for us).
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

    // 2. Write to a temporary sibling first so an interrupted copy is never
    //    mistaken for a usable database.
    final tmp = File('$path.tmp');
    if (tmp.existsSync()) await tmp.delete();
    await tmp.writeAsBytes(bytes, flush: true);

    // 3. Drop sidecar files belonging to any previous copy: a stale -wal could
    //    otherwise be replayed on top of the fresh database and corrupt it.
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      final sidecar = File('$path$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }

    // 4. Atomic swap. rename(2) within the same filesystem cannot half-apply.
    await tmp.rename(path);

    if (kDebugMode) {
      debugPrint('[OfflineDatabase] installed $fileName '
          '(${bytes.lengthInBytes} bytes, schema v$bundledSchemaVersion)');
    }
    return path;
  }

  /// True on first launch, after an app update shipping a newer schema, or when
  /// the existing file is unreadable/corrupt.
  Future<bool> _needsInstall(String path) async {
    final file = File(path);
    if (!file.existsSync()) return true;
    if (await file.length() == 0) return true;

    Database? probe;
    try {
      probe = await openDatabase(path, readOnly: true);
      final version = Sqflite.firstIntValue(
            await probe.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      return version < bundledSchemaVersion;
    } catch (_) {
      // Unreadable or corrupted (e.g. killed mid-write on an older build):
      // reinstalling from the asset is always safe because the file is
      // read-only reference data.
      return true;
    } finally {
      await probe?.close();
    }
  }

  /// Call from `main()` to pay the copy cost during the splash screen instead
  /// of on the farmer's first knowledge-base read. Never throws: the app must
  /// still start (falling back to the network) if the asset is unavailable.
  Future<void> warmUp() async {
    try {
      await database;
    } catch (e) {
      debugPrint('[OfflineDatabase] warmUp failed: $e');
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  // ── Queries ────────────────────────────────────────────────────────────

  /// Crop names supported offline (used by the AI scan screen's crop picker
  /// when `GET /api/diseases/supported_crops/` is unreachable).
  Future<List<String>> supportedCrops() async {
    final db = await database;
    final rows = await db.query('crop', columns: ['name'], orderBy: 'name');
    return rows.map((r) => r['name'] as String).toList();
  }

  /// Full disease records, optionally narrowed to one crop.
  Future<List<Map<String, Object?>>> diseases({String? crop}) async {
    final db = await database;
    return db.query(
      'disease',
      where: crop == null ? null : 'crop_name = ?',
      whereArgs: crop == null ? null : [crop],
      orderBy: 'disease_name',
    );
  }

  /// One disease by name (case-insensitive), or null when unknown offline.
  Future<Map<String, Object?>?> diseaseByName(String name) async {
    final db = await database;
    final rows = await db.query(
      'disease',
      where: 'disease_name = ? COLLATE NOCASE',
      whereArgs: [name],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Free-text search across name, symptoms and pathogen.
  Future<List<Map<String, Object?>>> searchDiseases(String query) async {
    if (query.trim().isEmpty) return diseases();
    final db = await database;
    final like = '%${query.trim()}%';
    return db.query(
      'disease',
      where: 'disease_name LIKE ? OR symptoms LIKE ? OR pathogen LIKE ?',
      whereArgs: [like, like, like],
      orderBy: 'disease_name',
    );
  }

  /// Crop-specific soil-moisture thresholds for offline irrigation advice.
  Future<Map<String, Object?>?> irrigationThresholds(String crop) async {
    final db = await database;
    final rows = await db.query(
      'crop',
      where: 'name = ? COLLATE NOCASE',
      whereArgs: [crop],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Build metadata (`schema_version`, `generated_at`, `source`, counts) -
  /// handy for a debug/about screen and for support tickets.
  Future<Map<String, String>> meta() async {
    final db = await database;
    final rows = await db.query('meta');
    return {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
  }
}

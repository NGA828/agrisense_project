import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:agrisense_app/services/local/offline_database.dart';

/// Verifies the bundled-database contract:
///  * the asset declared in pubspec.yaml exists and is a valid SQLite file;
///  * it carries the schema version the Dart side expects;
///  * the "install on first launch" copy lands in internal storage, is
///    idempotent, and self-heals a corrupted or outdated copy.
///
/// Run with: flutter test test/offline_database_test.dart
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  final assetFile = File(p.join('assets', 'db', 'agrisense_offline.db'));
  late Directory docs;

  setUp(() {
    docs = Directory.systemTemp.createTempSync('agrisense_docs');
    // Stand in for path_provider's platform channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });

  tearDown(() async {
    await OfflineDatabase.instance.close();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  String installedPath() =>
      p.join(docs.path, 'databases', OfflineDatabase.fileName);

  group('bundled asset', () {
    test('exists and is a real SQLite database', () async {
      expect(assetFile.existsSync(), isTrue,
          reason: 'run `python tools/build_offline_db.py`');
      final header = await assetFile.openRead(0, 16).first;
      expect(String.fromCharCodes(header.sublist(0, 15)), 'SQLite format 3');
    });

    test('has no -wal/-shm sidecars checked in', () {
      expect(File('${assetFile.path}-wal').existsSync(), isFalse);
      expect(File('${assetFile.path}-shm').existsSync(), isFalse);
    });

    test('schema version matches the Dart constant', () async {
      final db = await databaseFactory.openDatabase(assetFile.path);
      final version =
          Sqflite.firstIntValue(await db.rawQuery('PRAGMA user_version'));
      await db.close();
      expect(version, OfflineDatabase.bundledSchemaVersion);
    });

    test('is populated with crops and diseases', () async {
      final db = await databaseFactory.openDatabase(assetFile.path);
      final crops =
          Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM crop'));
      final diseases = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM disease'));
      await db.close();
      expect(crops, greaterThan(0));
      expect(diseases, greaterThan(0));
    });
  });

  group('install into internal storage', () {
    test('first launch copies the asset out of the APK', () async {
      expect(File(installedPath()).existsSync(), isFalse);
      final crops = await OfflineDatabase.instance.supportedCrops();
      expect(File(installedPath()).existsSync(), isTrue);
      expect(crops, isNotEmpty);
    });

    test('second launch reuses the copy instead of rewriting it', () async {
      await OfflineDatabase.instance.supportedCrops();
      await OfflineDatabase.instance.close();
      final stamp = File(installedPath()).lastModifiedSync();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      await OfflineDatabase.instance.supportedCrops();

      expect(File(installedPath()).lastModifiedSync(), stamp);
    });

    test('a corrupted copy is reinstalled from the asset', () async {
      await OfflineDatabase.instance.supportedCrops();
      await OfflineDatabase.instance.close();
      File(installedPath()).writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

      final crops = await OfflineDatabase.instance.supportedCrops();

      expect(crops, isNotEmpty);
      expect(File(installedPath()).lengthSync(), greaterThan(4));
    });

    test('an outdated copy is replaced after an app update', () async {
      await OfflineDatabase.instance.supportedCrops();
      await OfflineDatabase.instance.close();

      final db = await databaseFactory.openDatabase(installedPath());
      await db.execute('PRAGMA user_version = 0');
      await db.execute("DELETE FROM crop");
      await db.close();

      final crops = await OfflineDatabase.instance.supportedCrops();
      expect(crops, isNotEmpty, reason: 'stale copy should be overwritten');
    });

    test('no temp file is left behind', () async {
      await OfflineDatabase.instance.supportedCrops();
      expect(File('${installedPath()}.tmp').existsSync(), isFalse);
    });
  });

  group('queries', () {
    test('diseases can be filtered by crop', () async {
      final crops = await OfflineDatabase.instance.supportedCrops();
      final crop = crops.firstWhere((c) => c == 'Tomato', orElse: () => crops.first);
      final rows = await OfflineDatabase.instance.diseases(crop: crop);
      for (final row in rows) {
        expect(row['crop_name'], crop);
      }
    });

    test('lookup by name is case-insensitive', () async {
      final all = await OfflineDatabase.instance.diseases();
      final name = all.first['disease_name'] as String;
      final hit = await OfflineDatabase.instance.diseaseByName(name.toUpperCase());
      expect(hit, isNotNull);
      expect(hit!['disease_name'], name);
    });

    test('irrigation thresholds are available offline', () async {
      final t = await OfflineDatabase.instance.irrigationThresholds('Tomato');
      expect(t, isNotNull);
      expect(t!['moisture_dry'], isA<num>());
      expect(t['moisture_adequate'], isA<num>());
    });

    test('meta reports the build provenance', () async {
      final meta = await OfflineDatabase.instance.meta();
      expect(meta['schema_version'],
          OfflineDatabase.bundledSchemaVersion.toString());
      expect(meta['app'], 'agrisense');
    });
  });
}

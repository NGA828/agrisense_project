import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Offline-first cache + action outbox for AgriSense AI.
///
/// For low/no-coverage farming regions the app caches the last-known copy of
/// key data (diagnosis history, marketplace catalog, weather) so the UI stays
/// usable when the network drops, and queues mutating actions in an outbox that
/// is flushed once connectivity returns.
class LocalCacheService {
  LocalCacheService._();
  static final LocalCacheService instance = LocalCacheService._();

  static const String _keyDiagnosisHistory = 'cache.diagnosis_history';
  static const String _keyMarketplace = 'cache.marketplace';
  static const String _keyWeather = 'cache.weather';
  static const String _keyOutbox = 'cache.outbox';

  // ── Generic helpers ──────────────────────────────────────────────────
  Future<void> _set(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(value));
  }

  Future<dynamic> _get(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  // ── Cached collections ───────────────────────────────────────────────
  Future<void> cacheDiagnosisHistory(List<dynamic> items) =>
      _set(_keyDiagnosisHistory, items);

  Future<List<dynamic>?> getDiagnosisHistory() async =>
      await _get(_keyDiagnosisHistory) as List<dynamic>?;

  Future<void> cacheMarketplace(List<dynamic> items) => _set(_keyMarketplace, items);

  Future<List<dynamic>?> getMarketplace() async =>
      await _get(_keyMarketplace) as List<dynamic>?;

  Future<void> cacheWeather(Map<String, dynamic> data) => _set(_keyWeather, data);

  Future<Map<String, dynamic>?> getWeather() async =>
      await _get(_keyWeather) as Map<String, dynamic>?;

  // ── Action outbox (offline queue of mutations) ───────────────────────
  /// Enqueue an offline action. Returns true if queued.
  Future<void> enqueueOutbox(Map<String, dynamic> action) async {
    final queue = await getOutbox();
    queue.add(action);
    await _set(_keyOutbox, queue);
  }

  Future<List<dynamic>> getOutbox() async =>
      await _get(_keyOutbox) as List<dynamic>? ?? [];

  /// Replace the outbox after a flush (drops already-synced actions).
  Future<void> replaceOutbox(List<dynamic> queue) async =>
      await _set(_keyOutbox, queue);

  Future<void> clearOutbox() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOutbox);
  }

  /// Reset all offline caches (e.g. on logout to avoid leaking data between
  /// accounts).
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_keyDiagnosisHistory, _keyMarketplace, _keyWeather, _keyOutbox]) {
      await prefs.remove(key);
    }
  }
}

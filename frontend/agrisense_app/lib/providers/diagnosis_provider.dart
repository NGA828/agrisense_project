import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/diagnosis.dart';
import '../services/api/api_service.dart';
import '../services/local/cache_service.dart';

class DiagnosisProvider with ChangeNotifier {
  final ApiService _api = ApiService();
  List<Diagnosis> _history = [];
  Diagnosis? _currentDiagnosis;
  bool _isLoading = false;
  String? _error;

  List<Diagnosis> get history => _history;
  Diagnosis? get currentDiagnosis => _currentDiagnosis;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadHistory() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final fetched = await _api.getDiagnosisHistory();
      _history = fetched.cast<Diagnosis>();
      // Cache a JSON copy for offline reads.
      await LocalCacheService.instance
          .cacheDiagnosisHistory(fetched.map((d) => d.toJson()).toList());
    } catch (e) {
      // Offline-first: fall back to the last-known cached history.
      _error = e.toString();
      final cached = await LocalCacheService.instance.getDiagnosisHistory();
      if (cached != null) {
        _history = cached
            .map((j) => Diagnosis.fromJson(j as Map<String, dynamic>))
            .toList();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> analyzeImage(Uint8List imageBytes, String fileName, String cropType) async {
    _isLoading = true;
    _error = null;
    _currentDiagnosis = null;
    notifyListeners();
    try {
      _currentDiagnosis = await _api.analyzePlantImageBytes(imageBytes, fileName, cropType);
      _history.insert(0, _currentDiagnosis!);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

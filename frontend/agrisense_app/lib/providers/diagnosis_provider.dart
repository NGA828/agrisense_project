import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/diagnosis.dart';
import '../services/api/api_service.dart';
import '../services/local/cache_service.dart';

class DiagnosisProvider with ChangeNotifier {
  final ApiService _api;
  DiagnosisProvider({ApiService? api}) : _api = api ?? ApiService();
  bool _isAnalyzing = false;
  String? _errorCode;
  String? get errorCode => _errorCode;
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

  Future<Diagnosis?> analyzeImage(Uint8List imageBytes, String fileName, String cropType) async {
    if (_isAnalyzing) return null;
    _isAnalyzing = true;
    _isLoading = true;
    _error = null;
    _errorCode = null;
    _currentDiagnosis = null;
    notifyListeners();
    try {
      final result = await _api.analyzePlantImageBytes(imageBytes, fileName, cropType);
      if (result.cropType.trim().toLowerCase() != cropType.trim().toLowerCase()) {
        throw ApiException('The returned crop does not match your selection.', code: 'crop_mismatch');
      }
      _currentDiagnosis = result;
      _history.removeWhere((d) => d.id == result.id);
      _history.insert(0, result);
      return result;
    } on TimeoutException {
      _error = 'The analysis took too long to respond. Please retry shortly.';
      _errorCode = 'ai_timeout';
    } on ApiException catch (e) {
      _error = e.message;
      _errorCode = e.code;
    } catch (_) {
      _error = 'Could not connect to crop analysis. Check your internet connection and try again.';
    } finally {
      _isAnalyzing = false;
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }
}

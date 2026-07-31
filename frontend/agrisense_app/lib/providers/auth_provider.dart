import 'package:flutter/foundation.dart';

import '../models/user.dart';
import '../services/api/api_service.dart';

class AuthProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  User? _currentUser;
  bool _isLoading = false;
  bool _isRestoring = true;
  String? _error;

  User? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get isRestoring => _isRestoring;
  bool get isAuthenticated => _currentUser != null;
  String? get error => _error;

  Future<void> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _apiService.login(username, password);
      _currentUser = await _apiService.getCurrentUser();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called on app start: if a stored token exists, restore the session so
  /// the farmer is not asked to log in again ("persistent session management").
  Future<void> restoreSession() async {
    if (!_isRestoring) {
      _isRestoring = true;
      notifyListeners();
    }
    try {
      if (await _apiService.hasStoredTokens) {
        _currentUser = await _apiService.getCurrentUser();
      }
    } catch (e) {
      // Token invalid/expired and refresh failed -> start clean.
      await _apiService.clearSession();
      _currentUser = null;
    } finally {
      _isRestoring = false;
      notifyListeners();
    }
  }

  Future<void> loadCurrentUser() async {
    try {
      _currentUser = await _apiService.getCurrentUser();
      notifyListeners();
    } catch (e) {
      _currentUser = null;
    }
  }

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
  }) async {
    try {
      await _apiService.updateProfile(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
      );
      _currentUser = await _apiService.getCurrentUser();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      rethrow;
    }
  }

  Future<void> logout() async {
    await _apiService.logout();
    _currentUser = null;
    notifyListeners();
  }
}

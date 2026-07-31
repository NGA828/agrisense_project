import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user.dart';
import '../../models/diagnosis.dart';
import '../../models/product.dart';

/// Central HTTP client for the AgriSense AI REST API.
///
/// - Base URL is overridable at build time with
///   `--dart-define=API_BASE_URL=http://192.168.1.10:8000/api`
/// - Defaults adapt per platform: Android emulators reach the host via
///   10.0.2.2, everything else uses localhost.
/// - On HTTP 401 the client transparently refreshes the JWT (using the stored
///   refresh token) and retries the original request once.
class ApiService {
  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get defaultBaseUrl {
    if (_definedBaseUrl.isNotEmpty) return _definedBaseUrl;
    // Android emulator can't see `localhost` of the host machine.
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api';
    return 'http://localhost:8000/api';
  }

  static String baseUrl = defaultBaseUrl;

  static String get mediaUrl => baseUrl.replaceFirst(RegExp(r'/api$'), '');

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Map<String, String> get _headers => {'Content-Type': 'application/json'};

  Future<Map<String, String>> get _authHeaders async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Absolute URL for media paths returned by the API (which may be relative).
  static String resolveMedia(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '$mediaUrl$path';
  }

  /// WebSocket URL for a chat room (wss in production, ws otherwise).
  static String chatWebSocketUrl(int roomId) {
    final httpUrl = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final scheme = httpUrl.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://${httpUrl.replaceFirst(RegExp(r'^https?://'), '')}/ws/chat/$roomId/';
  }

  /// Low-level authenticated request with one automatic JWT refresh retry.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request, {
    bool isMultipart = false,
  }) async {
    Future<http.Response> attempt(Map<String, String> headers) => request(headers);

    var headers = await _authHeaders;
    if (isMultipart) {
      headers = Map.of(headers)..remove('Content-Type');
    }
    var response = await attempt(headers).timeout(const Duration(seconds: 30));

    final isLoginRequest = response.request?.url.path.endsWith('/auth/login/') ?? false;
    if (response.statusCode == 401 && !isLoginRequest) {
      final refreshed = await _tryRefreshToken();
      if (refreshed) {
        headers = await _authHeaders;
        if (isMultipart) headers = Map.of(headers)..remove('Content-Type');
        response = await attempt(headers).timeout(const Duration(seconds: 30));
      }
    }
    return response;
  }

  Future<bool> _tryRefreshToken() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/auth/refresh/'),
        headers: _headers,
        body: jsonEncode({'refresh': refresh}),
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        await _storage.write(key: 'access_token', value: data['access']);
        if (data['refresh'] != null) {
          await _storage.write(key: 'refresh_token', value: data['refresh']);
        }
        return true;
      }
      await _storage.delete(key: 'access_token');
      await _storage.delete(key: 'refresh_token');
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> clearSession() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  /// Expose the current access token (used to authenticate WebSocket links).
  Future<String?> getAccessToken() => _storage.read(key: 'access_token');

  // ── Auth ──────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access']);
      await _storage.write(key: 'refresh_token', value: data['refresh']);
      return data;
    }
    throw ApiException(_messageFrom(response, fallback: 'Login failed'));
  }

  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
    required String phoneNumber,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'phone_number': phoneNumber,
        'role': role,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Registration failed'));
    }
  }

  Future<User> getCurrentUser() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/users/me/'), headers: h));
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw ApiException(_messageFrom(response, fallback: 'Failed to load user'));
  }

  Future<void> updateProfile({
    String? firstName,
    String? lastName,
    String? phoneNumber,
  }) async {
    final body = <String, dynamic>{
      if (firstName != null) 'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
      if (phoneNumber != null) 'phone_number': phoneNumber,
    };
    final response = await _send((h) => http.patch(
          Uri.parse('$baseUrl/users/me/'),
          headers: h,
          body: jsonEncode(body),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to update profile'));
    }
  }

  Future<void> logout() => clearSession();

  Future<bool> get hasStoredTokens async =>
      await _storage.read(key: 'access_token') != null;

  // ── Diagnosis ─────────────────────────────────────────
  Future<Diagnosis> analyzePlantImageBytes(
      Uint8List imageBytes, String fileName, String cropType) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/diagnosis/analyze/'));
    final token = await _storage.read(key: 'access_token');
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: fileName));
    request.fields['crop_type'] = cropType;
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201) return Diagnosis.fromJson(jsonDecode(response.body));
    throw ApiException(_messageFrom(response, fallback: 'Analysis failed'));
  }

  Future<List<Diagnosis>> getDiagnosisHistory() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/diagnosis/history/'), headers: h));
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).map((j) => Diagnosis.fromJson(j)).toList();
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load history'));
  }

  // ── Products / marketplace ────────────────────────────
  Future<List<Product>> getMarketplaceProducts({String? category, String? search}) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty && category != 'All') 'category': category,
      if (search != null && search.isNotEmpty) 'search': search,
    };
    final uri = Uri.parse('$baseUrl/products/marketplace/').replace(queryParameters: query.isEmpty ? null : query);
    final response = await _send((h) => http.get(uri, headers: h));
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).map((j) => Product.fromJson(j)).toList();
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load products'));
  }

  Future<Product> getProduct(int id) async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/products/$id/'), headers: h));
    if (response.statusCode == 200) return Product.fromJson(jsonDecode(response.body));
    throw ApiException(_messageFrom(response, fallback: 'Failed to load product'));
  }

  Future<List<Product>> getMyProducts() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/products/my_products/'), headers: h));
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).map((j) => Product.fromJson(j)).toList();
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load your products'));
  }

  Future<Map<String, dynamic>> addProduct({
    required String name,
    required String description,
    required String category,
    required double price,
    required int stockQuantity,
    File? imageFile,
  }) async {
    if (imageFile != null) {
      var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/products/'));
      final token = await _storage.read(key: 'access_token');
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields['name'] = name;
      request.fields['description'] = description;
      request.fields['category'] = category;
      request.fields['price'] = price.toString();
      request.fields['stock_quantity'] = stockQuantity.toString();
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 201) return jsonDecode(response.body);
      throw ApiException(_messageFrom(response, fallback: 'Failed to add product'));
    } else {
      final response = await _send((h) => http.post(
            Uri.parse('$baseUrl/products/'),
            headers: h,
            body: jsonEncode({
              'name': name,
              'description': description,
              'category': category,
              'price': price,
              'stock_quantity': stockQuantity,
            }),
          ));
      if (response.statusCode == 201) return jsonDecode(response.body);
      throw ApiException(_messageFrom(response, fallback: 'Failed to add product'));
    }
  }

  Future<Map<String, dynamic>> updateProduct(
    int productId, {
    required String name,
    required String description,
    required String category,
    required double price,
    required int stockQuantity,
  }) async {
    final response = await _send((h) => http.put(
          Uri.parse('$baseUrl/products/$productId/'),
          headers: h,
          body: jsonEncode({
            'name': name,
            'description': description,
            'category': category,
            'price': price,
            'stock_quantity': stockQuantity,
          }),
        ));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to update product'));
  }

  Future<void> deleteProduct(int productId) async {
    final response = await _send((h) => http.delete(Uri.parse('$baseUrl/products/$productId/'), headers: h));
    if (response.statusCode != 204) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to delete product'));
    }
  }

  Future<Map<String, dynamic>> toggleProductAvailability(int productId) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/products/$productId/toggle_availability/'),
          headers: h,
        ));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to update product'));
  }

  // ── Orders ────────────────────────────────────────────
  Future<Map<String, dynamic>> createOrder(int productId, int quantity) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/orders/'),
          headers: h,
          body: jsonEncode({'product': productId, 'quantity': quantity}),
        ));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to create order'));
  }

  Future<List<dynamic>> getOrders() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/orders/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load orders'));
  }

  Future<Map<String, dynamic>> updateOrderStatus(int orderId, String status) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/orders/$orderId/update_status/'),
          headers: h,
          body: jsonEncode({'status': status}),
        ));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to update order'));
  }

  // ── Chat (REST fallback) ──────────────────────────────
  Future<List<dynamic>> getChatRooms() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/chat/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load chats'));
  }

  Future<Map<String, dynamic>> createChatRoom({int? dealerId, int? farmerId}) async {
    final body = <String, dynamic>{};
    if (dealerId != null) body['dealer'] = dealerId;
    if (farmerId != null) body['farmer'] = farmerId;
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/chat/'),
          headers: h,
          body: jsonEncode(body),
        ));
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to start chat'));
  }

  Future<List<dynamic>> getChatMessages(int roomId) async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/chat/$roomId/messages/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load messages'));
  }

  Future<Map<String, dynamic>> sendMessage(int roomId, String content) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/chat/$roomId/send_message/'),
          headers: h,
          body: jsonEncode({'content': content}),
        ));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to send message'));
  }

  Future<Map<String, dynamic>> sendImageMessage(int roomId, XFile image) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/$roomId/send_message/'));
    final token = await _storage.read(key: 'access_token');
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    final streamed = await request.send().timeout(const Duration(seconds: 45));
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to send image'));
  }

  Future<void> markChatRead(int roomId) async {
    await _send((h) => http.post(Uri.parse('$baseUrl/chat/$roomId/mark_read/'), headers: h));
  }

  Future<Map<String, dynamic>> getUnreadChatCounts() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/chat/unread_counts/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    return {};
  }

  // ── Payments ──────────────────────────────────────────
  Future<Map<String, dynamic>> createPayment(
      int orderId, String method, String phoneNumber, double amount) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/payments/'),
          headers: h,
          body: jsonEncode({
            'order': orderId,
            'payment_method': method,
            'phone_number': phoneNumber,
            'amount': amount,
          }),
        ));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to create payment'));
  }

  Future<Map<String, dynamic>> processPayment(int paymentId) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/payments/$paymentId/process_payment/'),
          headers: h,
        ));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to process payment'));
  }

  // ── Weather ───────────────────────────────────────────
  Future<Map<String, dynamic>> getWeather({double? lat, double? lon, String? location}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/weather/'),
      headers: _headers,
      body: jsonEncode({
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
        if (location != null) 'location': location,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load weather'));
  }

  // ── Users / Admin ─────────────────────────────────────
  Future<Map<String, dynamic>> getAdminStats() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/admin/stats/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load admin stats'));
  }

  Future<Map<String, dynamic>> getAdminAnalytics(String period) async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/admin/analytics/?period=$period'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load analytics'));
  }

  Future<Map<String, dynamic>> getHealth() async {
    final origin = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final response = await http
        .get(Uri.parse('$origin/health/'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Service unhealthy'));
  }

  Future<List<dynamic>> getUsers() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/users/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load users'));
  }

  Future<void> suspendUser(int userId) async {
    final response = await _send((h) =>
        http.post(Uri.parse('$baseUrl/users/$userId/suspend/'), headers: h));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to suspend user'));
    }
  }

  Future<void> activateUser(int userId) async {
    final response = await _send((h) =>
        http.post(Uri.parse('$baseUrl/users/$userId/activate/'), headers: h));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to activate user'));
    }
  }

  Future<void> deleteUser(int userId) async {
    final response = await _send((h) =>
        http.delete(Uri.parse('$baseUrl/users/$userId/'), headers: h));
    if (response.statusCode != 204) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to delete user'));
    }
  }

  Future<List<dynamic>> getPendingDealers() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/users/dealer_requests/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load dealer requests'));
  }

  Future<void> verifyDealer(int userId, bool approve) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/users/$userId/verify_dealer/'),
          headers: h,
          body: jsonEncode({'approve': approve}),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to verify dealer'));
    }
  }

  Future<Map<String, dynamic>> upgradePremium(
    int userId, {
    int durationMonths = 1,
    String? phoneNumber,
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/users/$userId/upgrade_premium/'),
          headers: h,
          body: jsonEncode({
            'duration_months': durationMonths,
            if (phoneNumber != null && phoneNumber.isNotEmpty) 'phone_number': phoneNumber,
          }),
        ));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to upgrade to premium'));
  }

  // ── Disease knowledge base (admin) ────────────────────
  Future<List<dynamic>> getDiseases() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/diseases/list_diseases/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load diseases'));
  }

  Future<List<dynamic>> getSupportedCrops() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/diseases/supported_crops/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  }

  Future<void> addDisease({
    required String cropName,
    required String diseaseName,
    required String pathogen,
    required String symptoms,
    required String severity,
    required String medication,
    required String instructions,
    required String treatmentType,
    String causes = '',
    String prevention = '',
    int duration = 14,
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/diseases/add_disease/'),
          headers: h,
          body: jsonEncode({
            'crop_name': cropName,
            'disease_name': diseaseName,
            'pathogen': pathogen,
            'symptoms': symptoms,
            'causes': causes,
            'severity': severity,
            'prevention': prevention,
            'medication': medication,
            'instructions': instructions,
            'treatment_type': treatmentType,
            'duration': duration,
          }),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to add disease'));
    }
  }

  Future<void> updateDisease(
    int diseaseId, {
    String? cropName,
    String? diseaseName,
    String? pathogen,
    String? symptoms,
    String? severity,
    String? medication,
    String? instructions,
    String? treatmentType,
    String? causes,
    String? prevention,
    int? duration,
  }) async {
    final body = <String, dynamic>{
      if (cropName != null) 'crop_name': cropName,
      if (diseaseName != null) 'disease_name': diseaseName,
      if (pathogen != null) 'pathogen': pathogen,
      if (symptoms != null) 'symptoms': symptoms,
      if (severity != null) 'severity': severity,
      if (medication != null) 'medication': medication,
      if (instructions != null) 'instructions': instructions,
      if (treatmentType != null) 'treatment_type': treatmentType,
      if (causes != null) 'causes': causes,
      if (prevention != null) 'prevention': prevention,
      if (duration != null) 'duration': duration,
    };
    final response = await _send((h) => http.put(
          Uri.parse('$baseUrl/diseases/$diseaseId/'),
          headers: h,
          body: jsonEncode(body),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to update disease'));
    }
  }

  Future<void> deleteDisease(int diseaseId) async {
    final response = await _send((h) =>
        http.delete(Uri.parse('$baseUrl/diseases/$diseaseId/'), headers: h));
    if (response.statusCode != 204) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to delete disease'));
    }
  }

  // ── Announcements & notifications ─────────────────────
  Future<List<dynamic>> getAnnouncements() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/announcements/active/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load announcements'));
  }

  Future<List<dynamic>> getAllAnnouncements() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/announcements/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load announcements'));
  }

  Future<void> createAnnouncement({
    required String title,
    required String content,
    required String targetAudience,
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/announcements/'),
          headers: h,
          body: jsonEncode({
            'title': title,
            'content': content,
            'target_audience': targetAudience,
          }),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to create announcement'));
    }
  }

  Future<void> deleteAnnouncement(int announcementId) async {
    final response = await _send((h) =>
        http.delete(Uri.parse('$baseUrl/announcements/$announcementId/'), headers: h));
    if (response.statusCode != 204) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to delete announcement'));
    }
  }

  Future<void> toggleAnnouncement(int announcementId) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/announcements/$announcementId/toggle_active/'),
          headers: h,
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to update announcement'));
    }
  }

  Future<List<dynamic>> getNotifications() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/notifications/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load notifications'));
  }

  Future<int> getUnreadNotificationCount() async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/notifications/unread_count/'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body)['count'] ?? 0;
    return 0;
  }

  Future<void> markNotificationRead(int notificationId) async {
    await _send((h) => http.post(
        Uri.parse('$baseUrl/notifications/$notificationId/mark_read/'), headers: h));
  }

  Future<void> markAllNotificationsRead() async {
    await _send((h) => http.post(
        Uri.parse('$baseUrl/notifications/mark_all_read/'), headers: h));
  }

  /// Extract a readable error message from a response body.
  static String _messageFrom(http.Response response, {required String fallback}) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map) {
        final error = data['error'] ?? data['detail'] ?? data['message'];
        if (error is String && error.isNotEmpty) return error;
        if (error is List && error.isNotEmpty) return error.join(', ');
        if (data.keys.isNotEmpty) {
          final firstKey = data.keys.first;
          final v = data[firstKey];
          if (v is List && v.isNotEmpty) return '$firstKey: ${v.join(', ')}';
          if (v is String) return '$firstKey: $v';
        }
      }
      if (data is List && data.isNotEmpty) return data.first.toString();
    } catch (_) {}
    return fallback;
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

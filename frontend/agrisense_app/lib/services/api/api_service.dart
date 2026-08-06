import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

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
  ///
  /// The backend returns relative media paths (e.g. `profile_photos/abc.png`),
  /// so we prefix them with the client's own configured base URL. This keeps
  /// images working on emulators, physical devices and behind reverse proxies
  /// regardless of the Host header the server saw. Absolute URLs are returned
  /// unchanged.
  static String resolveMedia(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    
    // Ensure path has /media prefix if it doesn't already
    String cleanPath = path.startsWith('/') ? path : '/$path';
    if (!cleanPath.startsWith('/media/')) {
      cleanPath = '/media$cleanPath';
    }
    
    final base = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    return '$base$cleanPath';
  }

  /// WebSocket URL for a chat room (wss in production, ws otherwise).
  static String chatWebSocketUrl(int roomId) {
    final httpUrl = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final scheme = httpUrl.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://${httpUrl.replaceFirst(RegExp(r'^https?://'), '')}/ws/chat/$roomId/';
  }

  /// WebSocket URL for the per-user realtime push bus (notifications, stock
  /// updates, broadcasts). One persistent connection per app session.
  static String pushWebSocketUrl() {
    final httpUrl = baseUrl.replaceFirst(RegExp(r'/api$'), '');
    final scheme = httpUrl.startsWith('https') ? 'wss' : 'ws';
    return '$scheme://${httpUrl.replaceFirst(RegExp(r'^https?://'), '')}/ws/push/';
  }

  // ── Realtime push tokens (FCM/APNs) ─────────────────────
  Future<void> registerPushToken({
    required String token,
    required String provider,
    required String platform,
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/push/register/'),
          headers: h,
          body: jsonEncode({
            'token': token,
            'provider': provider,
            'platform': platform,
          }),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to register push token'));
    }
  }

  Future<void> unregisterPushToken(String token) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/push/unregister/'),
          headers: h,
          body: jsonEncode({'token': token}),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to unregister push token'));
    }
  }

  // ── Reviews & product reports (Phase D) ───────────────
  Future<List<dynamic>> getReviews(int productId) async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/reviews/?product=$productId'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load reviews'));
  }

  Future<void> createReview({
    required int productId,
    required int rating,
    String comment = '',
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/reviews/'),
          headers: h,
          body: jsonEncode({'product': productId, 'rating': rating, 'comment': comment}),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to submit review'));
    }
  }

  Future<void> reportProduct({
    required int productId,
    required String reason,
    String details = '',
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/product_reports/'),
          headers: h,
          body: jsonEncode({'product': productId, 'reason': reason, 'details': details}),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to report product'));
    }
  }

  Future<void> resolveReport(int reportId, String decision) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/product_reports/$reportId/resolve/'),
          headers: h,
          body: jsonEncode({'decision': decision}),
        ));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to resolve report'));
    }
  }

  Future<List<dynamic>> getProductReports({String? status}) async {
    final query = status != null ? '?status=$status' : '';
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/product_reports/$query'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load reports'));
  }

  // ── Audit log (admin) ─────────────────────────────────
  Future<List<dynamic>> getAuditLogs({String? category}) async {
    final query = category != null ? '?category=$category' : '';
    return _fetchAllPages('/audit_logs/$query');
  }

  // ── Dealer sales analytics ────────────────────────────
  Future<Map<String, dynamic>> getDealerAnalytics(String period) async {
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/dealers/analytics/?period=$period'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load analytics'));
  }

  // ── Phone OTP ─────────────────────────────────────────
  Future<String?> requestOtp(String phoneNumber, String purpose) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/otp/send/'),
      headers: _headers,
      body: jsonEncode({'phone_number': phoneNumber, 'purpose': purpose}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['debug_code'] as String?;
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to send verification code'));
  }

  Future<void> verifyOtp(String phoneNumber, String purpose, String code) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/otp/verify/'),
      headers: _headers,
      body: jsonEncode({'phone_number': phoneNumber, 'purpose': purpose, 'code': code}),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Verification failed'));
    }
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

    final isLoginRequest = (response.request?.url?.path ?? '').endsWith('/auth/login/');
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
        final access = data is Map ? data['access'] : null;
        if (access == null) {
          await _storage.delete(key: 'access_token');
          await _storage.delete(key: 'refresh_token');
          return false;
        }
        await _storage.write(key: 'access_token', value: access);
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
      final access = data is Map ? data['access'] : null;
      final refresh = data is Map ? data['refresh'] : null;
      if (access == null || refresh == null) {
        throw ApiException('Invalid login response');
      }
      await _storage.write(key: 'access_token', value: access);
      await _storage.write(key: 'refresh_token', value: refresh);
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

  Future<void> resetPassword({
    required String username,
    required String phoneNumber,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/password_reset/'),
      headers: _headers,
      body: jsonEncode({
        'username': username,
        'phone_number': phoneNumber,
        'new_password': newPassword,
      }),
    ).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException(_messageFrom(response, fallback: 'Password reset failed'));
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
    XFile? profilePhoto,
  }) async {
    if (profilePhoto != null) {
      var request = http.MultipartRequest('PATCH', Uri.parse('$baseUrl/users/me/'));
      final token = await _storage.read(key: 'access_token');
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      if (firstName != null) request.fields['first_name'] = firstName;
      if (lastName != null) request.fields['last_name'] = lastName;
      if (phoneNumber != null) request.fields['phone_number'] = phoneNumber;
      final bytes = await profilePhoto.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes(
        'profile_photo', bytes,
        filename: profilePhoto.name,
      ));
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) {
        throw ApiException(_messageFrom(response, fallback: 'Failed to update profile'));
      }
    } else {
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
    // Free cloud-vision endpoints can queue briefly; keep the client timeout
    // above the backend's configured OpenRouter timeout (60s by default).
    final streamed = await request.send().timeout(const Duration(seconds: 90));
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
    XFile? imageFile,
    bool isAvailable = true,
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
      request.fields['is_available'] = isAvailable.toString();
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: imageFile.name));
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
              'is_available': isAvailable,
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
    XFile? imageFile,
    bool? isAvailable,
  }) async {
    if (imageFile != null) {
      var request = http.MultipartRequest('PUT', Uri.parse('$baseUrl/products/$productId/'));
      final token = await _storage.read(key: 'access_token');
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields['name'] = name;
      request.fields['description'] = description;
      request.fields['category'] = category;
      request.fields['price'] = price.toString();
      request.fields['stock_quantity'] = stockQuantity.toString();
      if (isAvailable != null) request.fields['is_available'] = isAvailable.toString();
      final bytes = await imageFile.readAsBytes();
      request.files.add(http.MultipartFile.fromBytes('image', bytes, filename: imageFile.name));
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw ApiException(_messageFrom(response, fallback: 'Failed to update product'));
    } else {
      final response = await _send((h) => http.put(
            Uri.parse('$baseUrl/products/$productId/'),
            headers: h,
            body: jsonEncode({
              'name': name,
              'description': description,
              'category': category,
              'price': price,
              'stock_quantity': stockQuantity,
              if (isAvailable != null) 'is_available': isAvailable,
            }),
          ));
      if (response.statusCode == 200) return jsonDecode(response.body);
      throw ApiException(_messageFrom(response, fallback: 'Failed to update product'));
    }
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
    return _fetchAllPages('/orders/');
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
    final imgBytes = await image.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes('image', imgBytes, filename: image.name));
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
    // The weather endpoint requires authentication (it is rate-limited and
    // cached server-side). It must go through `_send` so the JWT is attached
    // (and transparently refreshed on 401) — using `_headers` (no token) here
    // always returns 401 and broke the app's weather widget.
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/weather/'),
          headers: h,
          body: jsonEncode({
            if (lat != null) 'latitude': lat,
            if (lon != null) 'longitude': lon,
            if (location != null) 'location': location,
          }),
        )).timeout(const Duration(seconds: 15));
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
    // The health endpoint is mounted at /api/health/. baseUrl already ends in
    // `/api`, so append directly. (Previously this stripped `/api` and hit
    // `/health/`, which does not exist -> always reported "Service unhealthy".)
    final response = await http
        .get(Uri.parse('$baseUrl/health/'))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Service unhealthy'));
  }

  // ── IoT sensors & irrigation (Phase F, innovation #2) ─
  Future<Map<String, dynamic>> registerSensor({
    required String deviceId,
    required String sensorType,
    String name = '',
    String crop = '',
    double? latitude,
    double? longitude,
  }) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/sensors/'),
          headers: h,
          body: jsonEncode({
            'device_id': deviceId,
            'sensor_type': sensorType,
            if (name.isNotEmpty) 'name': name,
            if (crop.isNotEmpty) 'crop': crop,
            if (latitude != null) 'latitude': latitude,
            if (longitude != null) 'longitude': longitude,
          }),
        ));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to register sensor'));
  }

  Future<void> ingestReading(int sensorId, double value, {String? unit}) async {
    final response = await _send((h) => http.post(
          Uri.parse('$baseUrl/sensors/$sensorId/ingest/'),
          headers: h,
          body: jsonEncode({'value': value, if (unit != null) 'unit': unit}),
        ));
    if (response.statusCode != 201) {
      throw ApiException(_messageFrom(response, fallback: 'Failed to send reading'));
    }
  }

  Future<Map<String, dynamic>> getIrrigationAdvice(int sensorId, {String? crop}) async {
    final query = crop != null ? '?crop=$crop' : '';
    final response = await _send((h) =>
        http.get(Uri.parse('$baseUrl/sensors/$sensorId/irrigation_advice/$query'), headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load irrigation advice'));
  }

  Future<List<dynamic>> getMySensors() async {
    final response = await _send((h) => http.get(Uri.parse('$baseUrl/sensors/'), headers: h));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw ApiException(_messageFrom(response, fallback: 'Failed to load sensors'));
  }

  // ── Outbreak alerts (Phase F, innovation #4) ──────────
  Future<Map<String, dynamic>> getOutbreaks({String? status, String? q}) async {
    final params = <String, String>{
      if (status != null && status.isNotEmpty) 'status': status,
      if (q != null && q.isNotEmpty) 'q': q,
    };
    final uri = Uri.parse('$baseUrl/admin/outbreaks/')
        .replace(queryParameters: params.isEmpty ? null : params);
    final response = await _send((h) => http.get(uri, headers: h));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw ApiException(_messageFrom(response, fallback: 'Failed to load outbreaks'));
  }

  /// Fetch a paginated endpoint page by page until every record is collected.
  /// The admin console needs the full dataset (users, orders, ...), not just
  /// the first PAGE_SIZE=20 results.
  Future<List<dynamic>> _fetchAllPages(String path) async {
    final results = <dynamic>[];
    var page = 1;
    while (true) {
      final sep = path.contains('?') ? '&' : '?';
      final response = await _send(
          (h) => http.get(Uri.parse('$baseUrl$path${sep}page=$page'), headers: h));
      if (response.statusCode != 200) {
        throw ApiException(
            _messageFrom(response, fallback: 'Failed to load data'));
      }
      final data = jsonDecode(response.body);
      if (data is List) return data;
      results.addAll(data['results'] ?? []);
      final next = data['next'];
      if (next == null || next is! String || next.isEmpty) break;
      page++;
    }
    return results;
  }

  Future<List<dynamic>> getUsers() async {
    return _fetchAllPages('/users/');
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
    return _fetchAllPages('/announcements/');
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

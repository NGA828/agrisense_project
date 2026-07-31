import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user.dart';
import '../../models/diagnosis.dart';
import '../../models/product.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000/api';
  static const String mediaUrl = 'http://localhost:8000/media';
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  
  Map<String, String> get _headers => {'Content-Type': 'application/json'};
  
  Future<Map<String, String>> get _authHeaders async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── Auth ──────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login/'),
      headers: _headers,
      body: jsonEncode({'username': username, 'password': password}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _storage.write(key: 'access_token', value: data['access']);
      await _storage.write(key: 'refresh_token', value: data['refresh']);
      return data;
    }
    throw Exception('Login failed: ${response.body}');
  }

  Future<void> register({
    required String username, required String password,
    required String firstName, required String lastName,
    required String email, required String phoneNumber,
    required String role,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register/'),
      headers: _headers,
      body: jsonEncode({
        'username': username, 'password': password,
        'first_name': firstName, 'last_name': lastName,
        'email': email, 'phone_number': phoneNumber, 'role': role,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) throw Exception('Registration failed: ${response.body}');
  }

  Future<User> getCurrentUser() async {
    final response = await http.get(Uri.parse('$baseUrl/users/me/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return User.fromJson(jsonDecode(response.body));
    throw Exception('Failed to load user');
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // ── Diagnosis ─────────────────────────────────────────
  Future<Diagnosis> analyzePlantImageBytes(Uint8List imageBytes, String fileName, String cropType) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/diagnosis/analyze/'));
    request.headers.addAll(await _authHeaders);
    request.files.add(http.MultipartFile.fromBytes('image', imageBytes, filename: fileName));
    request.fields['crop_type'] = cropType;
    final response = await request.send().timeout(const Duration(seconds: 30));
    final responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) return Diagnosis.fromJson(jsonDecode(responseData.body));
    throw Exception('Analysis failed: ${responseData.body}');
  }

  Future<List<Diagnosis>> getDiagnosisHistory() async {
    final response = await http.get(Uri.parse('$baseUrl/diagnosis/history/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).map((j) => Diagnosis.fromJson(j)).toList();
    }
    throw Exception('Failed to load history');
  }

  // ── Products ──────────────────────────────────────────
  Future<List<Product>> getMarketplaceProducts({String? category}) async {
    String url = '$baseUrl/products/marketplace/';
    if (category != null && category != 'All') url += '?category=$category';
    final response = await http.get(Uri.parse(url), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List).map((j) => Product.fromJson(j)).toList();
    }
    throw Exception('Failed to load products');
  }

  Future<Product> getProduct(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/products/$id/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return Product.fromJson(jsonDecode(response.body));
    throw Exception('Failed to load product');
  }

  // ── Orders ────────────────────────────────────────────
  Future<Map<String, dynamic>> createOrder(int productId, int quantity) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/'),
      headers: await _authHeaders,
      body: jsonEncode({'product': productId, 'quantity': quantity}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw Exception('Failed to create order: ${response.body}');
  }

  Future<List<dynamic>> getOrders() async {
    final response = await http.get(Uri.parse('$baseUrl/orders/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load orders');
  }

  // ── Chat ──────────────────────────────────────────────
  Future<List<dynamic>> getChatRooms() async {
    final response = await http.get(Uri.parse('$baseUrl/chat/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load chats');
  }

  Future<List<dynamic>> getChatMessages(int roomId) async {
    final response = await http.get(Uri.parse('$baseUrl/chat/$roomId/messages/'), headers: await _authHeaders)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load messages');
  }

  Future<Map<String, dynamic>> sendMessage(int roomId, String content) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat/$roomId/send_message/'),
      headers: await _authHeaders,
      body: jsonEncode({'content': content}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw Exception('Failed to send message: ${response.body}');
  }

  Future<Map<String, dynamic>> sendImageMessage(int roomId, XFile image) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/chat/$roomId/send_message/'));
    request.headers.addAll(await _authHeaders);
    request.files.add(await http.MultipartFile.fromPath('image', image.path));
    final response = await request.send().timeout(const Duration(seconds: 30));
    final responseData = await http.Response.fromStream(response);
    if (response.statusCode == 201) return jsonDecode(responseData.body);
    throw Exception('Failed to send image: ${responseData.body}');
  }

  // ── Payments ──────────────────────────────────────────
  Future<Map<String, dynamic>> createPayment(int orderId, String method, String phoneNumber, double amount) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/'),
      headers: await _authHeaders,
      body: jsonEncode({
        'order': orderId,
        'payment_method': method,
        'phone_number': phoneNumber,
        'amount': amount,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 201) return jsonDecode(response.body);
    throw Exception('Failed to create payment: ${response.body}');
  }

  Future<Map<String, dynamic>> processPayment(int paymentId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/$paymentId/process_payment/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to process payment: ${response.body}');
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
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load weather: ${response.body}');
  }

  // ── Admin ────────────────────────────────────────────
  Future<Map<String, dynamic>> getAdminStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/stats/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load admin stats: ${response.body}');
  }

  Future<List<dynamic>> getUsers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data is List ? data : (data['results'] ?? []);
    }
    throw Exception('Failed to load users');
  }

  Future<void> suspendUser(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/suspend/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to suspend user');
  }

  Future<void> activateUser(int userId) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/activate/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to activate user');
  }

  Future<List<dynamic>> getDiseases() async {
    final response = await http.get(
      Uri.parse('$baseUrl/diseases/list_diseases/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load diseases');
  }

  // ── Products (Dealer) ────────────────────────────────
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
      request.headers.addAll(await _authHeaders);
      request.fields['name'] = name;
      request.fields['description'] = description;
      request.fields['category'] = category;
      request.fields['price'] = price.toString();
      request.fields['stock_quantity'] = stockQuantity.toString();
      request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));
      final response = await request.send().timeout(const Duration(seconds: 30));
      final responseData = await http.Response.fromStream(response);
      if (response.statusCode == 201) return jsonDecode(responseData.body);
      throw Exception('Failed to add product: ${responseData.body}');
    } else {
      final response = await http.post(
        Uri.parse('$baseUrl/products/'),
        headers: await _authHeaders,
        body: jsonEncode({
          'name': name,
          'description': description,
          'category': category,
          'price': price,
          'stock_quantity': stockQuantity,
        }),
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode == 201) return jsonDecode(response.body);
      throw Exception('Failed to add product: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> updateProduct(int productId, {
    required String name,
    required String description,
    required String category,
    required double price,
    required int stockQuantity,
  }) async {
    final response = await http.put(
      Uri.parse('$baseUrl/products/$productId/'),
      headers: await _authHeaders,
      body: jsonEncode({
        'name': name,
        'description': description,
        'category': category,
        'price': price,
        'stock_quantity': stockQuantity,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to update product: ${response.body}');
  }

  Future<void> deleteProduct(int productId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/products/$productId/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 204) throw Exception('Failed to delete product');
  }

  // ── Premium ────────────────────────────────────────────
  Future<Map<String, dynamic>> upgradePremium(int userId, {int durationMonths = 1}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/upgrade_premium/'),
      headers: await _authHeaders,
      body: jsonEncode({'duration_months': durationMonths}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to upgrade to premium: ${response.body}');
  }

  // ── Announcements ─────────────────────────────────────
  Future<List<dynamic>> getAnnouncements() async {
    final response = await http.get(
      Uri.parse('$baseUrl/announcements/active/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load announcements');
  }

  // ── Disease CRUD (Admin) ──────────────────────
  Future<void> addDisease({
    required String cropName,
    required String diseaseName,
    required String pathogen,
    required String symptoms,
    required String severity,
    required String medication,
    required String instructions,
    required String treatmentType,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/diseases/add_disease/'),
      headers: await _authHeaders,
      body: jsonEncode({
        'crop_name': cropName,
        'disease_name': diseaseName,
        'pathogen': pathogen,
        'symptoms': symptoms,
        'severity': severity,
        'medication': medication,
        'instructions': instructions,
        'treatment_type': treatmentType,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) throw Exception('Failed to add disease: ${response.body}');
  }

  Future<void> updateDisease(String diseaseId, {
    String? cropName,
    String? diseaseName,
    String? pathogen,
    String? symptoms,
    String? severity,
    String? medication,
    String? instructions,
    String? treatmentType,
  }) async {
    final body = <String, dynamic>{};
    if (cropName != null) body['crop_name'] = cropName;
    if (diseaseName != null) body['disease_name'] = diseaseName;
    if (pathogen != null) body['pathogen'] = pathogen;
    if (symptoms != null) body['symptoms'] = symptoms;
    if (severity != null) body['severity'] = severity;
    if (medication != null) body['medication'] = medication;
    if (instructions != null) body['instructions'] = instructions;
    if (treatmentType != null) body['treatment_type'] = treatmentType;
    final response = await http.put(
      Uri.parse('$baseUrl/diseases/$diseaseId/'),
      headers: await _authHeaders,
      body: jsonEncode(body),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to update disease: ${response.body}');
  }

  Future<void> deleteDisease(String diseaseId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/diseases/$diseaseId/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 204) throw Exception('Failed to delete disease');
  }

  // ── Dealer Verification ──────────────────────
  Future<List<dynamic>> getPendingDealers() async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/dealer_requests/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load dealer requests');
  }

  Future<void> verifyDealer(int userId, bool approve) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/$userId/verify_dealer/'),
      headers: await _authHeaders,
      body: jsonEncode({'approve': approve}),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) throw Exception('Failed to verify dealer');
  }

  // ── Announcements (Admin) ──────────────────────
  Future<List<dynamic>> getAllAnnouncements() async {
    final response = await http.get(
      Uri.parse('$baseUrl/announcements/'),
      headers: await _authHeaders,
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) return jsonDecode(response.body);
    throw Exception('Failed to load all announcements');
  }

  Future<void> createAnnouncement({
    required String title,
    required String content,
    required String targetAudience,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/announcements/'),
      headers: await _authHeaders,
      body: jsonEncode({
        'title': title,
        'content': content,
        'target_audience': targetAudience,
      }),
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 201) throw Exception('Failed to create announcement: ${response.body}');
  }
}

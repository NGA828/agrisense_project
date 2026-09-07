import 'dart:convert';
import 'dart:typed_data';

import 'package:agrisense_app/services/api/api_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> diagnosisJson(String crop) => {
  'id': 'scan-1', 'user_email': 'farmer@example.test', 'crop_type': crop,
  'image': '', 'symptoms': '', 'confidence': '88.00', 'disease_name': 'Healthy',
  'severity': 'low', 'causes': '', 'prevention': 'Monitor regularly',
  'is_healthy': true, 'is_inconclusive': false, 'engine': 'openrouter-vision',
  'trained_model': true, 'created_at': '2026-09-06T10:00:00Z',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String originalBaseUrl;
  setUp(() {
    originalBaseUrl = ApiService.baseUrl;
    ApiService.baseUrl = 'https://agrisense.example.test/api';
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'expired-access', 'refresh_token': 'test-refresh',
    });
  });
  tearDown(() => ApiService.baseUrl = originalBaseUrl);

  test('multipart scans refresh JWT and keep the selected crop/photo', () async {
    var uploads = 0;
    await http.runWithClient(() async {
      final result = await ApiService().analyzePlantImageBytes(
          Uint8List.fromList([1, 2, 3]), 'leaf.png', 'Maize');
      expect(result.cropType, 'Maize');
      expect(uploads, 2);
    }, () => MockClient((request) async {
      if (request.url.path.endsWith('/auth/refresh/')) {
        return http.Response(jsonEncode({'access': 'fresh-access'}), 200);
      }
      uploads++;
      expect(request.url.path, '/api/diagnosis/analyze/');
      expect(request.body, contains('name="crop_type"'));
      expect(request.body, contains('Maize'));
      expect(request.body, contains('filename="leaf.png"'));
      if (uploads == 1) {
        expect(request.headers['authorization'], 'Bearer expired-access');
        return http.Response('{"detail":"Token expired"}', 401);
      }
      expect(request.headers['authorization'], 'Bearer fresh-access');
      return http.Response(jsonEncode(diagnosisJson('Maize')), 201);
    }));
  });

  test('cached scan HTTP 200 is accepted', () async {
    await http.runWithClient(() async {
      final result = await ApiService().analyzePlantImageBytes(Uint8List(3), 'leaf.png', 'Tomato');
      expect(result.id, 'scan-1');
    }, () => MockClient((_) async => http.Response(jsonEncode(diagnosisJson('Tomato')), 200)));
  });

  test('a result for another crop is never shown', () async {
    await http.runWithClient(() async {
      await expectLater(
        ApiService().analyzePlantImageBytes(Uint8List(3), 'leaf.png', 'Maize'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'crop_mismatch')),
      );
    }, () => MockClient((_) async => http.Response(jsonEncode(diagnosisJson('Tomato')), 201)));
  });

  test('non-crop rejection retains an actionable error code', () async {
    await http.runWithClient(() async {
      await expectLater(
        ApiService().analyzePlantImageBytes(Uint8List(3), 'image.png', 'Tomato'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'not_a_crop')),
      );
    }, () => MockClient((_) async => http.Response(
        '{"error":"Upload a real crop photo","code":"not_a_crop"}', 422)));
  });

  test('collection sends the displayed amount for server-side confirmation', () async {
    await http.runWithClient(() async {
      final payment = await ApiService().processPayment(9, expectedAmount: 2000);
      expect(payment['status'], 'processing');
    }, () => MockClient((request) async {
      expect((jsonDecode(request.body) as Map)['expected_amount'], '2000.00');
      return http.Response('{"id":9,"status":"processing"}', 200);
    }));
  });

  test('checkout retry sends the same token and accepts reused order/attempt', () async {
    const key = '746061e2-3119-40dd-8076-911688254928';
    await http.runWithClient(() async {
      final api = ApiService();
      final order = await api.createOrder(12, 2, checkoutKey: key, paymentMethod: 'MTN_MOMO');
      expect(order['id'], 7);
      final payment = await api.createPayment(7, 'MTN_MOMO', '670000008', 2000);
      expect(payment['id'], 9);
      expect(payment['status'], 'processing');
    }, () => MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      if (request.url.path.endsWith('/orders/')) {
        expect(body['checkout_key'], key);
        expect(body['payment_method'], 'MTN_MOMO');
        return http.Response('{"id":7,"total_price":"2000.00"}', 200);
      }
      expect(body['order'], 7);
      expect(body['amount'], 2000);
      return http.Response('{"id":9,"status":"processing"}', 200);
    }));
  });
}

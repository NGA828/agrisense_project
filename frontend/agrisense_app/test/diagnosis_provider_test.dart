import 'dart:async';
import 'dart:typed_data';

import 'package:agrisense_app/models/diagnosis.dart';
import 'package:agrisense_app/providers/diagnosis_provider.dart';
import 'package:agrisense_app/services/api/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

Diagnosis result({String crop = 'Tomato'}) => Diagnosis(
  id: 'same-scan', userEmail: 'farmer@example.test', cropType: crop, imageUrl: '',
  symptoms: '', confidence: 88, diseaseName: 'Healthy', severity: 'low',
  causes: '', prevention: '', isHealthy: true, trainedModel: true,
  engine: 'ollama-vision', createdAt: DateTime(2026, 9, 6),
);

class FakeScanApi extends ApiService {
  int calls = 0;
  Future<Diagnosis> Function(String crop) respond = (_) async => result();
  @override
  Future<Diagnosis> analyzePlantImageBytes(Uint8List image, String fileName, String cropType) {
    calls++;
    return respond(cropType);
  }
}

void main() {
  test('double tap starts one analysis, not two overlapping requests', () async {
    final api = FakeScanApi();
    final pending = Completer<Diagnosis>();
    api.respond = (_) => pending.future;
    final provider = DiagnosisProvider(api: api);
    addTearDown(provider.dispose);
    final first = provider.analyzeImage(Uint8List(3), 'leaf.png', 'Tomato');
    final second = await provider.analyzeImage(Uint8List(3), 'leaf.png', 'Maize');
    expect(second, isNull);
    expect(api.calls, 1);
    pending.complete(result());
    expect((await first)?.cropType, 'Tomato');
    expect(provider.isLoading, isFalse);
  });

  test('wrong-crop result is discarded, not placed in history', () async {
    final api = FakeScanApi();
    final provider = DiagnosisProvider(api: api);
    addTearDown(provider.dispose);
    expect(await provider.analyzeImage(Uint8List(3), 'leaf.png', 'Maize'), isNull);
    expect(provider.errorCode, 'crop_mismatch');
    expect(provider.currentDiagnosis, isNull);
    expect(provider.history, isEmpty);
  });

  test('cached results are not duplicated in local history', () async {
    final provider = DiagnosisProvider(api: FakeScanApi());
    addTearDown(provider.dispose);
    await provider.analyzeImage(Uint8List(3), 'leaf.png', 'Tomato');
    await provider.analyzeImage(Uint8List(3), 'leaf.png', 'Tomato');
    expect(provider.history.length, 1);
  });

  test('timeout clears loading and previous result without fabricating a diagnosis', () async {
    final api = FakeScanApi();
    final provider = DiagnosisProvider(api: api);
    addTearDown(provider.dispose);
    await provider.analyzeImage(Uint8List(3), 'leaf.png', 'Tomato');
    api.respond = (_) async => throw TimeoutException('test timeout');
    expect(await provider.analyzeImage(Uint8List(3), 'new.png', 'Tomato'), isNull);
    expect(provider.isLoading, isFalse);
    expect(provider.currentDiagnosis, isNull);
    expect(provider.errorCode, 'ai_timeout');
    expect(provider.history.length, 1);
  });
}

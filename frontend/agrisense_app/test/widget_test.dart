import 'package:flutter_test/flutter_test.dart';
import 'package:agrisense_app/main.dart';

void main() {
  testWidgets('App starts correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const AgriSenseApp());
    expect(find.text('AgriSense AI'), findsOneWidget);
  });
}

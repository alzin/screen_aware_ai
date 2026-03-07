import 'package:flutter_test/flutter_test.dart';
import 'package:screen_aware_ai/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const ScreenAwareApp());
    expect(find.text('Screen Aware AI'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_aware_ai/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const LucyApp());
    expect(find.text('Lucy'), findsOneWidget);
  });
}

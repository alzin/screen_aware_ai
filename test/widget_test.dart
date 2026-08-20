import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:screen_aware_ai/main.dart';

/// The method channel that fronts the Kotlin screen-capture and
/// accessibility services. None of those exist in a test environment, so
/// every widget test has to stand in for them.
const MethodChannel _screenChannel = MethodChannel(
  'com.poc.screen_aware_ai/screen',
);

/// Answer [_screenChannel] calls with canned results.
///
/// [accessibilityEnabled] decides whether the app renders its
/// "Accessibility Required" gate or the main conversation screen.
void _mockScreenChannel({required bool accessibilityEnabled}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_screenChannel, (call) async {
        switch (call.method) {
          case 'isAccessibilityEnabled':
            return accessibilityEnabled;
          case 'getScreenSize':
            return <String, int>{'width': 1080, 'height': 2400};
          case 'requestScreenCapture':
          case 'openApp':
          case 'performTap':
          case 'performType':
          case 'performSwipe':
          case 'pressBack':
          case 'pressHome':
          case 'showStopOverlay':
            return false;
          default:
            return null;
        }
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_screenChannel, null);
  });

  testWidgets('shows the accessibility gate when the service is off', (
    tester,
  ) async {
    _mockScreenChannel(accessibilityEnabled: false);

    await tester.pumpWidget(const LucyApp());
    await tester.pumpAndSettle();

    expect(find.text('Accessibility Required'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('shows the main screen when accessibility is enabled', (
    tester,
  ) async {
    _mockScreenChannel(accessibilityEnabled: true);

    await tester.pumpWidget(const LucyApp());
    await tester.pumpAndSettle();

    expect(find.text('Lucy'), findsOneWidget);
    expect(find.text('Accessibility Required'), findsNothing);
  });
}

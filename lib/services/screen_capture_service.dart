import 'package:flutter/services.dart';

class ScreenCaptureManager {
  static const _channel = MethodChannel('com.poc.screen_aware_ai/screen');

  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;

  /// Callback fired when the native stop notification action is tapped.
  VoidCallback? onForceStop;

  bool _handlerRegistered = false;

  /// Ensure the reverse method call handler is registered (native → Dart).
  void _ensureHandler() {
    if (_handlerRegistered) return;
    _handlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onForceStop') {
        onForceStop?.call();
      }
    });
  }

  /// Request screen capture permission (shows system dialog)
  Future<bool> requestPermission() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestScreenCapture');
      _hasPermission = result ?? false;
      return _hasPermission;
    } catch (e) {
      print('Error requesting screen capture: $e');
      return false;
    }
  }

  /// Capture the current screen and return the file path.
  /// Automatically handles reinitialization if the capture service
  /// lost its projection (e.g., after app switch or service restart).
  Future<String?> captureScreen() async {
    if (!_hasPermission) {
      final granted = await requestPermission();
      if (!granted) return null;
    }

    try {
      final path = await _channel.invokeMethod<String>('captureScreen');
      return path;
    } on PlatformException catch (e) {
      if (e.code == 'NOT_INITIALIZED') {
        // Service exists but lost its MediaProjection — wait for
        // reinitialization (MainActivity attempts it automatically)
        // then retry once.
        print('Screen capture not initialized, waiting and retrying...');
        await Future.delayed(const Duration(milliseconds: 800));
        try {
          final path = await _channel.invokeMethod<String>('captureScreen');
          return path;
        } on PlatformException catch (retryError) {
          if (retryError.code == 'NOT_INITIALIZED' ||
              retryError.code == 'NO_SERVICE') {
            // Reinitialization failed — need fresh permission grant
            print('Reinitialization failed, re-requesting permission...');
            _hasPermission = false;
            final granted = await requestPermission();
            if (!granted) return null;
            // Final attempt after fresh permission
            try {
              final path = await _channel.invokeMethod<String>('captureScreen');
              return path;
            } catch (finalError) {
              print('Final capture attempt failed: $finalError');
              return null;
            }
          }
          print('Retry capture failed: $retryError');
          return null;
        }
      } else if (e.code == 'NO_SERVICE') {
        // Service not running at all — request permission to start it
        print('Screen capture service not running, requesting permission...');
        _hasPermission = false;
        final granted = await requestPermission();
        if (!granted) return null;
        try {
          final path = await _channel.invokeMethod<String>('captureScreen');
          return path;
        } catch (retryError) {
          print('Capture after permission re-request failed: $retryError');
          return null;
        }
      }
      print('Error capturing screen: $e');
      return null;
    } catch (e) {
      print('Error capturing screen: $e');
      return null;
    }
  }

  /// Get the UI tree of the current foreground app via accessibility service.
  /// Returns a JSON string with package name and element list, or null on error.
  Future<String?> getUITree() async {
    try {
      final result = await _channel.invokeMethod<String>('getUITree');
      return result;
    } catch (e) {
      print('Error getting UI tree: $e');
      return null;
    }
  }

  /// Check if accessibility service is enabled
  Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isAccessibilityEnabled',
      );
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Open accessibility settings
  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (e) {
      print('Error opening settings: $e');
    }
  }

  /// Launch an app by package name
  Future<bool> openApp(String packageName) async {
    try {
      final result = await _channel.invokeMethod<bool>('openApp', {
        'packageName': packageName,
      });
      return result ?? false;
    } catch (e) {
      print('Error opening app: $e');
      return false;
    }
  }

  /// Perform a tap at the given coordinates
  Future<bool> performTap(double x, double y) async {
    try {
      final result = await _channel.invokeMethod<bool>('performTap', {
        'x': x,
        'y': y,
      });
      return result ?? false;
    } catch (e) {
      print('Error performing tap: $e');
      return false;
    }
  }

  /// Type text into the currently focused input
  Future<bool> performType(String text) async {
    try {
      final result = await _channel.invokeMethod<bool>('performType', {
        'text': text,
      });
      return result ?? false;
    } catch (e) {
      print('Error performing type: $e');
      return false;
    }
  }

  /// Perform a swipe gesture
  Future<bool> performSwipe(
    double startX,
    double startY,
    double endX,
    double endY,
  ) async {
    try {
      final result = await _channel.invokeMethod<bool>('performSwipe', {
        'startX': startX,
        'startY': startY,
        'endX': endX,
        'endY': endY,
      });
      return result ?? false;
    } catch (e) {
      print('Error performing swipe: $e');
      return false;
    }
  }

  /// Press back button
  Future<bool> pressBack() async {
    try {
      final result = await _channel.invokeMethod<bool>('pressBack');
      return result ?? false;
    } catch (e) {
      print('Error pressing back: $e');
      return false;
    }
  }

  /// Get the screen size in pixels
  Future<Map<String, int>?> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        return {
          'width': result['width'] as int,
          'height': result['height'] as int,
        };
      }
      return null;
    } catch (e) {
      print('Error getting screen size: $e');
      return null;
    }
  }

  /// Press home button
  Future<bool> pressHome() async {
    try {
      final result = await _channel.invokeMethod<bool>('pressHome');
      return result ?? false;
    } catch (e) {
      print('Error pressing home: $e');
      return false;
    }
  }

  /// Delete all saved screenshots
  Future<void> clearScreenshots() async {
    try {
      await _channel.invokeMethod('clearScreenshots');
    } catch (e) {
      print('Error clearing screenshots: $e');
    }
  }

  // ─── Stop controls ──────────────────────────────────────────────────

  /// Show the persistent stop notification while Lucy is active.
  Future<bool> showStopOverlay() async {
    _ensureHandler();
    try {
      final result = await _channel.invokeMethod<bool>('showStopOverlay');
      return result ?? false;
    } catch (e) {
      print('Error showing stop controls: $e');
      return false;
    }
  }

  /// Hide the persistent stop notification.
  Future<void> hideStopOverlay() async {
    try {
      await _channel.invokeMethod('hideStopOverlay');
    } catch (e) {
      print('Error hiding stop controls: $e');
    }
  }
}

import 'package:flutter/services.dart';

class ScreenCaptureManager {
  static const _channel = MethodChannel('com.poc.screen_aware_ai/screen');

  bool _hasPermission = false;
  bool get hasPermission => _hasPermission;

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

  /// Capture the current screen and return the file path
  Future<String?> captureScreen() async {
    if (!_hasPermission) {
      final granted = await requestPermission();
      if (!granted) return null;
    }

    try {
      final path = await _channel.invokeMethod<String>('captureScreen');
      return path;
    } catch (e) {
      print('Error capturing screen: $e');
      return null;
    }
  }

  /// Check if accessibility service is enabled
  Future<bool> isAccessibilityEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
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
  Future<bool> performSwipe(double startX, double startY, double endX, double endY) async {
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
}

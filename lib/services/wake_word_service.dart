import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:porcupine_flutter/porcupine_error.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Top-level callback required by flutter_foreground_task.
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(WakeWordTaskHandler());
}

/// Minimal TaskHandler — keeps the foreground service alive.
/// Porcupine runs in the main isolate, not here.
class WakeWordTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

class WakeWordService {
  static const String _prefKeyEnabled = 'wake_word_enabled';
  static const String _prefKeyAccessKey = 'picovoice_access_key';
  static const String _ppnAsset = 'assets/wake_word/Hey-Lucy_en_android_v4_0_0.ppn';

  PorcupineManager? _porcupineManager;
  bool _isListening = false;
  bool _isEnabled = false;
  bool _isForegroundTaskRunning = false;
  String? _accessKey;

  bool get isListening => _isListening;
  bool get isEnabled => _isEnabled;
  bool get isAccessKeySet => _accessKey != null && _accessKey!.isNotEmpty;

  /// Called when the wake word is detected.
  VoidCallback? onWakeWordDetected;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(_prefKeyEnabled) ?? false;
    _accessKey = prefs.getString(_prefKeyAccessKey);
    _initForegroundTask();
  }

  Future<void> setAccessKey(String key) async {
    _accessKey = key;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyAccessKey, key);
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wake_word_channel',
        channelName: 'Wake Word Detection',
        channelDescription: 'Listening for "Hey Lucy" wake word.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
  }

  /// Toggle wake word on/off (called from UI).
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyEnabled, enabled);

    if (enabled) {
      await startListening();
    } else {
      await stopCompletely();
    }
  }

  /// Copy the .ppn model from Flutter assets to a file on disk,
  /// since Porcupine needs an absolute file path.
  Future<String> _getKeywordPath() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Hey-Lucy_en_android.ppn');
    if (!await file.exists()) {
      final data = await rootBundle.load(_ppnAsset);
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  /// Start listening for the wake word.
  Future<void> startListening() async {
    if (_isListening) return;
    if (!isAccessKeySet) {
      debugPrint('WakeWordService: No Picovoice access key set');
      return;
    }

    try {
      // Start foreground service to keep process alive
      if (!_isForegroundTaskRunning) {
        await FlutterForegroundTask.startService(
          serviceId: 200,
          notificationTitle: 'Lucy is listening',
          notificationText: 'Say "Hey Lucy" to activate',
          callback: startCallback,
        );
        _isForegroundTaskRunning = true;
      }

      final keywordPath = await _getKeywordPath();

      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _accessKey!,
        [keywordPath],
        _onDetected,
        errorCallback: _onError,
      );

      await _porcupineManager!.start();
      _isListening = true;
      debugPrint('WakeWordService: Started listening for "Hey Lucy"');
    } on PorcupineException catch (e) {
      debugPrint('WakeWordService: Porcupine error: ${e.message}');
      _isListening = false;
    } catch (e) {
      debugPrint('WakeWordService: Error starting: $e');
      _isListening = false;
    }
  }

  /// Stop listening but keep the foreground service alive (for quick resume).
  Future<void> stopListening() async {
    if (!_isListening) return;

    try {
      await _porcupineManager?.stop();
      await _porcupineManager?.delete();
      _porcupineManager = null;
      _isListening = false;
      debugPrint('WakeWordService: Stopped listening');
    } catch (e) {
      debugPrint('WakeWordService: Error stopping: $e');
    }
  }

  /// Fully stop: Porcupine + foreground service.
  Future<void> stopCompletely() async {
    await stopListening();

    if (_isForegroundTaskRunning) {
      await FlutterForegroundTask.stopService();
      _isForegroundTaskRunning = false;
    }
  }

  void _onDetected(int keywordIndex) {
    debugPrint('WakeWordService: Wake word detected! (index=$keywordIndex)');
    FlutterForegroundTask.launchApp();
    onWakeWordDetected?.call();
  }

  void _onError(PorcupineException error) {
    debugPrint('WakeWordService: Porcupine error: ${error.message}');
  }

  void dispose() {
    stopCompletely();
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'ai_service.dart';
import 'voice_service.dart';
import 'screen_capture_service.dart';

enum AgentState {
  idle,
  listening,
  capturing,
  analyzing,
  speaking,
  waitingConfirmation,
  executingAction,
}

class ConversationEntry {
  final String text;
  final bool isUser;
  final Uint8List? screenshotBytes;
  final DateTime timestamp;

  ConversationEntry({
    required this.text,
    required this.isUser,
    this.screenshotBytes,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class _UiSnapshot {
  final String? rawTree;
  final String? packageName;
  final List<Map<String, dynamic>> elements;
  final bool hasFocusedEditable;

  const _UiSnapshot({
    required this.rawTree,
    required this.packageName,
    required this.elements,
    required this.hasFocusedEditable,
  });

  String get signature => rawTree ?? '';
}

class AgentController extends ChangeNotifier {
  final AiService _aiService = AiService();
  final VoiceService _voiceService = VoiceService();
  final ScreenCaptureManager _screenCapture = ScreenCaptureManager();

  AgentState _state = AgentState.idle;
  AgentState get state => _state;

  final List<ConversationEntry> _conversation = [];
  List<ConversationEntry> get conversation => List.unmodifiable(_conversation);

  String _statusMessage =
      'I can see your screen and help you interact with apps';
  String get statusMessage => _statusMessage;

  Uint8List? _lastScreenshotBytes;
  Uint8List? get lastScreenshotBytes => _lastScreenshotBytes;

  String? _currentTranscript = '';
  String? get currentTranscript => _currentTranscript;

  bool _isActive = false;
  bool get isActive => _isActive;

  int _listenRetryCount = 0;
  static const int _maxListenRetries = 3;

  static const int _maxStepsPerCommand = 10;
  static const Duration _tapReadyTimeout = Duration(milliseconds: 900);
  static const Duration _typeReadyTimeout = Duration(milliseconds: 900);
  static const Duration _navigationReadyTimeout = Duration(milliseconds: 1200);
  static const Duration _openAppReadyTimeout = Duration(milliseconds: 2500);

  bool _cancelRequested = false;

  bool _isAskingForFurtherHelp = false;
  bool? _cachedAccessibilityEnabled;

  AiService get aiService => _aiService;
  ScreenCaptureManager get screenCapture => _screenCapture;

  /// Whether a cancel has been requested by the user.
  bool get cancelRequested => _cancelRequested;

  Future<bool> _getAccessibilityEnabled({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAccessibilityEnabled != null) {
      return _cachedAccessibilityEnabled!;
    }

    final isEnabled = await _screenCapture.isAccessibilityEnabled();
    _cachedAccessibilityEnabled = isEnabled;
    return isEnabled;
  }

  Future<bool> _ensureAccessibilityEnabled() async {
    final isEnabled = await _getAccessibilityEnabled();
    if (isEnabled) {
      return true;
    }

    return _getAccessibilityEnabled(forceRefresh: true);
  }

  /// Force-stop the current agent loop immediately.
  void requestCancel() {
    _cancelRequested = true;
    _voiceService.stopSpeaking();
    notifyListeners();
  }

  Future<void> initialize() async {
    await _voiceService.initialize();

    // Wire native stop notification action → requestCancel
    _screenCapture.onForceStop = () {
      if (_isActive) {
        requestCancel();
      }
    };

    _voiceService.onResult = (text, isFinal) {
      _currentTranscript = text;
      if (isFinal && text.isNotEmpty) {
        _handleUserInput(text);
      }
      notifyListeners();
    };

    _voiceService.onListeningDone = () {
      if (_state == AgentState.listening &&
          _currentTranscript?.isEmpty == true) {
        if (_isActive) {
          _listenRetryCount++;
          if (_listenRetryCount > _maxListenRetries) {
            print(
              'Listening retry limit reached ($_maxListenRetries). Stopping.',
            );
            _listenRetryCount = 0;
            _statusMessage = 'Listening timed out. Tap to restart.';
            _setState(AgentState.idle);
            _isActive = false;
            notifyListeners();
            return;
          }
          Future.delayed(const Duration(seconds: 2), () {
            if (_isActive && _state == AgentState.listening) {
              _startListening();
            }
          });
        }
      } else {
        _listenRetryCount = 0;
      }
    };

    _voiceService.onError = (error) {
      print('Voice error: $error');
      if (_isActive && _state == AgentState.listening) {
        if (error == 'error_busy' || error == 'error_client') {
          // Avoid infinite loops if Android STT client is busy or STT dead.
          return;
        }
        Future.delayed(const Duration(seconds: 1), () {
          if (_isActive) _startListening();
        });
      }
    };
  }

  void configureAi(String apiKey) {
    _aiService.configure(apiKey);
    notifyListeners();
  }

  Future<void> toggleAgent() async {
    if (_isActive) {
      await stopAgent();
    } else {
      await startAgent();
    }
  }

  Future<void> startAgent() async {
    if (!_aiService.isConfigured) {
      _statusMessage = '⚠️ Please set your Gemini API key first';
      notifyListeners();
      return;
    }

    _isActive = true;
    _addConversation(
      'Agent started. Listening for your commands. To stop Lucy while it is in another app, open notifications and tap "Stop Lucy".',
      false,
    );
    _statusMessage = 'Listening... Open notifications to stop Lucy.';
    _isAskingForFurtherHelp = false;
    notifyListeners();

    // Request screen capture permission
    final hasScreenPermission = await _screenCapture.requestPermission();
    if (!hasScreenPermission) {
      _addConversation(
        '⚠️ Screen capture permission denied. I can still listen and talk, but cannot see the screen.',
        false,
      );
    }

    // Check if accessibility service is enabled
    final hasAccessibility = await _getAccessibilityEnabled(forceRefresh: true);
    if (!hasAccessibility) {
      _addConversation(
        '⚠️ Accessibility service not enabled. I can see the screen but cannot perform actions (tap, type, swipe). '
        'Go to Settings → Accessibility → Lucy to enable it.',
        false,
      );
    }

    _listenRetryCount = 0;
    _startListening();
  }

  Future<void> stopAgent() async {
    _isActive = false;
    _cancelRequested = false;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    _setState(AgentState.idle);
    _statusMessage = 'I can see your screen and help you interact with apps';
    _addConversation('Agent stopped.', false);
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (!_isActive) return;
    _setState(AgentState.listening);
    _statusMessage = '🎤 Listening... Open notifications to stop Lucy.';
    _currentTranscript = '';
    notifyListeners();

    await _voiceService.startListening();
  }

  /// Main handler: user says something → agent loop begins.
  Future<void> _handleUserInput(String text) async {
    if (!_isActive || _state != AgentState.listening) return;

    // Immediately change state to prevent multipleSTT events or auto-restarts
    _setState(AgentState.analyzing);
    await _voiceService.stopListening();

    _addConversation(text, true);
    _currentTranscript = '';

    if (_isAskingForFurtherHelp) {
      _isAskingForFurtherHelp = false;
      final textLower = text.trim().toLowerCase().replaceAll(
        RegExp(r'[^\w\s]'),
        '',
      );
      if (textLower.startsWith('no ') ||
          textLower == 'no' ||
          textLower == 'nope' ||
          textLower == 'nah' ||
          textLower == 'stop' ||
          textLower == 'exit' ||
          textLower == 'nothing' ||
          textLower.startsWith('not ')) {
        _setState(AgentState.speaking);
        _addConversation('Alright, stopping the agent.', false);
        await _voiceService.speak('Alright, stopping the agent.');

        await stopAgent();
        return;
      }
    }

    await _runAgentLoop(text);

    // Resume listening after the loop completes
    if (_isActive) {
      _startListening();
    }
  }

  /// The core agent loop: capture → analyze → act → repeat.
  Future<void> _runAgentLoop(String userMessage) async {
    _cancelRequested = false;
    int step = 0;
    String currentMessage = userMessage;

    // Show persistent stop notification while Lucy is active
    await _screenCapture.showStopOverlay();

    // Fetch screen size once for the whole loop
    final screenSize = await _screenCapture.getScreenSize();

    while (step < _maxStepsPerCommand && _isActive && !_cancelRequested) {
      step++;

      // 1. Capture screenshot (with retries for reliability after app switches)
      _setState(AgentState.capturing);
      _statusMessage = '📸 Capturing screen... (step $step)';
      notifyListeners();

      final screenshotFuture = _captureScreenWithRetry();
      final uiSnapshotFuture = _fetchUiSnapshot();

      final screenshotBytes = await screenshotFuture;
      if (screenshotBytes != null) {
        _lastScreenshotBytes = screenshotBytes;
      }

      if (_cancelRequested) break;

      // 1b. Fetch UI tree from accessibility service (runs in parallel-ready)
      final uiSnapshot = await uiSnapshotFuture;
      final uiTree = uiSnapshot?.rawTree;

      if (_cancelRequested) break;

      // 2. Send to AI (with screenshot + UI tree)
      _setState(AgentState.analyzing);
      _statusMessage = '🤖 Thinking... (step $step)';
      notifyListeners();

      final agentResponse = await _aiService.agentChat(
        currentMessage,
        imageBytes: screenshotBytes,
        screenSize: screenSize,
        uiTree: uiTree,
      );

      if (_cancelRequested) break;

      // Show AI response and action summary in conversation
      String speakText = agentResponse.speak;
      if (agentResponse.done) {
        if (speakText.isNotEmpty &&
            !speakText.endsWith(' ') &&
            !speakText.endsWith('\n')) {
          speakText += ' ';
        }
        speakText += 'Do you need any further help?';
        _isAskingForFurtherHelp = true;
      } else {
        _isAskingForFurtherHelp = false;
      }

      String displayText = speakText;
      if (agentResponse.actions.isNotEmpty) {
        final actionSummary = agentResponse.actions
            .map(
              (a) => '⚡ ${a.type}${a.params.isNotEmpty ? ': ${a.params}' : ''}',
            )
            .join('\n');
        displayText = displayText.isEmpty
            ? actionSummary
            : '$displayText\n\n$actionSummary';
      }
      if (displayText.trim().isNotEmpty) {
        _addConversation(displayText, false, screenshotBytes: screenshotBytes);
      }

      if (_cancelRequested) break;

      // 3. Execute actions
      if (agentResponse.actions.isNotEmpty) {
        _setState(AgentState.executingAction);
        _statusMessage = '⚡ Executing actions... (step $step)';
        notifyListeners();

        var latestSnapshot = uiSnapshot;
        for (final action in agentResponse.actions) {
          if (_cancelRequested) break;
          latestSnapshot = await _executeAction(action, latestSnapshot);
        }
      }

      if (_cancelRequested) break;

      // 4. Speak the response (only speak if done or has something to say)
      if (speakText.isNotEmpty) {
        _setState(AgentState.speaking);
        _statusMessage = '🔊 Speaking...';
        notifyListeners();

        final ttsText = _trimForTts(speakText);
        await _voiceService.speak(ttsText);
      }

      if (_cancelRequested) break;

      // 5. Check if done
      if (agentResponse.done) {
        break;
      }

      // Not done → continue the loop with a follow-up message
      currentMessage =
          'I have executed the actions. Here is the updated screen. Continue with the task.';
      // If screenshot capture might fail next iteration, the AI will still
      // receive the message but without an image. The retry logic in
      // _captureScreenWithRetry handles this by making multiple attempts.
    }

    // Always hide the stop notification when the loop ends
    await _screenCapture.hideStopOverlay();

    // Handle cancellation
    if (_cancelRequested) {
      _cancelRequested = false;
      _addConversation('🛑 Stopped by user.', false);
      return;
    }

    if (step >= _maxStepsPerCommand) {
      _addConversation(
        '⚠️ Reached maximum steps ($_maxStepsPerCommand). Stopping.',
        false,
      );
    }
  }

  /// Capture the screen with retry logic.
  /// After navigating to another app, the first capture attempt may return null
  /// because the VirtualDisplay hasn't rendered a fresh frame yet. Retrying
  /// with increasing delays ensures we eventually get a valid screenshot.
  Future<Uint8List?> _captureScreenWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final bytes = await _screenCapture.captureScreen();
        if (bytes != null) return bytes;
      } catch (e) {
        print('Screenshot capture attempt ${i + 1} failed: $e');
      }
      if (i < maxRetries - 1) {
        // Increasing delay between retries: 200ms, 400ms
        await Future.delayed(Duration(milliseconds: 200 * (i + 1)));
      }
    }
    print('All $maxRetries screenshot capture attempts failed');
    return null;
  }

  /// Resolve element ID from the UI tree to (cx, cy) coordinates.
  /// Returns null if the element is not found.
  Map<String, double>? _resolveElementCoordinates(
    int elementId,
    List<Map<String, dynamic>> uiElements,
  ) {
    final element = _findElementById(elementId, uiElements);
    if (element != null) {
      final bounds = element['bounds'] as Map<String, dynamic>?;
      if (bounds != null) {
        return {
          'x': (bounds['cx'] as num).toDouble(),
          'y': (bounds['cy'] as num).toDouble(),
        };
      }
    }
    return null;
  }

  Map<String, dynamic>? _findElementById(
    int elementId,
    List<Map<String, dynamic>> uiElements,
  ) {
    for (final element in uiElements) {
      if (element['id'] == elementId) {
        return element;
      }
    }
    return null;
  }

  Future<_UiSnapshot?> _fetchUiSnapshot() async {
    try {
      final uiTree = await _screenCapture.getUITree();
      if (uiTree == null || uiTree.isEmpty) {
        return null;
      }

      final parsed = jsonDecode(uiTree) as Map<String, dynamic>;
      final elementsJson = parsed['elements'] as List<dynamic>? ?? const [];
      final elements = elementsJson
          .whereType<Map>()
          .map((element) => Map<String, dynamic>.from(element))
          .toList(growable: false);

      final hasFocusedEditable = elements.any(
        (element) => element['editable'] == true && element['focused'] == true,
      );

      return _UiSnapshot(
        rawTree: uiTree,
        packageName: parsed['package'] as String?,
        elements: elements,
        hasFocusedEditable: hasFocusedEditable,
      );
    } catch (e) {
      return null;
    }
  }

  bool _didPackageChange(_UiSnapshot? before, _UiSnapshot? after) {
    if (before?.packageName == null || after?.packageName == null) {
      return false;
    }
    return before!.packageName != after!.packageName;
  }

  bool _didTreeSignatureChange(_UiSnapshot? before, _UiSnapshot? after) {
    final beforeSignature = before?.signature;
    final afterSignature = after?.signature;
    if (beforeSignature == null || afterSignature == null) {
      return false;
    }
    return beforeSignature != afterSignature;
  }

  bool _tapTargetsEditableField(
    AgentAction action,
    _UiSnapshot? beforeSnapshot,
  ) {
    final elementId = action.params['element'] as num?;
    if (elementId == null || beforeSnapshot == null) {
      return false;
    }

    final element = _findElementById(
      elementId.toInt(),
      beforeSnapshot.elements,
    );
    if (element == null) {
      return false;
    }

    return element['editable'] == true ||
        element['focusable'] == true ||
        (element['type']?.toString().contains('EditText') ?? false);
  }

  Duration _readinessTimeoutForAction(AgentAction action) {
    switch (action.type) {
      case 'open_app':
        return _openAppReadyTimeout;
      case 'tap':
        return _tapReadyTimeout;
      case 'type':
        return _typeReadyTimeout;
      case 'swipe':
      case 'back':
      case 'home':
        return _navigationReadyTimeout;
      case 'wait':
        final ms = (action.params['ms'] as num?)?.toInt() ?? 1000;
        return Duration(milliseconds: ms.clamp(0, 10000));
      default:
        return Duration.zero;
    }
  }

  bool _isActionReady(
    AgentAction action,
    _UiSnapshot? beforeSnapshot,
    _UiSnapshot? currentSnapshot,
  ) {
    if (currentSnapshot == null) {
      return false;
    }

    if (beforeSnapshot == null) {
      return true;
    }

    final packageChanged = _didPackageChange(beforeSnapshot, currentSnapshot);
    final treeChanged = _didTreeSignatureChange(
      beforeSnapshot,
      currentSnapshot,
    );

    switch (action.type) {
      case 'open_app':
        final targetPackage = action.params['package'] as String?;
        if (targetPackage != null &&
            targetPackage.isNotEmpty &&
            currentSnapshot.packageName == targetPackage) {
          return true;
        }
        return packageChanged || treeChanged;
      case 'tap':
        final expectsFocusedInput = _tapTargetsEditableField(
          action,
          beforeSnapshot,
        );
        if (expectsFocusedInput && currentSnapshot.hasFocusedEditable) {
          return true;
        }
        return packageChanged || treeChanged;
      case 'type':
      case 'swipe':
      case 'back':
      case 'home':
      case 'wait':
        return packageChanged || treeChanged;
      default:
        return true;
    }
  }

  Future<_UiSnapshot?> _waitForActionReadiness(
    AgentAction action,
    _UiSnapshot? beforeSnapshot,
  ) async {
    final timeout = _readinessTimeoutForAction(action);
    if (timeout == Duration.zero) {
      return beforeSnapshot;
    }

    final canObserveUi = await _getAccessibilityEnabled();
    if (!canObserveUi) {
      return beforeSnapshot;
    }

    _UiSnapshot? latestSnapshot = beforeSnapshot;
    var currentSnapshot = await _fetchUiSnapshot();
    if (currentSnapshot != null) {
      latestSnapshot = currentSnapshot;
    }
    if (_isActionReady(action, beforeSnapshot, currentSnapshot)) {
      return currentSnapshot;
    }

    var uiChangeSequence = await _screenCapture.getUiChangeSequence();
    final deadline = DateTime.now().add(timeout);

    while (!_cancelRequested) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        break;
      }

      final observedUiChange = await _screenCapture.waitForUiChange(
        sinceSequence: uiChangeSequence,
        timeoutMs: remaining.inMilliseconds,
      );
      if (!observedUiChange) {
        break;
      }

      uiChangeSequence = await _screenCapture.getUiChangeSequence();
      currentSnapshot = await _fetchUiSnapshot();
      if (currentSnapshot != null) {
        latestSnapshot = currentSnapshot;
      }

      if (_isActionReady(action, beforeSnapshot, currentSnapshot)) {
        return currentSnapshot;
      }
    }

    return latestSnapshot;
  }

  /// Execute a single agent action.
  Future<_UiSnapshot?> _executeAction(
    AgentAction action,
    _UiSnapshot? beforeSnapshot,
  ) async {
    // Actions that require the accessibility service
    const accessibilityActions = {'tap', 'type', 'swipe', 'back', 'home'};

    if (accessibilityActions.contains(action.type)) {
      final hasAccessibility = await _ensureAccessibilityEnabled();
      if (!hasAccessibility) {
        _addConversation(
          '⚠️ Cannot execute "${action.type}" — accessibility service not enabled. '
          'Please enable it in Settings → Accessibility → Lucy.',
          false,
        );
        return beforeSnapshot;
      }
    }

    try {
      switch (action.type) {
        case 'open_app':
          final package = action.params['package'] as String? ?? '';
          if (package.isNotEmpty) {
            final success = await _screenCapture.openApp(package);
            if (!success) {
              print('Failed to open app: $package');
            }
          }
          break;

        case 'tap':
          double x, y;
          // Prefer element-based tap (resolve coordinates from UI tree)
          final elementId = action.params['element'] as num?;
          if (elementId != null) {
            final coords = _resolveElementCoordinates(
              elementId.toInt(),
              beforeSnapshot?.elements ?? const [],
            );
            if (coords != null) {
              x = coords['x']!;
              y = coords['y']!;
            } else {
              print(
                'Element $elementId not found in UI tree, falling back to raw coordinates',
              );
              x = (action.params['x'] as num?)?.toDouble() ?? 0;
              y = (action.params['y'] as num?)?.toDouble() ?? 0;
            }
          } else {
            // Fallback to raw coordinates if LLM still provides them
            x = (action.params['x'] as num?)?.toDouble() ?? 0;
            y = (action.params['y'] as num?)?.toDouble() ?? 0;
          }
          await _screenCapture.performTap(x, y);
          break;

        case 'type':
          final text = action.params['text'] as String? ?? '';
          if (text.isNotEmpty) {
            await _screenCapture.performType(text);
          }
          break;

        case 'swipe':
          final startX = (action.params['startX'] as num?)?.toDouble() ?? 0;
          final startY = (action.params['startY'] as num?)?.toDouble() ?? 0;
          final endX = (action.params['endX'] as num?)?.toDouble() ?? 0;
          final endY = (action.params['endY'] as num?)?.toDouble() ?? 0;
          await _screenCapture.performSwipe(startX, startY, endX, endY);
          break;

        case 'back':
          await _screenCapture.pressBack();
          break;

        case 'home':
          await _screenCapture.pressHome();
          break;

        case 'wait':
          break;

        default:
          print('Unknown action type: ${action.type}');
      }
    } catch (e) {
      print('Error executing action ${action.type}: $e');
    }

    return _waitForActionReadiness(action, beforeSnapshot);
  }

  String _trimForTts(String text) {
    // Remove action/emoji markers for cleaner TTS
    String cleaned = text;
    cleaned = cleaned.replaceAll(RegExp(r'⚡.*?\n'), '');
    cleaned = cleaned.trim();
    if (cleaned.length > 300) {
      return '${cleaned.substring(0, 297)}...';
    }
    return cleaned;
  }

  void _setState(AgentState newState) {
    _state = newState;
    notifyListeners();
  }

  Future<bool> capturePreview() async {
    final screenshotBytes = await _captureScreenWithRetry();
    if (screenshotBytes == null) {
      return false;
    }

    _lastScreenshotBytes = screenshotBytes;
    notifyListeners();
    return true;
  }

  void _addConversation(
    String text,
    bool isUser, {
    Uint8List? screenshotBytes,
  }) {
    _conversation.add(
      ConversationEntry(
        text: text,
        isUser: isUser,
        screenshotBytes: screenshotBytes,
      ),
    );
    notifyListeners();
  }

  void clearConversation() {
    _conversation.clear();
    _lastScreenshotBytes = null;
    _isAskingForFurtherHelp = false;
    _aiService.resetChat();
    notifyListeners();
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

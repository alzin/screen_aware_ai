import 'dart:async';
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
  final String? screenshotPath;
  final DateTime timestamp;

  ConversationEntry({
    required this.text,
    required this.isUser,
    this.screenshotPath,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AgentController extends ChangeNotifier {
  final AiService _aiService = AiService();
  final VoiceService _voiceService = VoiceService();
  final ScreenCaptureManager _screenCapture = ScreenCaptureManager();

  AgentState _state = AgentState.idle;
  AgentState get state => _state;

  final List<ConversationEntry> _conversation = [];
  List<ConversationEntry> get conversation => List.unmodifiable(_conversation);

  String _statusMessage = 'Tap the mic to start';
  String get statusMessage => _statusMessage;

  String? _lastScreenshotPath;
  String? get lastScreenshotPath => _lastScreenshotPath;

  String? _currentTranscript = '';
  String? get currentTranscript => _currentTranscript;

  bool _isActive = false;
  bool get isActive => _isActive;

  int _listenRetryCount = 0;
  static const int _maxListenRetries = 3;

  static const int _maxStepsPerCommand = 10;

  AiService get aiService => _aiService;
  ScreenCaptureManager get screenCapture => _screenCapture;

  Future<void> initialize() async {
    await _voiceService.initialize();

    _voiceService.onResult = (text, isFinal) {
      _currentTranscript = text;
      if (isFinal && text.isNotEmpty) {
        _handleUserInput(text);
      }
      notifyListeners();
    };

    _voiceService.onListeningDone = () {
      if (_state == AgentState.listening && _currentTranscript?.isEmpty == true) {
        if (_isActive) {
          _listenRetryCount++;
          if (_listenRetryCount > _maxListenRetries) {
            print('Listening retry limit reached ($_maxListenRetries). Stopping.');
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
    _addConversation('Agent started. Listening for your commands...', false);
    _statusMessage = 'Listening...';
    notifyListeners();

    // Request screen capture permission
    final hasScreenPermission = await _screenCapture.requestPermission();
    if (!hasScreenPermission) {
      _addConversation(
        '⚠️ Screen capture permission denied. I can still listen and talk, but cannot see the screen.',
        false,
      );
    }

    _listenRetryCount = 0;
    _startListening();
  }

  Future<void> stopAgent() async {
    _isActive = false;
    await _voiceService.stopListening();
    await _voiceService.stopSpeaking();
    _setState(AgentState.idle);
    _statusMessage = 'Tap the mic to start';
    _addConversation('Agent stopped.', false);
    notifyListeners();
  }

  Future<void> _startListening() async {
    if (!_isActive) return;
    _setState(AgentState.listening);
    _statusMessage = '🎤 Listening...';
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

    await _runAgentLoop(text);

    // Resume listening after the loop completes
    if (_isActive) {
      _startListening();
    }
  }

  /// The core agent loop: capture → analyze → act → repeat.
  Future<void> _runAgentLoop(String userMessage) async {
    int step = 0;
    String currentMessage = userMessage;

    // Fetch screen size once for the whole loop
    final screenSize = await _screenCapture.getScreenSize();

    while (step < _maxStepsPerCommand && _isActive) {
      step++;

      // 1. Capture screenshot (with retries for reliability after app switches)
      _setState(AgentState.capturing);
      _statusMessage = '📸 Capturing screen... (step $step)';
      notifyListeners();

      String? screenshotPath = await _captureScreenWithRetry();
      if (screenshotPath != null) {
        _lastScreenshotPath = screenshotPath;
      }

      // 2. Send to AI
      _setState(AgentState.analyzing);
      _statusMessage = '🤖 Thinking... (step $step)';
      notifyListeners();

      final agentResponse = await _aiService.agentChat(
        currentMessage,
        imagePath: screenshotPath,
        screenSize: screenSize,
      );

      // Show AI thought + speak in conversation
      String displayText = agentResponse.speak;
      if (agentResponse.thought.isNotEmpty) {
        displayText = '💭 ${agentResponse.thought}\n\n$displayText';
      }
      if (agentResponse.actions.isNotEmpty) {
        final actionSummary = agentResponse.actions
            .map((a) => '⚡ ${a.type}${a.params.isNotEmpty ? ': ${a.params}' : ''}')
            .join('\n');
        displayText = '$displayText\n\n$actionSummary';
      }
      _addConversation(displayText, false, screenshotPath: screenshotPath);

      // 3. Execute actions
      if (agentResponse.actions.isNotEmpty) {
        _setState(AgentState.executingAction);
        _statusMessage = '⚡ Executing actions... (step $step)';
        notifyListeners();

        for (final action in agentResponse.actions) {
          await _executeAction(action);
        }

        // Brief wait after actions for the UI to settle
        await Future.delayed(const Duration(milliseconds: 800));
      }

      // 4. Speak the response (only speak if done or has something to say)
      if (agentResponse.speak.isNotEmpty) {
        _setState(AgentState.speaking);
        _statusMessage = '🔊 Speaking...';
        notifyListeners();

        final ttsText = _trimForTts(agentResponse.speak);
        await _voiceService.speak(ttsText);

        // Wait for TTS to finish
        await Future.delayed(const Duration(seconds: 1));
        while (_voiceService.isSpeaking) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 5. Check if done
      if (agentResponse.done) {
        break;
      }

      // Not done → continue the loop with a follow-up message
      currentMessage = 'I have executed the actions. Here is the updated screen. Continue with the task.';
      // If screenshot capture might fail next iteration, the AI will still
      // receive the message but without an image. The retry logic in
      // _captureScreenWithRetry handles this by making multiple attempts.
    }

    if (step >= _maxStepsPerCommand) {
      _addConversation('⚠️ Reached maximum steps ($_maxStepsPerCommand). Stopping.', false);
    }
  }

  /// Capture the screen with retry logic.
  /// After navigating to another app, the first capture attempt may return null
  /// because the VirtualDisplay hasn't rendered a fresh frame yet. Retrying
  /// with increasing delays ensures we eventually get a valid screenshot.
  Future<String?> _captureScreenWithRetry({int maxRetries = 3}) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        final path = await _screenCapture.captureScreen();
        if (path != null) return path;
      } catch (e) {
        print('Screenshot capture attempt ${i + 1} failed: $e');
      }
      if (i < maxRetries - 1) {
        // Increasing delay between retries: 500ms, 1000ms
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    print('All $maxRetries screenshot capture attempts failed');
    return null;
  }

  /// Execute a single agent action.
  Future<void> _executeAction(AgentAction action) async {
    try {
      switch (action.type) {
        case 'open_app':
          final package = action.params['package'] as String? ?? '';
          if (package.isNotEmpty) {
            final success = await _screenCapture.openApp(package);
            if (!success) {
              print('Failed to open app: $package');
            }
            // Wait for the app to fully launch and render its first frame
            await Future.delayed(const Duration(milliseconds: 2500));
          }
          break;

        case 'tap':
          final x = (action.params['x'] as num?)?.toDouble() ?? 0;
          final y = (action.params['y'] as num?)?.toDouble() ?? 0;
          await _screenCapture.performTap(x, y);
          await Future.delayed(const Duration(milliseconds: 500));
          break;

        case 'type':
          final text = action.params['text'] as String? ?? '';
          if (text.isNotEmpty) {
            await _screenCapture.performType(text);
            await Future.delayed(const Duration(milliseconds: 300));
          }
          break;

        case 'swipe':
          final startX = (action.params['startX'] as num?)?.toDouble() ?? 0;
          final startY = (action.params['startY'] as num?)?.toDouble() ?? 0;
          final endX = (action.params['endX'] as num?)?.toDouble() ?? 0;
          final endY = (action.params['endY'] as num?)?.toDouble() ?? 0;
          await _screenCapture.performSwipe(startX, startY, endX, endY);
          await Future.delayed(const Duration(milliseconds: 500));
          break;

        case 'back':
          await _screenCapture.pressBack();
          await Future.delayed(const Duration(milliseconds: 500));
          break;

        case 'home':
          await _screenCapture.pressHome();
          await Future.delayed(const Duration(milliseconds: 500));
          break;

        case 'wait':
          final ms = (action.params['ms'] as num?)?.toInt() ?? 1000;
          await Future.delayed(Duration(milliseconds: ms));
          break;

        default:
          print('Unknown action type: ${action.type}');
      }
    } catch (e) {
      print('Error executing action ${action.type}: $e');
    }
  }

  String _trimForTts(String text) {
    // Remove thinking/emoji markers for cleaner TTS
    String cleaned = text.replaceAll(RegExp(r'💭.*?\n'), '');
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

  void _addConversation(String text, bool isUser, {String? screenshotPath}) {
    _conversation.add(ConversationEntry(
      text: text,
      isUser: isUser,
      screenshotPath: screenshotPath,
    ));
    notifyListeners();
  }

  void clearConversation() {
    _conversation.clear();
    _aiService.resetChat();
    notifyListeners();
  }

  @override
  void dispose() {
    _voiceService.dispose();
    super.dispose();
  }
}

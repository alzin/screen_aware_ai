import 'dart:convert';
import 'dart:io';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Represents a single action the AI wants to perform.
class AgentAction {
  final String type; // tap, type, open_app, back, home, swipe, wait
  final Map<String, dynamic> params;

  AgentAction({required this.type, this.params = const {}});

  @override
  String toString() => 'AgentAction($type, $params)';
}

/// Parsed structured response from the AI agent.
class AgentResponse {
  final String thought;
  final List<AgentAction> actions;
  final String speak;
  final bool done;
  final String rawResponse;

  AgentResponse({
    required this.thought,
    required this.actions,
    required this.speak,
    required this.done,
    required this.rawResponse,
  });

  factory AgentResponse.fromJson(Map<String, dynamic> json, String raw) {
    final actionsList = (json['actions'] as List<dynamic>? ?? [])
        .map((a) => AgentAction(
              type: a['type'] as String? ?? 'wait',
              params: Map<String, dynamic>.from(a as Map)..remove('type'),
            ))
        .toList();

    return AgentResponse(
      thought: json['thought'] as String? ?? '',
      actions: actionsList,
      speak: json['speak'] as String? ?? '',
      done: json['done'] as bool? ?? true,
      rawResponse: raw,
    );
  }

  factory AgentResponse.fallback(String raw) {
    return AgentResponse(
      thought: '',
      actions: [],
      speak: raw.length > 300 ? '${raw.substring(0, 297)}...' : raw,
      done: true,
      rawResponse: raw,
    );
  }
}

class AiService {
  GenerativeModel? _model;
  ChatSession? _chat;
  String? _apiKey;

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  static const _systemPrompt = '''
You are an autonomous AI agent controlling an Android phone. You can SEE the screen via screenshots and PERFORM actions on it.

AVAILABLE ACTIONS:
- {"type": "open_app", "package": "com.whatsapp"} — Launch an app by package name
- {"type": "tap", "x": 540, "y": 1200} — Tap at screen coordinates (pixels)
- {"type": "type", "text": "Hello!"} — Type text into the focused input field
- {"type": "swipe", "startX": 540, "startY": 1500, "endX": 540, "endY": 500} — Swipe/scroll
- {"type": "back"} — Press the back button
- {"type": "home"} — Press the home button
- {"type": "wait", "ms": 1000} — Wait before next screenshot

COMMON APP PACKAGES:
- WhatsApp: com.whatsapp
- Chrome: com.android.chrome
- Settings: com.android.settings
- YouTube: com.google.android.youtube
- Gmail: com.google.android.gm
- Messages: com.google.android.apps.messaging
- Phone: com.google.android.dialer
- Camera: com.android.camera2
- Maps: com.google.android.apps.maps
- Calendar: com.google.android.calendar
- Clock: com.google.android.deskclock
- Calculator: com.google.android.calculator
- Files: com.google.android.apps.nbu.files
- Play Store: com.android.vending
- Photos: com.google.android.apps.photos
- Contacts: com.google.android.contacts
- Instagram: com.instagram.android
- X/Twitter: com.twitter.android
- Telegram: org.telegram.messenger
- Facebook: com.facebook.katana
- Spotify: com.spotify.music

RULES:
1. You MUST respond with ONLY valid JSON. No markdown, no explanation outside JSON.
2. Look at the screenshot carefully. Identify what is on screen.
3. When the user asks you to do something, plan and execute step by step.
4. After performing actions, set "done": false so you get another screenshot to verify.
5. Set "done": true only when the user's request is fully completed or you've reported the info they asked for.
6. The screen dimensions in pixels are provided with each message as [Screen: WxH pixels]. Use these exact dimensions to determine tap coordinates from the screenshot. Tap the CENTER of the target element.
7. Keep "speak" concise — it will be read aloud to the user.
8. If you cannot perform an action or need more info, explain in "speak" and set "done": true.
9. When asked to read/describe screen content, read it from the screenshot, speak it, and set "done": true.
10. Always provide your reasoning in "thought" before actions.

RESPONSE FORMAT (strict JSON, no other text):
{
  "thought": "I see the home screen. I need to open WhatsApp to check messages.",
  "actions": [
    {"type": "open_app", "package": "com.whatsapp"}
  ],
  "speak": "Opening WhatsApp for you.",
  "done": false
}
''';

  void configure(String apiKey) {
    _apiKey = apiKey;
    _model = GenerativeModel(
      model: 'gemini-3.1-flash-lite-preview',
      apiKey: apiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
      systemInstruction: Content.system(_systemPrompt),
    );
    _chat = _model!.startChat();
  }

  /// Send a message with an optional screenshot and get a structured response.
  Future<AgentResponse> agentChat(String message, {String? imagePath, Map<String, int>? screenSize}) async {
    if (!isConfigured) {
      return AgentResponse.fallback('AI not configured. Please set your API key.');
    }

    try {
      // Prepend screen dimensions so the AI knows exact coordinate space
      String fullMessage = message;
      if (screenSize != null) {
        fullMessage = '[Screen: ${screenSize['width']}x${screenSize['height']} pixels] $message';
      }

      Content content;
      if (imagePath != null) {
        final imageBytes = await File(imagePath).readAsBytes();
        content = Content.multi([
          TextPart(fullMessage),
          DataPart('image/png', imageBytes),
        ]);
      } else {
        content = Content('user', [TextPart(fullMessage)]);
      }

      final response = await _chat!.sendMessage(content);
      final text = response.text ?? '{}';

      return _parseAgentResponse(text);
    } catch (e) {
      return AgentResponse.fallback('Error: ${e.toString()}');
    }
  }

  /// Parse the AI's JSON response into an AgentResponse.
  AgentResponse _parseAgentResponse(String text) {
    try {
      // Try to extract JSON from the response
      String jsonStr = text.trim();

      // If wrapped in markdown code block, extract it
      if (jsonStr.startsWith('```')) {
        final startIdx = jsonStr.indexOf('{');
        final endIdx = jsonStr.lastIndexOf('}');
        if (startIdx != -1 && endIdx != -1) {
          jsonStr = jsonStr.substring(startIdx, endIdx + 1);
        }
      }

      final json = jsonDecode(jsonStr) as Map<String, dynamic>;
      return AgentResponse.fromJson(json, text);
    } catch (e) {
      // If JSON parsing fails, treat the whole response as a spoken message
      return AgentResponse.fallback(text);
    }
  }

  /// Reset chat history for a fresh conversation.
  void resetChat() {
    if (_model != null) {
      _chat = _model!.startChat();
    }
  }
}

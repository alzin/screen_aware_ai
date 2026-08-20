# Contributing to Lucy

First off — thank you. Lucy is a young project and there is genuinely a lot of impactful work available, from one-line lint fixes to designing the safety layer that decides which actions need user confirmation.

This guide gets you from a fresh clone to a merged pull request.

- [Ways to contribute](#-ways-to-contribute)
- [Development setup](#-development-setup)
- [Project layout](#-project-layout)
- [Code style](#-code-style)
- [Testing](#-testing)
- [Pull request process](#-pull-request-process)
- [Commit messages](#-commit-messages)
- [Recipe: adding a new agent action](#-recipe-adding-a-new-agent-action)
- [Recipe: adding a language](#-adding-a-language)
- [Good first issues](#-good-first-issues)
- [Debugging tips](#-debugging-tips)

---

## 🎯 Ways to contribute

You don't have to write Kotlin to be useful here.

| | |
|---|---|
| 🐛 **Report bugs** | Especially "Lucy tapped the wrong thing in app X" reports. Device model + Android version + the app involved is gold. |
| 📱 **Device testing** | Lucy's behaviour varies a lot across manufacturers. Testing on Xiaomi/Oppo/Samsung and reporting what breaks is genuinely valuable. |
| 🌍 **Translations** | Adding a language is a small, well-scoped change — see the [recipe below](#-adding-a-language). |
| 📖 **Docs** | If a step in the README confused you, that's a bug in the README. |
| 🧪 **Tests** | Test coverage is thin. `AgentController`'s state machine is the highest-value target. |
| 💡 **Features** | Check the [roadmap](README.md#-roadmap) and open an issue before starting anything large. |

> [!TIP]
> For anything beyond a small fix, **open an issue first** and say you'd like to work on it. It avoids two people building the same thing, and it's a chance to agree on the approach before you invest hours.

---

## 🛠️ Development setup

### Prerequisites

- **Flutter** with Dart SDK `^3.11.1` (verified on Flutter 3.47.1 / Dart 3.13.1)
- **JDK 17**
- **A physical Android device** running Android 7.0+ with USB debugging enabled

Emulators technically run the app, but they usually lack a working speech-recognition engine, which makes the whole voice loop untestable. Use a real phone.

### Get running

```bash
git clone https://github.com/alzin/lucy-screen-agent.git
```

```bash
cd lucy-screen-agent && flutter pub get
```

```bash
flutter run
```

Then follow steps 6–10 of the [Quick Start](README.md#-quick-start) to add your Gemini API key, enable the accessibility service and grant screen capture.

### Before you push

Run the same three checks CI runs:

```bash
dart format --output=none --set-exit-if-changed .
```

```bash
flutter analyze --no-fatal-infos
```

```bash
flutter test
```

---

## 📁 Project layout

Lucy is deliberately small — six Dart files and four Kotlin files. Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full picture; here's the map:

### Dart (`lib/`)

| File | Responsibility |
|---|---|
| `main.dart` | Entry point. Builds `LucyApp`, owns the single `AgentController` instance. |
| `screens/home_screen.dart` | All UI. Accessibility gate, conversation list, mic button, API-key dialog, language selector. |
| `services/agent_controller.dart` | **The brain.** `ChangeNotifier` holding agent state, the observe→decide→act loop, action execution, readiness waiting, language state. |
| `services/ai_service.dart` | Gemini client. Owns the system prompt and parses the model's JSON into `AgentResponse` / `AgentAction`. |
| `services/voice_service.dart` | Thin wrapper over `speech_to_text` and `flutter_tts`, including locale mapping. |
| `services/screen_capture_service.dart` | Dart half of the `MethodChannel`. One method per native capability. |

### Kotlin (`android/app/src/main/kotlin/com/poc/screen_aware_ai/`)

| File | Responsibility |
|---|---|
| `MainActivity.kt` | Hosts the method channel, drives the `MediaProjection` consent flow, routes calls to the services. |
| `ScreenCaptureService.kt` | Foreground service. `MediaProjection` → `VirtualDisplay` → `ImageReader` → downscaled JPEG bytes, all on a background `HandlerThread`. |
| `ScreenActionService.kt` | The `AccessibilityService`. Walks the node tree into JSON, and dispatches tap/swipe/type/back/home gestures. |
| `OverlayService.kt` | The persistent "Stop Lucy" notification and its broadcast back into Flutter. |

> [!NOTE]
> The Kotlin package is still `com.poc.screen_aware_ai` (a leftover from the proof-of-concept days) and the Dart package is `screen_aware_ai`. Renaming these would change the Android `applicationId`, which breaks upgrades for anyone who already installed Lucy — so they stay as they are for now.

---

## 🎨 Code style

We follow standard Dart and Kotlin conventions. Nothing exotic.

**Dart**

- Format with `dart format .` — this is enforced in CI.
- `flutter analyze` must not introduce new **warnings** or **errors**. (Existing `info`-level lints are tracked as cleanup issues; CI runs with `--no-fatal-infos`.)
- Private members get a leading underscore. Public API on services gets a `///` doc comment.
- Prefer `const` constructors. Prefer early returns over deep nesting.

**Kotlin**

- Keep anything that touches bitmaps or the image pipeline **off the main thread** — `ScreenCaptureService` already runs on a dedicated `HandlerThread`, keep it that way.
- Always null-check `instance` on the services before use; Android can tear them down at any time.
- Log with the existing `TAG` constants rather than `println`.

**Both**

- Match the surrounding code. If a file uses a pattern, use that pattern.
- No new dependencies without discussing it in an issue first — every dependency is a permission surface on a project like this.

---

## 🧪 Testing

```bash
flutter test
```

Widget tests mock the `com.poc.screen_aware_ai/screen` method channel, because none of the native services exist in a test environment. See [`test/widget_test.dart`](test/widget_test.dart) for the pattern:

```dart
TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMethodCallHandler(channel, (call) async {
  switch (call.method) {
    case 'isAccessibilityEnabled':
      return true;
    // ...
  }
  return null;
});
```

Anything touching the agent loop, screen capture or gestures needs a **real device** and manual verification. When you submit a PR that changes agent behaviour, please say in the description which device you tested on and what you asked Lucy to do.

---

## 🔀 Pull request process

1. **Fork** the repo and create a branch off `main`:

   ```bash
   git checkout -b feat/confirmation-gate
   ```

2. **Make your change.** Keep the PR focused — one concern per PR. A 40-line PR gets reviewed today; a 900-line PR gets reviewed eventually.

3. **Run the checks** (format, analyze, test — see [above](#before-you-push)).

4. **Test on a real device** if you touched the agent loop or native code.

5. **Open the PR** against `main` and fill in the template. Describe *what changed and why*, and include a screenshot or screen recording for UI changes.

6. **Respond to review.** Push follow-up commits rather than force-pushing — it keeps the review thread readable. We'll squash on merge.

### What gets a PR merged fast

- ✅ It does one thing
- ✅ It explains why, not just what
- ✅ Format/analyze/test all pass
- ✅ Behaviour changes come with a note on how they were verified
- ✅ It doesn't add a dependency without discussion

---

## 💬 Commit messages

Conventional Commits, please:

```
feat: add confirmation gate before send actions
fix: retry screen capture after MediaProjection token expiry
docs: clarify accessibility setup on MIUI
refactor: extract element lookup from AgentController
test: cover the follow-up negative-response path
chore: bump google_generative_ai to 0.4.7
```

The subject line is imperative and lowercase. Body is optional — use it to explain *why*.

---

## 🧩 Recipe: adding a new agent action

Say you want to add a `long_press` action. Four files change, in this order:

### 1. Teach the model about it — `lib/services/ai_service.dart`

Add it to the `AVAILABLE ACTIONS` block in `_systemPrompt`:

```dart
- {"type": "long_press", "element": 5} — Long-press the UI tree element with the given id
```

Keep the description terse and give the exact JSON shape. This prompt is the model's entire API reference.

### 2. Add the Dart channel method — `lib/services/screen_capture_service.dart`

```dart
/// Long-press at the given coordinates.
Future<bool> performLongPress(double x, double y) async {
  try {
    final result = await _channel.invokeMethod<bool>('performLongPress', {
      'x': x,
      'y': y,
    });
    return result ?? false;
  } catch (e) {
    print('Error performing long press: $e');
    return false;
  }
}
```

### 3. Handle it in the loop — `lib/services/agent_controller.dart`

Add a `case 'long_press':` to `_executeAction()`. If the action takes an `element` id, resolve its real coordinates from the UI snapshot with the existing `_findElementById()` helper — **never** let the model supply raw tap coordinates.

Then add the action to `_readinessTimeoutForAction()` and `_isActionReady()` so the loop knows how long to wait for the screen to settle afterwards.

### 4. Implement it natively — `ScreenActionService.kt` + `MainActivity.kt`

In `ScreenActionService.kt`, build the gesture:

```kotlin
fun performLongPress(x: Float, y: Float): Boolean {
    val path = Path().apply { moveTo(x, y) }
    val gesture = GestureDescription.Builder()
        .addStroke(GestureDescription.StrokeDescription(path, 0, 800))
        .build()
    return dispatchGestureSync(gesture)
}
```

In `MainActivity.kt`, add a `"performLongPress" ->` branch to the method-channel handler. Follow the existing `performTap` branch exactly — it runs the gesture on a background `Thread` and returns via `runOnUiThread`, which matters because gesture dispatch blocks.

### 5. Test it on a device

Ask Lucy to do something that requires the new action and watch the conversation view for the `⚡ long_press: {element: 5}` line.

---

## 🌍 Adding a language

Lucy currently speaks English, Japanese and Arabic. Adding a fourth touches five spots, all small.

**1. `lib/services/voice_service.dart`** — add TTS and STT locales:

```dart
static const Map<String, String> _langToTtsLocale = {
  'en': 'en-US', 'ja': 'ja-JP', 'ar': 'ar-SA',
  'es': 'es-ES',  // ← new
};

static const Map<String, String> _langToSttLocale = {
  'en': 'en_US', 'ja': 'ja_JP', 'ar': 'ar_SA',
  'es': 'es_ES',  // ← new
};
```

**2. `lib/services/agent_controller.dart`** — register the code and translate the two hardcoded phrases:

```dart
static const Set<String> _supportedLangs = {'en', 'ja', 'ar', 'es'};

static const Map<String, String> _followUps = {
  // ...
  'es': '¿Necesitas más ayuda?',
};

static const Map<String, String> _stoppingMessages = {
  // ...
  'es': 'De acuerdo, deteniendo el agente.',
};
```

**3. Same file** — add a negative-response pattern so "no, that's all" ends the session:

```dart
static final RegExp _negativeEs = RegExp(r'^(no|nada|para|detente|ya está)$');
```

and add it to the `isNegative` check in `_handleUserInput()`.

**4. `lib/services/ai_service.dart`** — extend the `LANGUAGE RULES` block of `_systemPrompt` so the model knows to reply in Spanish and tag `"lang": "es"`.

**5. `lib/screens/home_screen.dart`** — add the badge and the menu entry:

```dart
static const Map<String, String> _langBadges = {
  'en': 'EN', 'ja': 'JA', 'ar': 'AR', 'es': 'ES',
};
```

```dart
PopupMenuItem(value: 'es', child: Text('Español')),
```

Please test on a device with that TTS voice installed and mention it in the PR — some locales need a voice-data download.

---

## 🌱 Good first issues

If you're looking for somewhere to start, these are real, self-contained tasks in the current codebase:

| Task | Where | Difficulty |
|---|---|---|
| Replace `print()` with a proper logger or `debugPrint` | `agent_controller.dart`, `screen_capture_service.dart` (~28 occurrences) | 🟢 Easy |
| Migrate deprecated `withOpacity()` → `withValues()` | `home_screen.dart` (~13 occurrences) | 🟢 Easy |
| Remove the unused `path_provider` dependency | `pubspec.yaml` | 🟢 Easy |
| Make the empty conversation state actually helpful (it's currently just an icon) | `home_screen.dart` → `_buildEmptyState` | 🟢 Easy |
| Show a masked preview of the saved API key in the dialog | `home_screen.dart` | 🟡 Medium |
| Add unit tests for `AgentResponse.fromJson` and the fallback path | new `test/ai_service_test.dart` | 🟡 Medium |
| Extract the hardcoded package-name list out of the system prompt into a data file | `ai_service.dart` | 🟡 Medium |
| Add a confirmation gate before irreversible actions | `agent_controller.dart` | 🔴 Hard |

Clearing the first two also lets CI run with `flutter analyze` at full strictness — a nice follow-up PR.

---

## 🔍 Debugging tips

**Watch the native side.** Most of the interesting failures are in Kotlin:

```bash
adb logcat -s MainActivity ScreenCaptureService ScreenActionService OverlayService
```

**Inspect what the model actually sees.** `AgentResponse.rawResponse` holds Gemini's unparsed reply — print it in `_runAgentLoop` when an action looks wrong. Nine times out of ten the model behaved sensibly given a bad UI tree.

**Dump the UI tree.** Call `screenCapture.getUITree()` and log the JSON. If an element you expect is missing, the target app isn't exposing it to accessibility — that's an upstream limitation, not a Lucy bug.

**The projection token expires.** On Android 14+, `MediaProjection` tokens are single-use. If capture starts failing after an app switch, that's expected — `screen_capture_service.dart` handles it by re-requesting permission. Don't "fix" it by caching harder.

**State machine confusion.** `AgentController` has seven states (`idle`, `listening`, `capturing`, `analyzing`, `speaking`, `waitingConfirmation`, `executingAction`). If the UI looks stuck, log `_setState` transitions first — the bug is usually a state that never advances, not a hung await.

---

## 📜 Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Be decent to each other.

---

## 📄 License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE) that covers this project.

---

**Questions?** Open a [discussion or an issue](https://github.com/alzin/lucy-screen-agent/issues) — no question is too small, and if something confused you it probably confuses others too.

# Changelog

All notable changes to Lucy are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

- 📖 Open source documentation set: `README`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY`, and `docs/ARCHITECTURE.md`
- 📄 MIT `LICENSE`
- 🔧 GitHub Actions CI — format check, analyze, tests, and a debug APK build on every push and pull request
- 📋 Issue templates for bug reports and feature requests, plus a pull request template
- 🧪 Widget tests covering the accessibility gate and the main screen, with the platform channel mocked

### Fixed

- 🧪 `flutter test` no longer fails on a clean checkout — the previous test asserted against the main screen without mocking the accessibility method channel, so it always rendered the "Accessibility Required" gate instead

### Changed

- 🎨 Applied `dart format` across `lib/` so contributor diffs stay clean

---

## [1.0.1] - 2026-05-08

The state of the app when it was open sourced. Distributed to testers only; not
formally released.

### Added

- 🗣️ **Voice-driven agent loop** — speech in, screenshot and accessibility tree to Gemini, real taps and keystrokes out, spoken answer back
- 👁️ **Dual-input perception** — a downscaled JPEG screenshot plus a structured JSON accessibility tree with exact pixel bounds for every element
- 🎯 **Tap-by-element** — the model references elements by integer ID; coordinates are resolved on the Dart side, making hallucinated taps structurally impossible
- ⚡ **Seven actions** — `open_app`, `tap`, `type`, `swipe`, `back`, `home`, `wait`
- 🌍 **Trilingual support** — English, Japanese and Arabic, with language detection from the model's response, matching TTS/STT locales, and a persisted language preference
- 🛑 **Persistent "Stop Lucy" notification** — cancels the agent from anywhere, including from inside another app
- 🔑 **Bring-your-own Gemini API key**, stored locally via `shared_preferences`
- ♿ **Accessibility gate** — the app requires its accessibility service before it will run, and re-checks on resume
- 💬 **Conversation view** with inline screenshots, action summaries and timestamps

### Changed

- ⚡ Screenshots are encoded to JPEG in memory on a dedicated background thread instead of being written to disk
- ⚡ Screenshot capture and UI-tree collection now run concurrently within each agent step
- ⚡ Fixed post-action sleeps replaced with readiness detection — the loop waits for an observed package change, UI-tree change, or newly focused input, with per-action timeouts
- 🎨 Numerous UI refinements to the conversation view and status bar

### Fixed

- 🔄 Screen capture recovers from a lost or expired `MediaProjection` token, including the single-use token behaviour on Android 14+
- 🔁 Capture is retried after app switches, when the `VirtualDisplay` has not yet rendered a frame
- 🎤 Speech recognition retries on empty results, with a 3-attempt ceiling before returning to idle

---

## [1.0.0] - 2026-03-07

Initial proof of concept: screen capture, a Gemini vision call, and the first
working accessibility-driven taps.

[Unreleased]: https://github.com/alzin/lucy-screen-agent/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/alzin/lucy-screen-agent/releases/tag/v1.0.1
[1.0.0]: https://github.com/alzin/lucy-screen-agent/releases/tag/v1.0.0

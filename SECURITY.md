# Security Policy

Lucy runs with two of the most sensitive permissions Android grants — **screen capture** and an **accessibility service that can tap and type on the user's behalf**. That makes security reports especially important here, and we take them seriously.

## Supported versions

Lucy is pre-1.0 and moves fast. Only the latest commit on `main` receives fixes.

| Version | Supported |
|---|---|
| `main` (latest) | ✅ |
| Tagged releases | ⚠️ Best effort |
| Anything older | ❌ |

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Use GitHub's private reporting instead:

1. Go to the [Security tab](https://github.com/alzin/lucy-screen-agent/security/advisories/new).
2. Click **Report a vulnerability**.
3. Describe the issue, the impact, and how to reproduce it.

This creates a private thread visible only to maintainers.

### What to include

- What the vulnerability allows an attacker to do
- Step-by-step reproduction, ideally with a device model and Android version
- Whether it requires physical access, a malicious app on the device, or neither
- Any proof-of-concept code (please don't test on other people's devices)

### What to expect

| | |
|---|---|
| **Acknowledgement** | Within 7 days |
| **Assessment** | Within 14 days, with a severity judgement and a rough fix timeline |
| **Fix & disclosure** | Coordinated with you; credit given in the advisory unless you prefer otherwise |

This is a volunteer-run project, so please be patient if a response takes a little longer than the targets above.

## What counts as a vulnerability here

Things we especially want to hear about:

- 🔓 **API key exposure** — any path that leaks the user's Gemini key out of `shared_preferences` to another app, a log, or the network
- 📤 **Unintended data exfiltration** — screenshots or accessibility-tree data reaching anywhere other than the Google Gemini API
- 🎭 **Prompt injection with real consequences** — on-screen content that causes Lucy to perform actions the user didn't ask for (this is a genuine threat model for a screen-reading agent, and a report with a working demo is very welcome)
- 🚪 **Privilege escalation** — another app on the device driving Lucy's accessibility service or method channel
- 🛑 **Cancellation bypass** — any state where the user cannot stop a running agent
- 📢 **Exported component abuse** — the services are declared `exported="false"`; a way around that is a bug

## What is a known limitation, not a vulnerability

These are documented design consequences. Reports about them will be closed with a pointer here:

- **Screenshots are sent to Google.** This is how the app works. It's documented in the [README](README.md#-privacy--security).
- **The accessibility service can read on-screen text.** That is the point of an accessibility service.
- **Lucy will do what she's told**, including sending a message. A confirmation gate is [on the roadmap](README.md#-roadmap), and its absence is a known gap rather than a vulnerability report.
- **`FLAG_SECURE` screens capture as black.** Working as intended.
- **A user who enables the accessibility service has granted broad access.** Android shows an explicit warning before this.

## For users

If you run Lucy, reduce your exposure:

- ✅ Prefer a spare device or a separate Android user profile
- ✅ Disable the accessibility service when you're not actively using the app
- ✅ Stop Lucy (via the **Stop Lucy** notification) before opening banking apps, password managers or private messages
- ✅ Use a Gemini API key scoped to this use and rotate it if you ever share a build
- ❌ Never install a Lucy APK from an untrusted source — build it yourself from this repository

## Scope

This policy covers the code in this repository. Vulnerabilities in dependencies (Flutter, `google_generative_ai`, `speech_to_text`, `flutter_tts`, `shared_preferences`) or in the Gemini API should be reported to those projects — though a heads-up here is appreciated so we can bump versions.

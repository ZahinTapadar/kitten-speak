# KittenSpeak

Select text anywhere on macOS → right-click → **Services → Speak with KittenSpeak**. It reads it aloud, offline, with [KittenTTS](https://github.com/KittenML/KittenTTS) nano (a 17 MB model running on CPU).

- 37 built-in voices across 8 languages (English, German, Spanish, Italian, Portuguese, Russian, Hindi, French)
- Native: a macOS Service (no accessibility permissions, no clipboard hijacking) plus a menu-bar icon for voice, speed and Stop (⌘.)
- Instant: the model stays warm in the background; first audio in ~0.1 s, speech streams sentence by sentence, Stop cuts off immediately

## Install

Requires Apple-silicon macOS 13+, Xcode command-line tools and [uv](https://docs.astral.sh/uv/).

```bash
./build.sh
```

This creates `.venv`, builds `KittenSpeak.app` into `~/Applications`, registers the Service and launches it. If the Service does not show up in the right-click menu, enable it in **System Settings › Keyboard › Keyboard Shortcuts › Services › Text** (you can also give it a hotkey there).

## How it works

| File | Role |
|---|---|
| `KittenSpeak.swift` | Menu-bar app; `speak(_:userData:error:)` receives the selection from the Services menu and plays audio chunks as they arrive |
| `Info.plist` | `NSServices` entry that puts "Speak with KittenSpeak" into the right-click menu |
| `engine.py` | Long-lived Python process: JSON lines on stdin, WAV chunk paths on stdout, one chunk per sentence; any new request cancels the old one |
| `test_engine.py` | Self-check: voices, first-audio latency, Stop cancellation |

## Credits

Speech by [KittenTTS](https://github.com/KittenML/KittenTTS) (Apache 2.0). Inspired by [FluidVoice](https://github.com/altic-dev/FluidVoice).

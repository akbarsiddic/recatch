# Meeting Radar — E2E Scaffold (M0 → P1)

Native macOS Swift/SwiftUI app. Open this folder on your Mac with Xcode 16+ (`open Package.swift`).

## Decisions locked
- Native Swift/SwiftUI, macOS 14+ (dev on 15.x), Apple Silicon
- Ears = on-device WhisperKit `openai_whisper-largev3-turbo` (same approach as StreamLingo.space: 100% local, $0 STT)
- Brain = BYOK: Anthropic native + OpenAI-compatible (OpenAI, OpenCode Zen, OpenRouter, Ollama) + CLI fallback (`opencode run`, `claude -p`, `codex exec`)
- `since I looked` = `lastPanelOpenedAt`

## Run M0 on Mac
1. `open Package.swift` in Xcode, select My Mac, Run.
2. Join a Google Meet in Chrome with a second device as remote speaker.
3. Menu bar → Start listening → grant Mic + Screen Recording (relaunch if asked) → pick main display.
4. Speak alternating. Debug window should show `Me / Others` lines in <4s.
5. Unplug headphones / toggle Bluetooth / sleep 10s → should auto-resume + log `[gap]`. Stop → no `.wav/.pcm` on disk.

## Providers (Brain)
Settings → Providers:
- Anthropic API key (fast default), or
- OpenAI-compatible baseURL + key. Presets: OpenAI, OpenCode Zen (`https://opencode.ai/zen/v1`), OpenRouter, Ollama (`http://localhost:11434/v1`)
- CLI fallback (slow, opt-in for Ask only): `opencode run --model <id>`, `claude -p`, `codex exec`
- Per-feature override: cheap model for Right-now, stronger for Ask.

## Layout
- `Capture/` — ScreenCaptureKit system audio + AVAudioEngine mic, MeetingClock, manager
- `Transcription/` — VAD + chunker + WhisperKit engine + pipeline + language router
- `LLM/` — gateway protocol + adapters + prompts
- `Persistence/` — SQLite schema + retention + Keychain + redactor
- `UI/` — menu bar, hotkey panel, overlay, settings, permissions
- `Nudges/` — P3 behind feature flag (schema ships now, detection later)

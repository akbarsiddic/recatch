# ReCatch

Never ask “what did I miss?” again.

A private, Mac-only companion that answers two questions on demand — without anyone else knowing you asked:

1. **What's happening right now?**
2. **What did I miss?**

You drifted off, got pulled into code, or the conversation moved fast. Instead of reading a full transcript or asking out loud, press a hotkey and get a glanceable answer in seconds.

> No bots. No recordings. No one else knows. Audio never leaves your Mac.

---

## How it works

- **Menu bar app** — sits quietly in your menu bar. Idle → Listening → Paused.
- **Hotkey panel** — press `⌥⌘R`, pick **Right now**, **What did I miss** (2m / 5m / 10m / since you looked), or **Ask** anything about the meeting so far.
- **Live ears, private brain** — speech is transcribed on-device (Whisper, Apple Silicon). Only the transcript text for the window you requested is sent to your chosen LLM. Audio is never stored, never uploaded.
- **Mixed English + Indonesian** — built for code-switching. Answers come back in the language you picked for the meeting.
- **Global-ready (LiveLingo-style)** — same engine handles 30+ languages: auto-detect per chunk, code-switch mid-sentence without flipping settings, output in any language you pick. Indo was just the first test pair.

## Privacy first

- Audio exists only in memory, discarded after transcription.
- Transcripts live in local SQLite, auto-deleted after 3 days (1–7 configurable, or delete on meeting end).
- One-click **Delete everything now**.
- API keys live in macOS Keychain, never in logs.
- **What leaves my machine** screen shows every LLM request (timestamp + size).
- Consent reminder on every start — you're responsible for telling participants where required.

## Providers (bring your own)

Pick whatever you already pay for. No lock-in.

| Brain | How | Best for |
|---|---|---|
| Anthropic API | API key | Fast, accurate default |
| OpenAI / OpenRouter | API key | Swap models freely |
| OpenCode Zen | API key | One key, many models |
| Ollama | Local, free | Fully offline meetings |
| `opencode run` / `claude -p` / `codex exec` | CLI, uses your subscription | $0 extra, slower (Ask only) |

Tip: use a cheap model for *Right now*, a stronger one for *Ask*. Set per-feature in Settings → Providers.

## Requirements

- Mac with Apple Silicon, macOS 14+ (developed on 15.x)
- Xcode 16+ to build
- Microphone + Screen Recording permissions (for system audio)
- A Google Meet in Chrome (more apps later)

## Install & run

```bash
git clone git@github.com:akbarsiddic/recatch.git
cd recatch
open Package.swift   # opens in Xcode → select My Mac → Run
```

1. Join a Meet in Chrome.
2. Menu bar → **Start listening** → grant Mic + Screen Recording (relaunch once if macOS asks) → consent reminder → done.
3. Press `⌥⌘R` anytime. `Esc` dismisses, focus returns to your work.

## Shortcuts

- `⌥⌘R` — summon panel
- `⌘1 / ⌘2 / ⌘3` — Right now / Missed / Ask
- `Esc` — dismiss

## Project layout

- `Sources/ReCatch/Capture/` — ScreenCaptureKit system audio + mic, meeting clock
- `Sources/ReCatch/Transcription/` — VAD, chunker, Whisper engine, language router
- `Sources/ReCatch/LLM/` — provider-agnostic gateway + prompts
- `Sources/ReCatch/Persistence/` — SQLite, retention janitor, Keychain
- `Sources/ReCatch/UI/` — menu bar, hotkey panel, overlay, settings
- `Sources/ReCatch/Nudges/` — quiet name-mention nudges (phased, off by default)

## Roadmap

- [x] M0 — capture spike: system + mic → live on-device transcript
- [ ] M1 — menu bar skeleton, hotkey panel, permissions
- [ ] M2 — on-demand answers with streaming + error states
- [ ] M3 — retention, delete-all, consent, LLM log view
- [ ] M4 — overlay pill, per-meeting language, rating loop
- [ ] M5 — nudges: name mentions + directed-at-me detection

## Contributing

Personal tool, but PRs welcome. Keep it local-first: no audio uploads, no tracking, no accounts.

## License

TBD (personal use for now).

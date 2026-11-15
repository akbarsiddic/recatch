# ReCatch

**Never ask "what did I miss?" again.**

A private, local-first companion for your Mac that answers two questions on demand — without anyone else knowing you asked:

1. **What's happening right now?**
2. **What did I miss?**

You drifted off, got pulled into code, or the conversation moved fast. Instead of reading a full transcript or asking out loud, glance at the floating caption or press `⌥⌘R` and get an answer in seconds.

No bots join your call. Nothing is uploaded. Audio never leaves your Mac.

---

## What it does

- **Rolling live captions** in a floating window — words appear while people speak, not after the meeting.
- **Right now** — a one-line read of the current topic.
- **What did I miss** — timestamped summary, decisions, open questions, anything directed at you.
- **Ask** — any question about the meeting so far.
- **Answers in the meeting's language.** ReCatch does not translate. If the meeting is Bahasa, the answer is Bahasa.
- **Auto-start** — when a meeting takes the mic, ReCatch starts listening by itself. Stop it and it backs off for a minute.

## Why it's different

- **Local ASR.** Whisper runs on-device via CoreML. Audio is never recorded, never stored, never uploaded.
- **System audio without Screen Recording.** It uses Core Audio process taps, so it only asks for the Audio Recording permission.
- **One mixed stream.** Mic and system audio are mixed before recognition, so a single recognizer hears the whole room.
- **Bring your own brain.** 14 providers — API keys or the coding agents you already pay for.
- **A model you choose.** Fast (Whisper Base, loads in seconds) or Accurate (Large V3 Turbo). Bigger models are an upgrade, never a default that stalls first launch.

## Requirements

- Apple Silicon Mac, macOS 14.2+ (built and tested on macOS 26)
- Xcode 16+ / Swift 6 toolchain to build
- Microphone permission; Audio Recording permission for system audio

## Install

```bash
git clone https://github.com/akbarsiddic/recatch.git
cd recatch

./Scripts/make-app.sh release run   # builds build/ReCatch.app and launches it
```

Or open `Package.swift` in Xcode, select **My Mac**, and Run.

On first launch:

1. Menu bar → **Start listening** (or just join a meeting — it auto-starts).
2. Grant **Microphone** (and **Audio Recording** for system audio).
3. Settings → General → pick your **meeting language** and **speech model**.
4. Settings → Providers → paste one API key (Groq's free tier is fastest).

The first run downloads the speech model (~140 MB Fast / ~954 MB Accurate) with progress shown in the menu.

## Using it

| Action | Shortcut |
|---|---|
| Summon panel | `⌥⌘R` |
| Right now / Missed / Ask | `⌘1` / `⌘2` / `⌘3` |
| Start / stop listening | `⌥⌘L` |
| Dismiss | `Esc` |

The overlay appears on its own while listening. Drag it anywhere; it stays above full-screen apps and remembers its position.

## Providers

ReCatch talks to whatever you already have. Keys live in the macOS Keychain, never in preferences or logs.

| Kind | Providers |
|---|---|
| API | Groq, OpenAI, Anthropic, DeepSeek, OpenRouter, OpenCode Zen, 9router (local), Ollama (local), any custom OpenAI-compatible endpoint |
| Your existing agent | Claude Code, opencode, Codex, Gemini CLI, Command Code |

Groq is the fastest by a wide margin (sub-second answers). CLIs use your subscription at no extra cost but are slower — good for **Ask**, not for **Right now**.

## How it works

```
Microphone ─┐
            ├─► AudioMixer ─► RollingTranscriber ─► SQLite ─► AnswerEngine ─► provider
System audio┘   (16 kHz mono)   (12 s window,       (3-day      (Right now /
 Core Audio tap                  partial + final)    retention)  Missed / Ask)
```

- **Capture** — `AVAudioEngine` for the mic, `CATapDescription` + aggregate device for system audio. ScreenCaptureKit is the fallback.
- **Mix** — one 16 kHz mono stream, labelled Me/Others by which side carried the energy.
- **Transcribe** — the last 12 s are re-transcribed continuously; the growing line is the live caption. A line is committed at 18 words, 22 s, or 1.2 s of silence.
- **Answer** — only the transcript window you asked about is sent to your provider. Every request is logged locally as timestamp + size, never content.

## Privacy

- Audio exists only in memory and is discarded after transcription.
- Transcripts live in local SQLite and auto-delete after 3 days (1–7 configurable, or **Delete everything now**).
- API keys live in the Keychain.
- **What left this machine** in Settings → Privacy lists every LLM request: timestamp, model, token counts. No content.

You are responsible for complying with local rules and letting participants know you're transcribing.

## Verify it works, without a meeting

```bash
# speech file → VAD → ASR (no mic, no permissions)
RECATCH_SELFTEST=1 RECATCH_SELFTEST_AUDIO=/path/to/speech.wav .build/debug/ReCatch

# whole app path: capture → rolling captions → SQLite → panel answer
RECATCH_SELFTEST=1 RECATCH_SELFTEST_APP=1 RECATCH_SELFTEST_AUDIO=/path/to/speech.wav .build/debug/ReCatch

# live capture for N seconds, then ask the panel (play something while it runs)
RECATCH_SELFTEST=1 RECATCH_SELFTEST_LIVE=90 .build/debug/ReCatch

# provider round-trip only
RECATCH_SELFTEST=1 RECATCH_SELFTEST_LLM=1 .build/debug/ReCatch
```

`RECATCH_DEBUG=1` streams pipeline tracing to stderr (never audio, never keys).

## Troubleshooting

**Nothing appears when I talk.**
Check Settings → General shows "Model ready". If it says failed, hit **Retry download** — a half-finished model download is the usual cause.

**It transcribes the wrong language.**
Set **Meeting language** explicitly. Auto-detect guesses per window and will happily hear English in Indonesian audio.

**First launch hangs for minutes.**
The Accurate tier's encoder is heavy to compile. `ANECompilerService` can spin at 100% CPU for a long time on some Macs ([upstream issue](https://github.com/argmaxinc/argmax-oss-swift/issues/560)). ReCatch computes on GPU by default to avoid it; `RECATCH_ANE=1` opts back in. If it still hangs: `sudo killall -9 ANECompilerService`.

**No system audio.**
Grant **Audio Recording** in System Settings → Privacy & Security. Mic-only still works.

## Project layout

```
Sources/ReCatch/
├── Capture/        mic, Core Audio tap, mixer, meeting watcher
├── Transcription/  rolling window, WhisperKit engine, filter
├── LLM/            provider catalog, adapters, answer engine, prompts
├── Persistence/    SQLite store, retention janitor, Keychain
├── UI/             menu bar, hotkey panel, overlay, settings
└── SelfTest.swift  headless probes
Scripts/            make-app.sh, make-icon.py
```

## Roadmap

- [x] On-device transcription with rolling captions
- [x] Floating overlay, auto-start, catch-up + ask
- [x] 14 providers, BYO key or CLI
- [x] Core Audio tap (no Screen Recording)
- [ ] Speaker labels beyond Me/Others
- [ ] Nudges: your name mentioned, something directed at you
- [ ] Notarized build, auto-update

## Contributing

Issues and PRs welcome. Keep it local-first: no audio uploads, no accounts, no tracking.

Before opening a PR:

```bash
swift build && ./Scripts/make-app.sh release
```

## License

MIT — see [LICENSE](LICENSE).

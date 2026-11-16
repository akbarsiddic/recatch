# Backlog

## Provider architecture — adopt pi.dev's approach

**Status:** not started
**Why:** Today ReCatch works end-to-end with Groq only. Claude, ChatGPT and the
other providers are wired in `LLM/Providers.swift` but unverified. The current
shape is a hand-rolled adapter list with per-feature overrides.

**What "pi.dev's approach" means:** pi (github.com/earendil-works/pi) drives many
providers — Claude Code, opencode, Gemini CLI, Codex, DeepSeek, and API-key
providers — through a single provider registry/capability abstraction
(`orchestrator_capabilities`), then fans out work by feature with per-call
model/option overrides. ReCatch should mirror that: one registry of providers
(CLI agents *and* raw API keys), a single capability surface, and the existing
per-feature provider/model overrides (transcribe / summarize / ask) kept intact
on top of it.

**Scope to decide later:**
- Which providers are CLI-agent style (shell out to `claude`, `opencode`, `gemini`, `codex`) vs raw API key.
- How to keep ReCatch's privacy promise (audio never leaves the Mac; only transcript text goes to the LLM) consistent across CLI providers.
- A self-test matrix that actually exercises each provider, not just registers it.

## Ship a real installer (DMG + one-command install)

**Status:** not started
**Why:** The landing page presents "Download for macOS" like Tayang Studio does, but
ReCatch has no released artifact yet — the button points at GitHub Releases (empty).

**What:**
- Cut a notarized `.dmg` (needs an Apple Developer ID + notarization credentials).
- Add an `install.sh` one-command installer (mirror Tayang Studio's `curl -fsSL … | sh`
  flow) that drops the app in `/Applications` and opens it.
- Wire the GitHub Actions release pipeline (or a local `make dmg` script) to build the
  `.app` via `./Scripts/make-app.sh release` and publish to Releases.
- Update the landing page's download button + "Opening the first time" FAQ once the
  DMG actually exists.

## Landing page polish (site/)

**Status:** built (v1), needs a real demo video + real screenshots on final pass
**Why:** The page uses self-test screenshots (stub meeting content) and has no demo video yet.

**What:**
- Record a real demo (overlay live summary → catch-up → ask) and embed it in the hero.
- Replace stub screenshots with real, anonymized meeting captures.
- Activate the "Featured on" badges only after actually listing on Launch Llama Tools,
  Twelve Tools, Smol Launch, and ShipNLaunch (submission notes in DECISIONS or a launch file).

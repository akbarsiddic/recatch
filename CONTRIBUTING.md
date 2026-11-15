# Contributing

Thanks for looking. A few things that keep this project honest:

## Ground rules

- **Local-first.** No audio uploads, no accounts, no analytics. A PR that sends audio off-device will be declined.
- **No translation.** ReCatch answers in the meeting's language. Translation is a different product.
- **Small models are a feature.** Defaults must stay usable on first launch. A model that takes minutes to compile is an opt-in tier, never the default.
- **Say why, not just what.** If you change a threshold (energy gate, window length, token budget), say which real recording it was tuned on.

## Before you open a PR

```bash
swift build
./Scripts/make-app.sh release
RECATCH_SELFTEST=1 RECATCH_SELFTEST_LLM=1 .build/debug/ReCatch   # provider round-trip
```

If you touched capture or transcription, run the whole-app probe with a speech file:

```bash
say -v Samantha "We ship the migration on Friday." -o /tmp/speech.aiff
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/speech.aiff /tmp/speech.wav
RECATCH_SELFTEST=1 RECATCH_SELFTEST_APP=1 RECATCH_SELFTEST_AUDIO=/tmp/speech.wav .build/debug/ReCatch
```

A subagent's "it works" is not evidence — paste the transcript.

## Reporting a bug

Include:

- macOS version and chip (`sw_vers`, `sysctl -n machdep.cpu.brand_string`)
- Speech model tier (Fast / Accurate) and meeting language
- Output of `RECATCH_DEBUG=1` around the failure — it logs pipeline shape, never audio or keys

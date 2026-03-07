# CLAUDE.md — whisper-dictation

## What this project is

A macOS live dictation tool: press a hotkey, speak, and transcribed text appears
in whatever app has focus. Powered by whisper.cpp (local, open-source, private).

## Architecture

```
Hammerspoon (Lua)
  ├── hotkey bind → start/stop dictation
  ├── spawn whisper.cpp stream binary
  ├── read stdout line by line
  └── hs.eventtap.keyStrokes() → type text into active app
```

### Components

1. **whisper.cpp stream binary** (`whisper-stream`) — lives at `~/whisper.cpp/build/bin/`
   - Source: `~/whisper.cpp/examples/stream/stream.cpp`
   - Continuously captures mic audio via SDL2, transcribes in chunks, prints to stdout
   - Has built-in VAD (voice activity detection) mode

2. **Hammerspoon** (https://www.hammerspoon.org/) — macOS automation
   - Scriptable in Lua; provides hotkey binding, process spawning, simulated keystrokes
   - Config lives at `~/.hammerspoon/init.lua`

3. **This repo** — glue scripts, config, documentation

## Francis's setup

- **Mac**: Apple Silicon, 36 GB RAM
- **whisper.cpp**: `~/whisper.cpp/`, binaries at `~/whisper.cpp/build/bin/`
- **Model**: `ggml-large-v3.bin` (2.9 GB)

## Design decisions

- **Hotkey**: Ctrl+D (replaces macOS dictation — must disable system dictation shortcut first)
- **Toggle mode**: press Ctrl+D to start, press again to stop
- **Visual feedback**: menubar icon shows state (idle / loading / listening)
- **Process lifecycle**: whisper-stream is spawned on first Ctrl+D, killed on second press.
  "Quit Whisper" in menubar fully kills it to free RAM (~3 GB).

## Key files

- `init.lua` — Hammerspoon config (symlinked to `~/.hammerspoon/init.lua`)
- `README.md` — setup instructions and usage

## Known characteristics

- ~5 second cold start when whisper-stream first launches (Metal GPU library init)
- whisper-stream output includes ANSI escape codes (`[2K`) for line overwriting;
  init.lua strips these before typing text
- Model auto-punctuates (commas, periods, question marks)

## TODO

- **Chunk tuning**: experiment with `--step` and `--length` values to balance latency
  vs. transcription quality. Larger steps give the model more context (fewer
  within-chunk artifacts like "artist artist's") but delay output.
- **Corrections dictionary**: a simple text file mapping common mistranscriptions
  to correct words (e.g., proper names). Applied as post-processing before typing.
  Similar to what Wispr Flow calls "vocabulary learning" — no model fine-tuning,
  just string replacement.
- **System audio transcription**: capture system audio (e.g., a Zoom call) via
  BlackHole virtual audio device. Likely a separate mode that writes to a file
  rather than typing into the active app. Low priority — for meetings, simpler to
  record in Zoom and run whisper-cli on the file afterward.

## Decided against

- **Silence hallucinations blocklist**: whisper hallucinates "Thank you" etc. during
  silence. Considered filtering these in Lua but it's kludgy. Better to just stop
  dictation when not speaking (Ctrl+D to toggle off).
- **VAD mode**: whisper-stream's VAD mode (`--step 0`) is designed for isolated speech
  detection, not continuous dictation. It grabs overlapping 10-second windows every
  2 seconds, causing massive duplication for continuous speech.

## Conventions

- Keep it simple — this is a small tool, not a framework
- Local-first, no cloud services

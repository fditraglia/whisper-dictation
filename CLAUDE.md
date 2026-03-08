# CLAUDE.md — whisper-dictation

## What this project is

A macOS live dictation tool: press a hotkey, speak, and transcribed text appears
in whatever app has focus. Powered by whisper.cpp (local, open-source, private).

## Architecture

Two modes, both orchestrated by Hammerspoon (Lua):

```
Streaming (Ctrl+D):
  Hammerspoon → whisper-stream (SDL2 mic capture) → stdout → keyStrokes

Batch (Ctrl+Shift+D):
  Hammerspoon → ffmpeg (record to wav) → whisper-cli (transcribe) → keyStrokes
```

### Components

1. **whisper-stream** — `~/whisper.cpp/build/bin/whisper-stream`
   - Captures mic via SDL2, transcribes in ~6-second chunks, prints to stdout
   - Used for streaming mode

2. **whisper-cli** — `~/whisper.cpp/build/bin/whisper-cli`
   - Transcribes a complete audio file in one pass with full context
   - Used for batch mode (~4 seconds per minute of audio on M4 Max)

3. **ffmpeg** — records mic audio to wav file for batch mode

4. **Hammerspoon** (https://www.hammerspoon.org/) — macOS automation
   - Hotkey binding, process spawning, simulated keystrokes, menubar icon
   - Config lives at `~/.hammerspoon/init.lua`

5. **This repo** — Hammerspoon config, documentation

## Francis's setup

- **Mac**: Apple Silicon, 36 GB RAM
- **whisper.cpp**: `~/whisper.cpp/`, binaries at `~/whisper.cpp/build/bin/`
- **Model**: `ggml-large-v3.bin` (2.9 GB)

## Design decisions

- **Hotkeys**: Ctrl+D for streaming, Ctrl+Shift+D for batch
- **Toggle mode**: press to start, press again to stop (both modes)
- **Visual feedback**: menubar icon shows state (idle / loading / streaming / recording)
- **Batch mode rationale**: streaming has inherent chunk boundary issues (duplicated
  words, limited context). Batch transcribes the full recording in one pass — higher
  quality, simpler code, ~4s/min processing delay is acceptable.

## Key files

- `init.lua` — Hammerspoon config (symlinked to `~/.hammerspoon/init.lua`)
- `README.md` — setup instructions and usage

## Known characteristics

- ~5 second cold start when whisper-stream first launches (Metal GPU library init);
  subsequent launches faster due to macOS shader caching
- Streaming mode: whisper-stream output includes ANSI escape codes (`[2K`) for line
  overwriting; init.lua strips these and deduplicates overlapping words at chunk
  boundaries
- Streaming mode: whisper hallucinates "Thank you" etc. during silence — just stop
  dictation when not speaking
- Batch mode: uses ffmpeg for recording, whisper-cli for transcription. SIGINT to
  ffmpeg for clean shutdown (writes wav header)
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

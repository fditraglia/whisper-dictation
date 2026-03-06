# whisper-dictation

Local, private live dictation for macOS. Press a hotkey, speak, and transcribed
text appears in whatever app has focus. Powered by
[whisper.cpp](https://github.com/ggerganov/whisper.cpp) and
[Hammerspoon](https://www.hammerspoon.org/).

## How it works

1. **Hammerspoon** listens for a hotkey and spawns/kills the whisper.cpp stream process
2. **whisper-stream** captures mic audio via SDL2, transcribes it locally, and prints text to stdout
3. **Hammerspoon** reads stdout and types the text into the active app via simulated keystrokes

Everything runs locally — no cloud services, no network requests.

## Dependencies

| Dependency | What it does | Install |
|---|---|---|
| [whisper.cpp](https://github.com/ggerganov/whisper.cpp) | Speech-to-text engine | Clone + build from source |
| [SDL2](https://www.libsdl.org/) | Real-time microphone capture (used by whisper-stream) | `brew install sdl2` |
| [Hammerspoon](https://www.hammerspoon.org/) | macOS automation: hotkeys, process control, keystrokes | `brew install --cask hammerspoon` |

## Building whisper-stream

The `whisper-stream` binary is not built by default — it requires SDL2 and an
explicit CMake flag.

```bash
# Install SDL2 if not already present
brew install sdl2

# Rebuild whisper.cpp with the stream example enabled
cd ~/whisper.cpp/build
cmake .. -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_SDL2=ON
cmake --build . --target whisper-stream

# Verify
ls -la ~/whisper.cpp/build/bin/whisper-stream
```

### Why SDL2?

whisper.cpp's `stream` example needs to capture audio from the microphone in
real time. SDL2 (Simple DirectMedia Layer) provides a cross-platform API for
this. It's a widely-used open-source library — the same one many games and media
apps use for audio/video. whisper.cpp's CMakeLists.txt gates the stream build
behind `WHISPER_SDL2=ON` so that the core library can be built without this
dependency.

## Setup

### 1. Disable macOS dictation shortcut

Ctrl+D is the macOS dictation key by default. You need to prevent macOS from
intercepting it:

- System Settings → Keyboard → Dictation → turn off the shortcut (or turn off
  Dictation entirely)
- If you press Ctrl+D before doing this, macOS may show a "Do you want to enable
  dictation?" prompt — choose **Don't Ask Again** to dismiss it permanently

### 2. Install and configure Hammerspoon

```bash
brew install --cask hammerspoon
```

Open Hammerspoon from `/Applications/Hammerspoon.app`. On first launch:

1. **Enable Accessibility**: macOS will prompt you, or go to System Settings →
   Privacy & Security → Accessibility → toggle Hammerspoon on. This is required
   for simulating keystrokes.
2. **Quit and reopen Hammerspoon** after granting Accessibility permissions —
   macOS doesn't always pick up the permission change until the app restarts.
3. **Recommended settings** (Hammerspoon menubar icon → Preferences):
   - Enable "Launch Hammerspoon at login" so it's always available
   - Enable "Check for updates" (updates are infrequent; it's open-source)

### 3. Link the config

The Hammerspoon config (`init.lua`) lives in this repo and is symlinked into
Hammerspoon's config directory:

```bash
mkdir -p ~/.hammerspoon
ln -s /path/to/whisper-dictation/init.lua ~/.hammerspoon/init.lua
```

### 4. Reload

Click the Hammerspoon menubar icon → Reload Config, or run:

```bash
hs -c "hs.reload()"
```

You should see a "Whisper dictation loaded" alert and a 🎤✕ menubar icon.

## Usage

- **Ctrl+D** — toggle dictation on/off
- First press spawns `whisper-stream` (~5 second model load), then starts
  transcribing. Subsequent presses kill/restart the process instantly.
- A menubar icon shows the current state:
  - 🎤✕ — idle (process not running)
  - 🎤⏳ — loading model
  - 🎤🔴 — actively listening
- Click the menubar icon → "Quit Whisper" to kill the process and free ~3 GB RAM.

## Files

| File | Purpose |
|---|---|
| `init.lua` | Hammerspoon config — hotkey binding, process management, menubar |
| `README.md` | This file |
| `CLAUDE.md` | Project context for Claude Code |

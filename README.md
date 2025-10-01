# 🎬 mpv-multi-screen

**mpv-multi-screen** is a lightweight macOS command-line tool that launches one [`mpv`](https://mpv.io/) instance per display, each running fullscreen in loop mode.  
It supports **per-screen audio routing** and optional **volume control**, so each screen can output sound to its own device at the desired level.

---

## 🚀 Features
- Launch one fullscreen `mpv` instance per screen
- Play either:
  - a single video file per screen, or
  - an entire folder of videos (looped as a playlist)
- Independent audio device selection per screen
- Persistent configuration of audio routing & volume
- Clean playback: no UI, no OSC, just video

---

## 📦 Installation

You need [`mpv`](https://mpv.io/) installed on your Mac. The easiest way is via [Homebrew](https://brew.sh):

```bash
# Install Homebrew if not already installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install mpv
brew install mpv
```

Then build this project in Xcode (or `swift build`) to get the `mpv-multi-screen` executable.

---

## 🔧 Usage

### 1. List available audio devices
```bash
mpv-multi-screen list
```

Example output:
```
[0] 'coreaudio/auto' (default)
[1] 'coreaudio/USB HIFI Audio'
[2] 'coreaudio/HDMI LG TV'

Config will be saved to: ~/Library/Application Support/mpv-multi-screen/audio.conf
Use: mpv-multi-screen setaudio <idx[,vol]> <idx[,vol]> ...  (one per screen, in order; vol = 0–100)
```

---

### 2. Save audio routing per screen
Choose a device (and optionally a volume 0–100) for each screen:

```bash
# screen1 → device index 1 @ 100%
# screen2 → device index 2 @ 45%
mpv-multi-screen setaudio 1,100 2,45
```

The configuration is saved persistently at:

```
~/Library/Application Support/mpv-multi-screen/audio.conf
```

---

### 3. Launch videos
Pass **one path per screen** (each path can be a single file or a folder):

```bash
# Example: 2 screens, each looping its own folder
mpv-multi-screen /path/to/folder1 /path/to/folder2
```

- If you pass a folder, all supported videos inside (`.mp4`, `.mov`, `.mkv`, `.webm`, etc.) are sorted and looped as a playlist.
- Each instance runs fullscreen on its assigned display.
- The saved audio device and volume settings are automatically applied.

---

## 🛠 Development

This project is written in Swift and can be built via Xcode or the Swift Package Manager:

```bash
swift build -c release
```

The resulting binary can be copied into `/usr/local/bin` or another location on your `$PATH`.

---

## 📄 License
MIT License © 2025 Alaric Hamacher

# EnigmaSuite V2 🚀

**Modern, fast, cross-platform Enigma2 receiver suite written in Rust.**

Supports all Enigma2-based satellite and cable set-top boxes (VU+, Dreambox, Gigablue, Octagon, Zgemma running OpenATV, VTi, OpenPLi, PurE2, etc.).

---

## Features

- 🎛️ **Box Manager:** Manage multiple Enigma2 receivers with automatic online status detection, hardware info, and tuner details.
- 📱 **Virtual Remote Control:** Full responsive remote keypad, on-screen TV screenshots, and volume/power control.
- 📺 **Channels & EPG:** Browse bouquets, view live electronic program guides, zap channels, and stream directly with VLC/mpv.
- ⏱️ **Timers & Movies:** Manage scheduled recordings, browse recordings on receiver storage, and stream recordings over local network.
- 🔄 **Settings Sync:** Compare and clone channel lists and `/etc/enigma2/settings` between two receivers.
- 🎨 **Bootlogo & MVI Creator:** Create and flash custom bootlogos and backdrop images.
- 💾 **Image Manager & Multiboot:** Slot inspection and full backup flashing.
- 🌐 **Bilingual:** Instant switching between Finnish 🇫🇮 and English 🇬🇧.

---

## Supported Platforms

- **macOS:** Universal 2 Binary (Native Apple Silicon M1/M2/M3/M4 + Intel x86_64), macOS 11+.
- **Windows:** Standalone 64-bit executable & Microsoft Store MSIX package (Windows 10/11).
- **Linux:** Standalone x86_64 binary (glibc 2.17+ compatible).

---

## Building from Source

Ensure you have Rust 1.80+ installed:

```bash
cargo build --release
```

### All Platforms Build

```bash
./scripts/build_all_platforms.sh
```

---

## Author

Developed by **Niko Pietinen**.

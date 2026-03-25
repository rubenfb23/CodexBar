---
summary: "Build and run the native Ubuntu window for CodexBar."
read_when:
  - Building the Linux GUI from source
  - Installing GTK/libadwaita dependencies on Ubuntu
---

# Native Ubuntu app

CodexBar now has a native Ubuntu window target named `CodexBarLinux`.

This is not a direct port of the macOS menu bar app. The Linux app is a separate GTK4/libadwaita frontend that reads the existing `CodexBarCLI` JSON output and renders provider cards in a native desktop window.

## Requirements

- Ubuntu 24.04 or newer
- `libgtk-4-dev`
- `libadwaita-1-dev`
- `xdg-utils`
- Swift 6.2.1 or newer

## Install and run

From the repo root:

```bash
./bin/install-codexbar-ubuntu-native.sh
codexbar-linux
```

The installer will:

- install the GTK/libadwaita build dependencies with `apt`
- bootstrap Swift with Swiftly if `swift` is missing
- build `CodexBarCLI` and `CodexBarLinux`
- install symlinks into `~/.local/bin`
- add a desktop entry at `~/.local/share/applications/com.steipete.codexbar.linux.desktop`

## Manual build

```bash
sudo apt-get update
sudo apt-get install -y pkg-config xdg-utils libgtk-4-dev libadwaita-1-dev
swift build -c release --product CodexBarCLI
swift build -c release --product CodexBarLinux
.build/release/CodexBarLinux
```

If `CodexBarLinux` cannot find the CLI automatically, point it at the binary explicitly:

```bash
CODEXBAR_LINUX_CLI_BINARY="$(pwd)/.build/release/CodexBarCLI" .build/release/CodexBarLinux
```

## Current scope

- native GNOME/libadwaita window
- overview page with provider cards rendered from `codexbar usage --format json`
- providers page that writes provider enablement back to `~/.codexbar/config.json`
- general/display/about pages with Linux-side persisted preferences
- manual refresh
- open config button via `xdg-open`

Not implemented yet:

- tray/AppIndicator integration
- autostart
- notifications
- parity with the macOS menu bar UI

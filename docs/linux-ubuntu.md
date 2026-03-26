---
summary: "Build and run the native Ubuntu tray app for CodexBar."
read_when:
  - Building the Linux GUI from source
  - Installing GTK/libadwaita dependencies on Ubuntu
  - Configuring provider tokens on Linux
  - Setting up the Homebrew tap for Linux
---

# Native Ubuntu app

CodexBar has a native Ubuntu tray target named `CodexBarLinux`.

This is not a direct port of the macOS menu bar app. The Linux app is a separate GTK4/libadwaita frontend that reads the existing `CodexBarCLI` JSON output and renders provider cards in a native desktop window. It integrates with the system tray via the StatusNotifierItem (SNI) D-Bus protocol.

## Requirements

- Ubuntu 24.04 or newer (or any Linux distro with GTK 4.6+)
- GTK4, libadwaita, libX11 (installed automatically by either method below)
- GNOME Shell with the [AppIndicator/KStatusNotifierItem](https://extensions.gnome.org/extension/615/appindicator-support/) extension (for the tray icon)

## Install via Homebrew (pre-built binary)

Homebrew runs on Linux. This is the easiest way to install a pre-built binary without compiling from source.

```bash
brew tap rubenfb23/codexbar
brew install codexbar-linux
codexbar-linux
```

Homebrew will install the `gtk4`, `libadwaita`, and `libx11` runtime dependencies automatically.

> **Tap repo**: create a GitHub repo named `homebrew-codexbar` and copy [`Formula/codexbar-linux.rb`](../Formula/codexbar-linux.rb) from this repo into it. Update the `sha256` and `version` fields after each release.

## Install from source (install script)

From the repo root:

```bash
./bin/install-codexbar-ubuntu-native.sh
codexbar-linux
```

The installer will:

- install the GTK/libadwaita/X11 build dependencies with `apt`
- bootstrap Swift with Swiftly if `swift` is missing
- build `CodexBarCLI` and `CodexBarLinux`
- install symlinks into `~/.local/bin`
- copy the CodexBar icon to `~/.local/share/icons/hicolor/` at sizes 22–256 px
- add a desktop entry at `~/.local/share/applications/com.steipete.codexbar.linux.desktop`

## Manual build

```bash
sudo apt-get update
sudo apt-get install -y pkg-config xdg-utils libgtk-4-dev libadwaita-1-dev libx11-dev
swift build -c release --product CodexBarCLI
swift build -c release --product CodexBarLinux
.build/release/CodexBarLinux
```

If `CodexBarLinux` cannot find the CLI automatically, point it at the binary explicitly:

```bash
CODEXBAR_LINUX_CLI_BINARY="$(pwd)/.build/release/CodexBarCLI" .build/release/CodexBarLinux
```

## Tray icon

The app registers a StatusNotifierItem (SNI) on the session D-Bus. Requires the GNOME Shell **AppIndicator** extension to be enabled.

- **Single click** on the tray icon opens/closes the compact popup window directly below the icon.
- The tray icon uses the embedded CodexBar logo via SNI `IconPixmap` (no icon-theme dependency).
- The app forces `GDK_BACKEND=x11` (XWayland) so the popup window can be precisely positioned with `XMoveWindow`.

### Context menu

Right-click the tray icon to open a context menu:

| Item | Action |
|------|--------|
| Show / Hide | Toggle the popup |
| Refresh | Force a fresh fetch of all providers |
| Preferences | Open the settings window |
| Quit | Exit CodexBar |

## Preferences window

Open via the ⚙ button in the popup footer or via the tray context menu.

| Tab | Contents |
|-----|----------|
| Overview | Full provider cards with usage bars |
| Providers | Toggle providers, configure API tokens |
| General | Refresh cadence, usage options |
| Display | Bar direction, personal info redaction |
| About | Build paths, description |

### Configuring provider API tokens

Some providers authenticate via an API token (Copilot, OpenRouter, Zai, …). On macOS these are stored in the Keychain. On Linux they are stored in `~/.codexbar/config.json` under `providers[].apiKey`.

To configure a token in the UI:

1. Open **Preferences → Providers**
2. Find the provider section (e.g. "Copilot")
3. Paste the token into the **API Token** field and click **Save**
4. Refresh — the provider should now show usage data

Alternatively edit `~/.codexbar/config.json` directly:

```json
{
  "providers": [
    { "id": "copilot", "enabled": true, "apiKey": "ghu_your_token_here" }
  ]
}
```

#### Copilot token

Get a GitHub OAuth token with the `copilot` scope:

```bash
gh auth token        # if you have the GitHub CLI and are already signed in
```

Or create a Personal Access Token at **GitHub → Settings → Developer settings → Personal access tokens** with `copilot` scope, then paste it in the Providers tab.

## Current scope

- SystemTray icon via SNI D-Bus protocol (requires AppIndicator GNOME Shell extension)
- Single-click popup window positioned below tray icon
- Overview page with provider cards rendered from `codexbar usage --format json`
- Providers page: toggle enablement, configure API tokens
- General/display/about pages with Linux-side persisted preferences
- Auto-refresh (configurable cadence)
- Manual refresh
- Open config button via `xdg-open`

## Not implemented yet

- Autostart / launch-at-login
- Desktop notifications
- Full parity with the macOS menu bar (merged view, history charts, etc.)

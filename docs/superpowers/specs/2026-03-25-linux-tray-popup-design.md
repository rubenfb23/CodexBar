# Linux Tray Icon + Compact Popup — Design Spec

**Date:** 2026-03-25
**Branch:** feat/ubuntu-native
**Goal:** Replace the floating AdwApplicationWindow with a system tray icon that opens a compact popup, anchoring CodexBar to the top-right of the screen like the macOS menu bar version.

---

## 1. User Story

As a Ubuntu user, I want CodexBar to live as a tray icon in the GNOME top bar so I can see AI provider usage at a glance by clicking the icon, without a floating window taking up screen space.

---

## 2. Architecture Overview

### Current
- App starts → opens `AdwApplicationWindow` (1080×780) floating anywhere on screen.

### New
- App starts → no window shown.
- A **StatusNotifierItem (SNI)** tray icon appears in the GNOME top bar via the D-Bus `org.kde.StatusNotifierItem` protocol, implemented directly over GLib D-Bus (no AppIndicator library — see §4 for why).
- **Left-click / Activate** → toggles the compact popup (show/hide).
- **Right-click / ContextMenu** → shows a `GtkPopoverMenu` at the provided (x, y) screen coordinates with: Show/Hide · Refresh · ─── · Preferences · Quit.
- **⚙ button** in popup footer → opens the existing full preferences window (tabs: Overview, Providers, General, Display, About).
- **↻ button** → triggers a data refresh.
- **✕ button** → quits the app.

---

## 3. Compact Popup Spec

### Dimensions & Position
- Width: ~280px fixed.
- Height: auto (grows with number of providers, max ~480px then scrolls).
- **Wayland note**: On Wayland, `gtk_window_move()` and `gtk_window_set_keep_above()` are no-ops. The SNI `Activate` D-Bus call delivers the (x, y) of the tray icon click; these coordinates are used to call `gtk_window_move()` which is honored on X11 and best-effort on Wayland compositors. Pinned top-right positioning via `gtk4-layer-shell` is out of scope for this iteration.
- Window type: undecorated `GtkWindow`, no title bar, no taskbar entry.
- **Popup lifecycle**: The `GtkWindow` for the popup is created once at app startup (hidden immediately after creation). It is never destroyed — only shown and hidden. This avoids Wayland surface errors that occur when `GtkWindow` instances are created outside the GTK main loop's activate signal.

### Popup Structure

```
┌─────────────────────────────────┐
│ CodexBar              ↻ hace Xm │  ← header
├─────────────────────────────────┤
│ [logo] Claude         ● Oper.   │  ← provider card
│         1h  ████░░░░░░   65%    │
│         Day █░░░░░░░░░   88%    │
├─────────────────────────────────┤
│ [logo] Codex          ● Oper.   │
│         5h  ████████░   28% ⚠   │  ← red % when low
├─────────────────────────────────┤
│ ...more providers (scrollable)  │
├─────────────────────────────────┤
│                        ⚙  ↻  ✕ │  ← footer, icons only
└─────────────────────────────────┘
```

### Provider Cards
- Each enabled provider with data gets one card.
- **Logo**: 18×18px rounded container with brand background color + 12×12 white SVG icon loaded from a compiled GResource bundle. Providers without a bundled icon fall back to an 18×18 rounded square with brand color and a white initial letter rendered via Pango.
- **Name**: provider display name (bold).
- **Status dot**: colored circle derived from `LinuxProviderCard.statusLevel` (new field — see §6). Green = operational, yellow = degraded, red = incident/error. Omitted if `statusLevel == nil`.
- **Usage bars**: one per window (1h, Day, Week, Month as available). Shows remaining % by default. Bar and percentage text turn red when < 20% remaining.
- Cards separated by a 1px divider.
- Empty state: single "No providers configured." dim label.

### Footer Buttons (icons only)
Tooltips are in Spanish (no i18n system in scope for this iteration):

| Button  | Icon | Color | Tooltip      | Action                              |
|---------|------|-------|--------------|-------------------------------------|
| Prefs   | ⚙   | blue  | Preferencias | Show/raise full preferences window  |
| Refresh | ↻   | dim   | Actualizar   | Trigger data refresh                |
| Quit    | ✕   | red   | Salir        | `g_application_quit()`              |

### Stored Properties (additions to `LinuxWindowController`)
New fields needed to support the popup UI after build time:
- `popupWindow: UnsafeMutablePointer<GtkWindow>?` — the persistent undecorated popup
- `popupCardsBox: LinuxWidgetPtr?` — the vertical box holding provider card widgets (re-rendered on refresh)
- `popupHeaderTimestampLabel: LinuxWidgetPtr?` — the "↻ hace X min" label in the header
- `preferencesWindow: LinuxWindowPtr?` — the existing full preferences window (built lazily on first open, then shown/hidden)

---

## 4. Tray Icon via StatusNotifierItem (D-Bus)

### Why not `libayatana-appindicator3`
`libayatana-appindicator3` links against GTK3 (`libgtk-3.so`). GTK3 and GTK4 cannot safely coexist in the same process — they share global GType registrations and Pango state. Loading both will crash at runtime. Since the rest of the app uses GTK4/Adwaita, `libayatana-appindicator3` is not usable here.

### Solution: Direct D-Bus SNI
The `org.kde.StatusNotifierItem` protocol is a D-Bus interface. GLib (`<gio/gio.h>`) provides `GDBusConnection`, which is already available through the existing Adwaita/GLib dependency chain. No additional library is needed.

### D-Bus Registration Flow
1. Acquire a unique bus name: `org.kde.StatusNotifierItem-<pid>-1`.
2. Register a D-Bus object at `/StatusNotifierItem` implementing:
   - **Interface**: `org.kde.StatusNotifierItem`
   - **Required properties**: `Category` = `"ApplicationStatus"`, `Id` = `"codexbar"`, `Title` = `"CodexBar"`, `Status` = `"Active"`, `IconName` = `"codexbar"` (themed icon or absolute path).
   - **Methods**: `Activate(x: Int32, y: Int32)`, `ContextMenu(x: Int32, y: Int32)`, `Scroll(delta: Int32, orientation: String)` (ignored).
3. Call `RegisterStatusNotifierItem` on `org.kde.StatusNotifierWatcher` to become visible to the shell.
4. Emit `NewStatus` signal when app state changes (not needed for v1).

### GNOME Compatibility
GNOME Shell does not natively support SNI. The **AppIndicator/KStatusNotifierItem** GNOME Shell extension reads the D-Bus registrations and shows the icon. Without it the tray icon is invisible. The app still functions — users launch Preferences via the `.desktop` file. This is the same limitation as `libayatana-appindicator3` and requires no change to the approach.

---

## 5. New C Bridge Functions

### In existing `CodexBarLinuxUIBridge.h`

```c
// Undecorated plain GtkWindow (for the compact popup)
GtkWindow *codexbar_linux_plain_window_new(void);
void codexbar_linux_plain_window_move(GtkWindow *window, int x, int y);
void codexbar_linux_window_set_decorated(GtkWindow *window, gboolean decorated);
void codexbar_linux_window_set_skip_taskbar(GtkWindow *window, gboolean skip);
void codexbar_linux_plain_window_present(GtkWindow *window);
void codexbar_linux_plain_window_hide(GtkWindow *window);

// GTK PopoverMenu at absolute screen coordinates (for right-click context menu)
void codexbar_linux_show_context_menu_at(GtkWindow *parent, int x, int y,
    const char **labels, int count,
    CodexBarLinuxWidgetCallback callback, void *user_data);

// Image widget from GResource path (e.g. "/com/steipete/codexbar/icons/anthropic.svg")
GtkWidget *codexbar_linux_image_from_resource(const char *resource_path, int size);
```

Note: `LinuxWindowPtr` in Swift is `UnsafeMutablePointer<AdwApplicationWindow>`. The popup uses `UnsafeMutablePointer<GtkWindow>` (a new typealias `LinuxPlainWindowPtr`) to keep types distinct.

### New file: `CodexBarLinuxSNIBridge.h` + `sni_bridge.c`

No new system library target is needed — GLib/GIO is already linked via Adwaita. The SNI bridge is a new `.c` file inside `Sources/CodexBarLinuxUIBridge/`.

```c
// CodexBarLinuxSNIBridge.h (included by CodexBarLinuxUIBridge.h)
typedef void (*CodexBarLinuxSNIActivateCallback)(int x, int y, void *user_data);
typedef void (*CodexBarLinuxSNIContextMenuCallback)(int x, int y, void *user_data);

// Returns FALSE and sets error if registration fails (watcher not present, etc.)
gboolean codexbar_linux_sni_register(
    AdwApplication *app,
    const char *icon_name,
    CodexBarLinuxSNIActivateCallback activate_cb,
    CodexBarLinuxSNIContextMenuCallback context_menu_cb,
    void *user_data,
    GError **error);

void codexbar_linux_sni_unregister(void);
```

The implementation in `sni_bridge.c` uses `g_dbus_connection_register_object()` with an inline GVariant-based introspection XML for the `org.kde.StatusNotifierItem` interface.

---

## 6. Data Model Change — `LinuxProviderCard`

Add a `statusLevel` field to `LinuxProviderCard` in `LinuxPresentation.swift`:

```swift
public enum LinuxStatusLevel: Sendable {
    case operational   // green dot
    case degraded      // yellow dot
    case incident      // red dot
}

public struct LinuxProviderCard: Sendable {
    // ...existing fields unchanged...
    public let statusLevel: LinuxStatusLevel?   // NEW — nil if no status data
}
```

`LinuxDashboardPresenter.makeCard(from:options:)` populates `statusLevel` from `payload.status?.indicator`:
- `.none` / `.operational` → `.operational`
- `.degraded` → `.degraded`
- `.majorOutage` / `.partialOutage` / `.critical` → `.incident`
- Non-nil `payload.error` → `.incident`
- `payload.status == nil` and no error → `nil`

This change cascades into `TestsLinux` — all `LinuxProviderCard` construction in tests must be updated to pass `statusLevel:`.

---

## 7. Provider Logos

### Strategy
Bundle SVG files from [Simple Icons](https://simpleicons.org) as a compiled GResource bundle inside the `CodexBarLinux` executable target.

- `Scripts/download-icons.sh` fetches SVGs from `cdn.simpleicons.org/{slug}/ffffff` into `Sources/CodexBarLinux/Resources/icons/` if not already present.
- `Sources/CodexBarLinux/Resources/icons.gresource.xml` lists all icon files.
- Icons are committed to the repo; no network needed at build time.

### SVG Rendering
Use `gtk_image_new_from_resource()` — GTK4 handles SVG resources natively on Ubuntu (via the built-in SVG loader in `gdk-pixbuf`/`librsvg2` which is a standard GTK4 dependency on Ubuntu). The icon is loaded at 12×12px, placed inside an 18×18 container widget with CSS `background-color: <brand-hex>; border-radius: 4px`.

Fallback: if the resource path is not found, render a `GtkLabel` with a single initial letter, same background.

### Provider Logo Table

| Provider        | Simple Icons slug | Brand bg color |
|-----------------|-------------------|----------------|
| Claude          | `anthropic`       | `#CC785C`      |
| Codex           | `openai`          | `#1A1A1A`      |
| Cursor          | `cursor`          | `#1C1C1E`      |
| GitHub Copilot  | `githubcopilot`   | `#24292E`      |
| OpenRouter      | `openrouter`      | `#6467F2`      |
| JetBrains       | `jetbrains`       | `#000000`      |
| OpenCode        | `opencode`        | `#2D6CDF`      |

---

## 8. Build System Changes (`Package.swift`)

### No new system library target
The SNI bridge uses only GLib/GIO headers already available through the existing `CAdwaita` / Adwaita dependency. No `CAppIndicator` target is needed.

### GResource compilation
SPM does not natively run `glib-compile-resources`. The chosen approach is a **pre-build shell script** invoked via a `Makefile` target (not a SPM `BuildToolPlugin`, which would require a separate plugin package):

- `Makefile` target `icons`: runs `Scripts/download-icons.sh` then `glib-compile-resources --sourcedir=... icons.gresource.xml --target=...`
- The compiled `.gresource` file is linked into the `CodexBarLinuxUIBridge` C target via `linkerSettings: [.linkedLibrary("..."), .unsafeFlags(["-Wl,--whole-archive", "codexbar.gresource", "-Wl,--no-whole-archive"])]`, or more portably, the resource blob is embedded as a C array via `glib-compile-resources --generate-source` which produces a `.c` file that can be added directly to the `Sources/CodexBarLinuxUIBridge/` directory and compiled as part of the existing C target.

**Chosen approach**: `--generate-source` (produces `icons.gresource.c`) → add to `Sources/CodexBarLinuxUIBridge/` → compiled automatically by SPM as part of `CodexBarLinuxUIBridge`. The `Scripts/download-icons.sh && glib-compile-resources --generate-source ...` step is run once manually (or in CI before `swift build`) and the output `.c` file is committed to the repo alongside the SVG sources.

---

## 9. Swift-Side Changes (`main.swift`)

`LinuxWindowController` gains these new fields:
```swift
private typealias LinuxPlainWindowPtr = UnsafeMutablePointer<GtkWindow>

private var sniRegistered = false
private var popupWindow: LinuxPlainWindowPtr?
private var popupCardsBox: LinuxWidgetPtr?
private var popupHeaderTimestampLabel: LinuxWidgetPtr?
private var preferencesWindow: LinuxWindowPtr?   // lazily built
```

New methods:
- `buildAndHidePopup()` — called from `handleActivate`, builds popup window and immediately hides it.
- `buildPreferencesWindow()` — extracted from existing `buildWindow()`, called lazily on first ⚙ click.
- `togglePopup(x:y:)` — called from SNI `Activate` callback; shows popup at (x, y) if hidden, hides if visible.
- `showContextMenu(x:y:)` — called from SNI `ContextMenu` callback.
- `updatePopupCards(snapshot:)` — remove-all on `popupCardsBox` + re-append cards; called after each refresh.

App startup no longer calls `codexbar_linux_window_present`. The SNI is registered inside `handleActivate`.

---

## 10. Dependencies

### Runtime (new)
- None — GLib/GIO already linked via Adwaita.

### Build (new)
- `glib-compile-resources` from `libglib2.0-dev-bin` (standard on Ubuntu dev environments).

### SVG Icons
Downloaded once via `Scripts/download-icons.sh`, committed to `Sources/CodexBarLinux/Resources/icons/`.
The generated `icons.gresource.c` is also committed.

---

## 11. Out of Scope

- Pinned top-right positioning on Wayland (requires `gtk4-layer-shell`, tracked separately).
- Desktop notifications.
- Launch at login.
- Animated tray icon showing live usage.
- Clicking a provider card to open a detail view.
- i18n / locale detection (UI language is Spanish for now).
- SNI `NewStatus` signal / dynamic icon updates.

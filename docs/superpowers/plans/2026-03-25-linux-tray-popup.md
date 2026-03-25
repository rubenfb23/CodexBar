# Linux Tray Icon + Compact Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the floating AdwApplicationWindow with an SNI D-Bus tray icon and a compact 280px popup showing provider usage cards with logos.

**Architecture:** A GLib D-Bus StatusNotifierItem is registered at startup (no AppIndicator/GTK3 dependency). Left-click/Activate toggles a persistent undecorated GtkWindow (the compact popup). The existing full tabbed window becomes the preferences window, opened lazily on demand.

**Tech Stack:** Swift 6, GTK4/Adwaita, GLib D-Bus (GIO), glib-compile-resources, Simple Icons SVGs.

**Spec:** `docs/superpowers/specs/2026-03-25-linux-tray-popup-design.md`

---

## File Map

| File | Change |
|------|--------|
| `Sources/CodexBarLinuxSupport/LinuxPresentation.swift` | Add `LinuxStatusLevel` enum + `statusLevel` field to `LinuxProviderCard`; populate in `makeCard` |
| `TestsLinux/CodexBarLinuxSupportTests.swift` | Add `statusLevel` assertions to existing tests + new status level tests |
| `Scripts/download-icons.sh` | New: fetch SVGs from cdn.simpleicons.org for each provider |
| `Sources/CodexBarLinux/Resources/icons/icons.gresource.xml` | New: GResource manifest listing all icon SVGs |
| `Sources/CodexBarLinuxUIBridge/icons.gresource.c` | Generated (committed): GResource blob as C array, compiled by SPM automatically |
| `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h` | Add plain window + image + popover bridge declarations |
| `Sources/CodexBarLinuxUIBridge/bridge.c` | Implement plain window + image + popover functions |
| `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxSNIBridge.h` | New: SNI D-Bus callback types + `codexbar_linux_sni_register/unregister` declarations |
| `Sources/CodexBarLinuxUIBridge/sni_bridge.c` | New: full GDBus SNI implementation |
| `Sources/CodexBarLinux/main.swift` | Refactor: extract `buildPreferencesWindow`, add `buildAndHidePopup`, `togglePopup`, `updatePopupCards`, SNI wiring |

---

## Task 1: Add `statusLevel` to `LinuxProviderCard`

**Files:**
- Modify: `Sources/CodexBarLinuxSupport/LinuxPresentation.swift`
- Modify: `TestsLinux/CodexBarLinuxSupportTests.swift`

- [ ] **Step 1.1: Write failing tests for `statusLevel`**

Add to `TestsLinux/CodexBarLinuxSupportTests.swift`:

```swift
@Test
func presenterSetsOperationalStatusLevelFromIndicator() {
    let payload = LinuxProviderPayload(
        provider: "codex", account: nil, version: nil, source: "cli",
        status: LinuxProviderStatusPayload(
            indicator: .none,
            description: nil, updatedAt: nil, url: nil),
        usage: nil, credits: nil, openaiDashboard: nil, error: nil)

    let snapshot = LinuxDashboardPresenter.makeSnapshot(
        from: [payload], cliBinaryPath: "/tmp/cli",
        refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

    #expect(snapshot.cards[0].statusLevel == .operational)
}

@Test
func presenterSetsIncidentStatusLevelWhenErrorPresent() {
    let payload = LinuxProviderPayload(
        provider: "claude", account: nil, version: nil, source: "api",
        status: nil, usage: nil, credits: nil, openaiDashboard: nil,
        error: LinuxProviderErrorPayload(code: 1, message: "Bad token", kind: .provider))

    let snapshot = LinuxDashboardPresenter.makeSnapshot(
        from: [payload], cliBinaryPath: "/tmp/cli",
        refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

    #expect(snapshot.cards[0].statusLevel == .incident)
}

@Test
func presenterSetsNilStatusLevelWhenNoStatusData() {
    let payload = LinuxProviderPayload(
        provider: "codex", account: nil, version: nil, source: "cli",
        status: nil, usage: nil, credits: nil, openaiDashboard: nil, error: nil)

    let snapshot = LinuxDashboardPresenter.makeSnapshot(
        from: [payload], cliBinaryPath: "/tmp/cli",
        refreshedAt: Date(timeIntervalSince1970: 1_750_000_000))

    #expect(snapshot.cards[0].statusLevel == nil)
}
```

- [ ] **Step 1.2: Run tests — verify they fail to compile**

```bash
swift test --filter CodexBarLinuxTests 2>&1 | head -20
```

Expected: compile error — `LinuxProviderCard` has no `statusLevel` member.

- [ ] **Step 1.3: Add `LinuxStatusLevel` + `statusLevel` to `LinuxPresentation.swift`**

In `LinuxPresentation.swift`, after the existing imports, add the enum:

```swift
public enum LinuxStatusLevel: Sendable, Equatable {
    case operational   // green
    case degraded      // yellow
    case incident      // red
}
```

Add `statusLevel: LinuxStatusLevel?` to `LinuxProviderCard.init` (add parameter after `errorMessage`):

```swift
public let statusLevel: LinuxStatusLevel?

public init(
    providerID: String,
    title: String,
    subtitle: String,
    statusLine: String,
    metadataLine: String?,
    footerLine: String?,
    errorMessage: String?,
    statusLevel: LinuxStatusLevel?,   // NEW
    usageBars: [LinuxUsageBar])
{
    // ...existing assignments...
    self.statusLevel = statusLevel
}
```

Add a private helper to `LinuxDashboardPresenter`:

```swift
private static func statusLevel(for payload: LinuxProviderPayload) -> LinuxStatusLevel? {
    if payload.error != nil { return .incident }
    guard let indicator = payload.status?.indicator else { return nil }
    switch indicator {
    case .none, .operational: return .operational
    case .degraded: return .degraded
    case .majorOutage, .partialOutage, .critical: return .incident
    }
}
```

In `makeCard(from:options:)`, pass `statusLevel: self.statusLevel(for: payload)` to `LinuxProviderCard.init`.

- [ ] **Step 1.4: Run tests — all must pass**

```bash
swift test --filter CodexBarLinuxTests 2>&1 | tail -20
```

Expected: all tests pass including the 3 new ones.

- [ ] **Step 1.5: Commit**

```bash
git add Sources/CodexBarLinuxSupport/LinuxPresentation.swift TestsLinux/CodexBarLinuxSupportTests.swift
git commit -m "feat(linux): add statusLevel to LinuxProviderCard"
```

---

## Task 2: Icon Infrastructure (Download + GResource)

**Files:**
- Create: `Scripts/download-icons.sh`
- Create: `Sources/CodexBarLinux/Resources/icons/icons.gresource.xml`
- Generate + commit: `Sources/CodexBarLinuxUIBridge/icons.gresource.c`

- [ ] **Step 2.1: Create the download script**

Create `Scripts/download-icons.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ICONS_DIR="Sources/CodexBarLinux/Resources/icons"
mkdir -p "$ICONS_DIR"

# slug -> filename mapping (all fetched as white SVG on transparent bg)
declare -A ICONS=(
    ["anthropic"]="claude.svg"
    ["openai"]="codex.svg"
    ["cursor"]="cursor.svg"
    ["githubcopilot"]="copilot.svg"
    ["openrouter"]="openrouter.svg"
    ["jetbrains"]="jetbrains.svg"
    ["opencode"]="opencode.svg"
)

BASE_URL="https://cdn.simpleicons.org"

for slug in "${!ICONS[@]}"; do
    filename="${ICONS[$slug]}"
    dest="$ICONS_DIR/$filename"
    if [ ! -f "$dest" ]; then
        echo "Downloading $slug -> $filename"
        curl -sf "$BASE_URL/$slug/ffffff" -o "$dest" || {
            echo "  WARNING: $slug not found in Simple Icons, skipping"
        }
    else
        echo "  $filename already present, skipping"
    fi
done

echo "Icons ready in $ICONS_DIR"
```

```bash
chmod +x Scripts/download-icons.sh
```

- [ ] **Step 2.2: Create the GResource manifest**

Create `Sources/CodexBarLinux/Resources/icons/icons.gresource.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<gresources>
  <gresource prefix="/com/steipete/codexbar/icons">
    <file preprocess="xml-stripblanks">claude.svg</file>
    <file preprocess="xml-stripblanks">codex.svg</file>
    <file preprocess="xml-stripblanks">cursor.svg</file>
    <file preprocess="xml-stripblanks">copilot.svg</file>
    <file preprocess="xml-stripblanks">openrouter.svg</file>
    <file preprocess="xml-stripblanks">jetbrains.svg</file>
    <file preprocess="xml-stripblanks">opencode.svg</file>
  </gresource>
</gresources>
```

- [ ] **Step 2.3: Download icons and generate the C file**

```bash
# Download SVGs (skips any that fail — those providers get initial-letter fallback)
bash Scripts/download-icons.sh

# Generate the self-contained C file and place it in the C bridge target
glib-compile-resources \
    --sourcedir=Sources/CodexBarLinux/Resources/icons \
    --generate-source \
    --target=Sources/CodexBarLinuxUIBridge/icons.gresource.c \
    Sources/CodexBarLinux/Resources/icons/icons.gresource.xml
```

Expected: `Sources/CodexBarLinuxUIBridge/icons.gresource.c` created (~50KB). It contains a `__attribute__((constructor))` function that registers the resources at process startup — no explicit init call needed.

- [ ] **Step 2.4: Verify the binary compiles with the new C file**

```bash
swift build --target CodexBarLinuxUIBridge 2>&1 | tail -10
```

Expected: builds without errors.

- [ ] **Step 2.5: Commit**

```bash
git add Scripts/download-icons.sh \
        Sources/CodexBarLinux/Resources/icons/ \
        Sources/CodexBarLinuxUIBridge/icons.gresource.c
git commit -m "feat(linux): add provider icon SVGs and GResource bundle"
```

---

## Task 3: C Bridge — Plain Window + Image Functions

**Files:**
- Modify: `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h`
- Modify: `Sources/CodexBarLinuxUIBridge/bridge.c`

- [ ] **Step 3.1: Add declarations to the header**

In `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h`, append before the final newline:

```c
/* Plain undecorated GtkWindow (for the compact popup and context menu) */
GtkWindow *codexbar_linux_plain_window_new(void);
void codexbar_linux_plain_window_move(GtkWindow *window, int x, int y);
void codexbar_linux_plain_window_present(GtkWindow *window);
void codexbar_linux_plain_window_hide(GtkWindow *window);
void codexbar_linux_window_set_decorated(GtkWindow *window, gboolean decorated);
void codexbar_linux_window_set_skip_taskbar(GtkWindow *window, gboolean skip);
void codexbar_linux_window_set_keep_above(GtkWindow *window, gboolean keep_above);

/* Set the root child of a plain GtkWindow (equivalent to adw_application_window_set_content) */
void codexbar_linux_plain_window_set_child(GtkWindow *window, GtkWidget *child);

/* Widget visibility — used to toggle the popup window */
void codexbar_linux_widget_set_visible(GtkWidget *widget, gboolean visible);
gboolean codexbar_linux_widget_get_visible(GtkWidget *widget);

/* Apply an inline background color (hex, e.g. "#CC785C") and border-radius to a widget.
   Uses a per-widget GtkCssProvider — call once per widget. */
void codexbar_linux_widget_set_background_color(GtkWidget *widget, const char *css_color);

/* Icon loaded from a GResource path at the given pixel size */
GtkWidget *codexbar_linux_image_from_resource(const char *resource_path, int size);
```

- [ ] **Step 3.2: Implement in `bridge.c`**

Append to `Sources/CodexBarLinuxUIBridge/bridge.c`:

```c
GtkWindow *codexbar_linux_plain_window_new(void) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
    return GTK_WINDOW(window);
}

void codexbar_linux_plain_window_move(GtkWindow *window, int x, int y) {
    /* X11: respected. Wayland: compositor may ignore. */
#ifdef GDK_WINDOWING_X11
    gtk_window_move(window, x, y);
#else
    (void)window; (void)x; (void)y;
#endif
}

void codexbar_linux_plain_window_present(GtkWindow *window) {
    gtk_window_present(window);
}

void codexbar_linux_plain_window_hide(GtkWindow *window) {
    gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
}

void codexbar_linux_plain_window_set_child(GtkWindow *window, GtkWidget *child) {
    gtk_window_set_child(window, child);
}

void codexbar_linux_window_set_decorated(GtkWindow *window, gboolean decorated) {
    gtk_window_set_decorated(window, decorated);
}

void codexbar_linux_window_set_skip_taskbar(GtkWindow *window, gboolean skip) {
    gtk_window_set_skip_taskbar_hint(window, skip);
}

void codexbar_linux_window_set_keep_above(GtkWindow *window, gboolean keep_above) {
    gtk_window_set_keep_above(window, keep_above);
}

void codexbar_linux_widget_set_visible(GtkWidget *widget, gboolean visible) {
    gtk_widget_set_visible(widget, visible);
}

gboolean codexbar_linux_widget_get_visible(GtkWidget *widget) {
    return gtk_widget_get_visible(widget);
}

void codexbar_linux_widget_set_background_color(GtkWidget *widget, const char *css_color) {
    GtkCssProvider *provider = gtk_css_provider_new();
    gchar *css = g_strdup_printf(
        "* { background-color: %s; border-radius: 4px; min-width: 18px; min-height: 18px; }",
        css_color);
    gtk_css_provider_load_from_string(provider, css);
    g_free(css);
    gtk_style_context_add_provider(
        gtk_widget_get_style_context(widget),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

GtkWidget *codexbar_linux_image_from_resource(const char *resource_path, int size) {
    GtkWidget *image = gtk_image_new_from_resource(resource_path);
    if (image == NULL) return NULL;
    gtk_image_set_pixel_size(GTK_IMAGE(image), size);
    return image;
}
```

- [ ] **Step 3.3: Verify bridge compiles**

```bash
swift build --target CodexBarLinuxUIBridge 2>&1 | tail -10
```

Expected: no errors. Note: `gtk_window_move` and `gtk_window_set_skip_taskbar_hint` may produce deprecation warnings on GTK4 — these are acceptable for now.

- [ ] **Step 3.4: Commit**

```bash
git add Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h \
        Sources/CodexBarLinuxUIBridge/bridge.c
git commit -m "feat(linux): add plain window and image bridge functions"
```

---

## Task 4: C Bridge — SNI D-Bus Tray Icon

**Files:**
- Create: `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxSNIBridge.h`
- Create: `Sources/CodexBarLinuxUIBridge/sni_bridge.c`
- Modify: `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h` (add include)

The StatusNotifierItem (SNI) D-Bus interface is implemented using GLib's `GDBusConnection`. GIO is already available through `CAdwaita` → `libadwaita-1` pkgConfig chain.

- [ ] **Step 4.1: Create the SNI bridge header**

Create `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxSNIBridge.h`:

```c
#pragma once

#include <adwaita.h>

/* Called when the tray icon receives Activate(x, y) — use to toggle popup */
typedef void (*CodexBarLinuxSNIActivateCallback)(int x, int y, void *user_data);

/* Called when the tray icon receives ContextMenu(x, y) */
typedef void (*CodexBarLinuxSNIContextMenuCallback)(int x, int y, void *user_data);

/*
 * Register a StatusNotifierItem on the session D-Bus.
 * icon_name: themed icon name (e.g. "codexbar") or empty string to use the
 *            app's executable name.
 * Returns TRUE on success; sets error and returns FALSE if D-Bus is unavailable.
 *
 * GNOME Shell requires the AppIndicator/KStatusNotifierItem extension for the
 * icon to appear. Without it, the app still functions — registration is a no-op.
 */
gboolean codexbar_linux_sni_register(
    const char *icon_name,
    CodexBarLinuxSNIActivateCallback activate_cb,
    CodexBarLinuxSNIContextMenuCallback context_menu_cb,
    void *user_data,
    GError **error);

void codexbar_linux_sni_unregister(void);
```

- [ ] **Step 4.2: Add the include to the main bridge header**

At the bottom of `Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h`, add:

```c
#include "CodexBarLinuxSNIBridge.h"
```

- [ ] **Step 4.3: Implement `sni_bridge.c`**

Create `Sources/CodexBarLinuxUIBridge/sni_bridge.c`:

```c
#include "CodexBarLinuxSNIBridge.h"
#include <gio/gio.h>
#include <stdio.h>
#include <unistd.h>   /* getpid() */

/* --- D-Bus introspection XML for org.kde.StatusNotifierItem --- */
static const gchar SNI_INTROSPECTION_XML[] =
    "<node>"
    "  <interface name='org.kde.StatusNotifierItem'>"
    "    <property name='Category'       type='s' access='read'/>"
    "    <property name='Id'             type='s' access='read'/>"
    "    <property name='Title'          type='s' access='read'/>"
    "    <property name='Status'         type='s' access='read'/>"
    "    <property name='IconName'       type='s' access='read'/>"
    "    <property name='IconThemePath'  type='s' access='read'/>"
    "    <method name='Activate'>"
    "      <arg name='x' type='i' direction='in'/>"
    "      <arg name='y' type='i' direction='in'/>"
    "    </method>"
    "    <method name='ContextMenu'>"
    "      <arg name='x' type='i' direction='in'/>"
    "      <arg name='y' type='i' direction='in'/>"
    "    </method>"
    "    <method name='SecondaryActivate'>"
    "      <arg name='x' type='i' direction='in'/>"
    "      <arg name='y' type='i' direction='in'/>"
    "    </method>"
    "    <method name='Scroll'>"
    "      <arg name='delta'       type='i' direction='in'/>"
    "      <arg name='orientation' type='s' direction='in'/>"
    "    </method>"
    "    <signal name='NewStatus'><arg name='status' type='s'/></signal>"
    "  </interface>"
    "</node>";

/* --- Module-level state --- */
typedef struct {
    GDBusConnection *connection;
    guint            bus_owner_id;
    guint            object_id;
    gchar           *icon_name;
    CodexBarLinuxSNIActivateCallback      activate_cb;
    CodexBarLinuxSNIContextMenuCallback   context_menu_cb;
    void            *user_data;
} SNIState;

static SNIState g_sni = {0};

/* --- Property getter --- */
static GVariant *sni_get_property(
    GDBusConnection *conn,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *property_name,
    GError **error,
    gpointer user_data)
{
    (void)conn; (void)sender; (void)object_path;
    (void)interface_name; (void)error; (void)user_data;

    if (g_strcmp0(property_name, "Category")      == 0) return g_variant_new_string("ApplicationStatus");
    if (g_strcmp0(property_name, "Id")            == 0) return g_variant_new_string("codexbar");
    if (g_strcmp0(property_name, "Title")         == 0) return g_variant_new_string("CodexBar");
    if (g_strcmp0(property_name, "Status")        == 0) return g_variant_new_string("Active");
    if (g_strcmp0(property_name, "IconName")      == 0) return g_variant_new_string(g_sni.icon_name ? g_sni.icon_name : "dialog-information");
    if (g_strcmp0(property_name, "IconThemePath") == 0) return g_variant_new_string("");
    return NULL;
}

/* --- Method call dispatcher --- */
static void sni_method_call(
    GDBusConnection *conn,
    const gchar *sender,
    const gchar *object_path,
    const gchar *interface_name,
    const gchar *method_name,
    GVariant *parameters,
    GDBusMethodInvocation *invocation,
    gpointer user_data)
{
    (void)conn; (void)sender; (void)object_path;
    (void)interface_name; (void)user_data;

    gint32 x = 0, y = 0;

    if (g_strcmp0(method_name, "Activate") == 0 ||
        g_strcmp0(method_name, "SecondaryActivate") == 0) {
        g_variant_get(parameters, "(ii)", &x, &y);
        if (g_sni.activate_cb) g_sni.activate_cb((int)x, (int)y, g_sni.user_data);
    } else if (g_strcmp0(method_name, "ContextMenu") == 0) {
        g_variant_get(parameters, "(ii)", &x, &y);
        if (g_sni.context_menu_cb) g_sni.context_menu_cb((int)x, (int)y, g_sni.user_data);
    }
    /* Scroll: intentionally ignored */

    g_dbus_method_invocation_return_value(invocation, NULL);
}

static const GDBusInterfaceVTable SNI_VTABLE = {
    .method_call  = sni_method_call,
    .get_property = sni_get_property,
    .set_property = NULL,
};

/* --- Called once we own the bus name --- */
static void on_name_acquired(GDBusConnection *conn, const gchar *name, gpointer user_data) {
    (void)user_data;
    /* Register with the StatusNotifierWatcher so GNOME Shell picks us up */
    g_dbus_connection_call(
        conn,
        "org.kde.StatusNotifierWatcher",
        "/StatusNotifierWatcher",
        "org.kde.StatusNotifierWatcher",
        "RegisterStatusNotifierItem",
        g_variant_new("(s)", name),
        NULL,
        G_DBUS_CALL_FLAGS_NONE,
        -1, NULL, NULL, NULL);
}

static void on_name_lost(GDBusConnection *conn, const gchar *name, gpointer user_data) {
    (void)conn; (void)name; (void)user_data;
    /* StatusNotifierWatcher not present — tray icon invisible, app still runs */
}

/* --- Public API --- */
gboolean codexbar_linux_sni_register(
    const char *icon_name,
    CodexBarLinuxSNIActivateCallback activate_cb,
    CodexBarLinuxSNIContextMenuCallback context_menu_cb,
    void *user_data,
    GError **error)
{
    GDBusConnection *conn = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, error);
    if (!conn) return FALSE;

    GDBusNodeInfo *introspection = g_dbus_node_info_new_for_xml(SNI_INTROSPECTION_XML, error);
    if (!introspection) { g_object_unref(conn); return FALSE; }

    guint object_id = g_dbus_connection_register_object(
        conn,
        "/StatusNotifierItem",
        introspection->interfaces[0],
        &SNI_VTABLE,
        NULL, NULL, error);

    g_dbus_node_info_unref(introspection);

    if (!object_id) { g_object_unref(conn); return FALSE; }

    /* Store state before owning name so callbacks are ready */
    g_sni.connection      = conn;
    g_sni.object_id       = object_id;
    g_sni.icon_name       = g_strdup(icon_name ? icon_name : "dialog-information");
    g_sni.activate_cb     = activate_cb;
    g_sni.context_menu_cb = context_menu_cb;
    g_sni.user_data       = user_data;

    gchar *bus_name = g_strdup_printf("org.kde.StatusNotifierItem-%d-1", (int)getpid());
    g_sni.bus_owner_id = g_bus_own_name_on_connection(
        conn, bus_name,
        G_BUS_NAME_OWNER_FLAGS_NONE,
        on_name_acquired, on_name_lost,
        NULL, NULL);
    g_free(bus_name);

    return TRUE;
}

void codexbar_linux_sni_unregister(void) {
    if (g_sni.bus_owner_id) {
        g_bus_unown_name(g_sni.bus_owner_id);
        g_sni.bus_owner_id = 0;
    }
    if (g_sni.connection && g_sni.object_id) {
        g_dbus_connection_unregister_object(g_sni.connection, g_sni.object_id);
        g_sni.object_id = 0;
    }
    if (g_sni.connection) {
        g_object_unref(g_sni.connection);
        g_sni.connection = NULL;
    }
    g_free(g_sni.icon_name);
    g_sni.icon_name = NULL;
}
```

- [ ] **Step 4.4: Build and verify**

```bash
swift build --target CodexBarLinuxUIBridge 2>&1 | tail -15
```

Expected: no errors. `getpid()` requires `<unistd.h>` — add `#include <unistd.h>` at the top of `sni_bridge.c` if the compiler reports it missing.

- [ ] **Step 4.5: Commit**

```bash
git add Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxSNIBridge.h \
        Sources/CodexBarLinuxUIBridge/include/CodexBarLinuxUIBridge.h \
        Sources/CodexBarLinuxUIBridge/sni_bridge.c
git commit -m "feat(linux): add SNI D-Bus tray registration bridge"
```

---

## Task 5: Swift — Popup Window (Cards + Footer)

**Files:**
- Modify: `Sources/CodexBarLinux/main.swift`

This task extracts preferences window building out of `buildWindow()` and adds the compact popup window. The app still compiles and runs — but tray icon is not wired yet (Task 6).

- [ ] **Step 5.1: Add new type aliases and stored properties**

At the top of `CodexBarLinuxApp` / `LinuxWindowController` in `main.swift`, add:

```swift
private typealias LinuxPlainWindowPtr = UnsafeMutablePointer<GtkWindow>
```

In `LinuxWindowController`, add alongside existing properties:

```swift
// Popup window (compact, undecorated — built once and hidden)
private var popupWindow: LinuxPlainWindowPtr?
private var popupCardsBox: LinuxWidgetPtr?
private var popupHeaderTimestampLabel: LinuxWidgetPtr?
// Preferences window (existing full tabbed window — built lazily)
private var preferencesWindow: LinuxWindowPtr?
private var sniRegistered = false
```

- [ ] **Step 5.2: Extract `buildPreferencesWindow()` from `buildWindow()`**

Rename the existing `buildWindow(application:)` to `buildPreferencesWindow(application:)`. No logic changes — just the name. The existing `handleActivate` call `self.buildWindow(application: application)` changes to `self.buildPreferencesWindow(application: application)` and stores the result in `self.preferencesWindow` instead of `self.window`.

Also update the `handleActivate` method: instead of calling `codexbar_linux_window_present` on startup, only build the popup and register SNI (Task 6 wires SNI). For now keep `codexbar_linux_window_present` so the app still opens a window on launch during development.

- [ ] **Step 5.3: Add `buildAndHidePopup()`**

```swift
private func buildAndHidePopup() {
    let popupWindow = requireValue(
        codexbar_linux_plain_window_new(),
        "Failed to create popup window.")
    self.popupWindow = popupWindow

    codexbar_linux_window_set_decorated(popupWindow, 0)
    codexbar_linux_window_set_skip_taskbar(popupWindow, 1)
    codexbar_linux_window_set_keep_above(popupWindow, 1)

    let root = requireValue(codexbar_linux_box_new_vertical(0), "Failed to create popup root.")

    // --- Header ---
    let header = requireValue(codexbar_linux_box_new_horizontal(0), "Failed to create popup header.")
    codexbar_linux_widget_set_margin_all(header, 12)
    let titleLabel = self.makeLabel(text: "CodexBar", xalign: 0, wrap: false, cssClasses: ["title-4"])
    codexbar_linux_widget_set_hexpand(titleLabel, 1)
    let timestampLabel = self.makeLabel(text: "", xalign: 1, wrap: false, cssClasses: ["dim-label"])
    self.popupHeaderTimestampLabel = timestampLabel
    codexbar_linux_box_append(header, titleLabel)
    codexbar_linux_box_append(header, timestampLabel)
    codexbar_linux_box_append(root, header)
    codexbar_linux_box_append(root, codexbar_linux_separator_new())

    // --- Scrollable cards area ---
    let scroll = requireValue(codexbar_linux_scrolled_window_new(), "Failed to create popup scroll.")
    codexbar_linux_widget_set_vexpand(scroll, 1)
    let cardsBox = requireValue(codexbar_linux_box_new_vertical(0), "Failed to create cards box.")
    codexbar_linux_widget_set_margin_all(cardsBox, 8)
    self.popupCardsBox = cardsBox
    codexbar_linux_scrolled_window_set_child(scroll, cardsBox)
    codexbar_linux_box_append(root, scroll)

    codexbar_linux_box_append(root, codexbar_linux_separator_new())

    // --- Footer (icon buttons only) ---
    let footer = requireValue(codexbar_linux_box_new_horizontal(4), "Failed to create popup footer.")
    codexbar_linux_widget_set_margin_all(footer, 8)
    codexbar_linux_widget_set_hexpand(footer, 1)

    let spacer = requireValue(codexbar_linux_box_new_horizontal(0), "Failed to create spacer.")
    codexbar_linux_widget_set_hexpand(spacer, 1)
    codexbar_linux_box_append(footer, spacer)

    codexbar_linux_box_append(footer, self.makeButton(title: "⚙") { [weak self] _ in
        self?.showPreferences()
    })
    codexbar_linux_box_append(footer, self.makeButton(title: "↻") { [weak self] _ in
        self?.refresh()
    })
    codexbar_linux_box_append(footer, self.makeButton(title: "✕") { [weak self] _ in
        guard let self else { return }
        if let application = self.application {
            g_application_quit(G_APPLICATION(application))
        }
    })
    codexbar_linux_box_append(root, footer)

    codexbar_linux_plain_window_set_child(popupWindow, root)
    codexbar_linux_widget_set_visible(GTK_WIDGET(popupWindow), 0)
}
```

Note: `gtk_window_set_child` and `GTK_WIDGET`/`G_APPLICATION` macros are available via `CAdwaita`. Since `GtkWindow` and `AdwApplicationWindow` both map through the C bridge, call them via the bridge wrapper functions where possible, or cast as needed.

- [ ] **Step 5.4: Add `updatePopupCards(snapshot:options:)` and `makePopupCard(_:)`**

```swift
private func updatePopupCards(snapshot: LinuxDashboardSnapshot, options: LinuxDashboardRenderOptions) {
    guard let popupCardsBox, let popupHeaderTimestampLabel else { return }

    // Update timestamp label
    let elapsed = Int(-snapshot.refreshedAt.timeIntervalSinceNow / 60)
    let timestampText = elapsed < 1 ? "just now" : "↻ \(elapsed) min ago"
    self.setLabelText(popupHeaderTimestampLabel, timestampText)

    // Rebuild cards
    codexbar_linux_box_remove_all(popupCardsBox)

    if snapshot.cards.isEmpty {
        let emptyLabel = self.makeLabel(
            text: "No providers configured.",
            xalign: 0.5, wrap: false, cssClasses: ["dim-label"])
        codexbar_linux_widget_set_margin_all(emptyLabel, 16)
        codexbar_linux_box_append(popupCardsBox, emptyLabel)
        return
    }

    var isFirst = true
    for card in snapshot.cards {
        if !isFirst {
            codexbar_linux_box_append(popupCardsBox, codexbar_linux_separator_new())
        }
        isFirst = false
        codexbar_linux_box_append(popupCardsBox, self.makePopupCard(card))
    }
}

private func makePopupCard(_ card: LinuxProviderCard) -> LinuxWidgetPtr {
    let cardBox = requireValue(codexbar_linux_box_new_vertical(6), "Failed to create popup card box.")
    codexbar_linux_widget_set_margin_all(cardBox, 10)

    // --- Title row: [logo] Name  ● Status ---
    let titleRow = requireValue(codexbar_linux_box_new_horizontal(7), "Failed to create card title row.")

    // Logo (try GResource, fallback to initial letter)
    let logoWidget = self.makeProviderLogo(providerID: card.providerID)
    codexbar_linux_box_append(titleRow, logoWidget)

    let nameLabel = self.makeLabel(text: card.title, xalign: 0, wrap: false, cssClasses: ["heading"])
    codexbar_linux_widget_set_hexpand(nameLabel, 1)
    codexbar_linux_box_append(titleRow, nameLabel)

    if let statusLevel = card.statusLevel {
        let dotColor: String
        switch statusLevel {
        case .operational: dotColor = "●"
        case .degraded:    dotColor = "●"
        case .incident:    dotColor = "●"
        }
        let statusCSSClass: String
        switch statusLevel {
        case .operational: statusCSSClass = "success"
        case .degraded:    statusCSSClass = "warning"
        case .incident:    statusCSSClass = "error"
        }
        let statusDot = self.makeLabel(
            text: dotColor, xalign: 1, wrap: false, cssClasses: [statusCSSClass])
        codexbar_linux_box_append(titleRow, statusDot)
    }
    codexbar_linux_box_append(cardBox, titleRow)

    // --- Usage bars ---
    for bar in card.usageBars {
        let barRow = requireValue(codexbar_linux_box_new_horizontal(6), "Failed to create bar row.")

        let windowLabel = self.makeLabel(text: bar.title, xalign: 1, wrap: false, cssClasses: [])
        codexbar_linux_widget_set_margin_all(windowLabel, 0)
        codexbar_linux_box_append(barRow, windowLabel)

        let progressBar = requireValue(codexbar_linux_progress_bar_new(), "Failed to create progress bar.")
        codexbar_linux_widget_set_hexpand(progressBar, 1)
        codexbar_linux_progress_bar_set_fraction(progressBar, bar.fractionFilled)
        codexbar_linux_box_append(barRow, progressBar)

        // Percentage label — red when < 20% remaining
        let pct = Int((bar.fractionFilled * 100).rounded())
        let pctText = "\(pct)%"
        let pctCSS = pct < 20 ? ["error"] : ["dim-label"]
        let pctLabel = self.makeLabel(text: pctText, xalign: 1, wrap: false, cssClasses: pctCSS)
        codexbar_linux_box_append(barRow, pctLabel)

        codexbar_linux_box_append(cardBox, barRow)
    }

    if let errorMessage = card.errorMessage {
        let errorLabel = self.makeLabel(text: errorMessage, xalign: 0, wrap: true, cssClasses: ["error"])
        codexbar_linux_box_append(cardBox, errorLabel)
    }

    return cardBox
}

private func makeProviderLogo(providerID: String) -> LinuxWidgetPtr {
    let resourceMap: [String: (path: String, bgColor: String)] = [
        "claude":    ("/com/steipete/codexbar/icons/claude.svg",    "#CC785C"),
        "codex":     ("/com/steipete/codexbar/icons/codex.svg",     "#1A1A1A"),
        "cursor":    ("/com/steipete/codexbar/icons/cursor.svg",     "#1C1C1E"),
        "copilot":   ("/com/steipete/codexbar/icons/copilot.svg",    "#24292E"),
        "openrouter":("/com/steipete/codexbar/icons/openrouter.svg", "#6467F2"),
        "jetbrains": ("/com/steipete/codexbar/icons/jetbrains.svg",  "#000000"),
        "opencode":  ("/com/steipete/codexbar/icons/opencode.svg",   "#2D6CDF"),
    ]

    if let entry = resourceMap[providerID],
       let imageWidget = entry.path.withCString({ codexbar_linux_image_from_resource($0, 12) })
    {
        // Wrap image in a box and apply brand background color via CSS provider
        let container = requireValue(codexbar_linux_box_new_horizontal(0), "container")
        entry.bgColor.withCString { codexbar_linux_widget_set_background_color(container, $0) }
        codexbar_linux_box_append(container, imageWidget)
        return container
    }

    // Fallback: initial letter
    let initial = String(providerID.prefix(1).uppercased())
    return self.makeLabel(text: initial, xalign: 0.5, wrap: false, cssClasses: ["dim-label"])
}
```

- [ ] **Step 5.5: Add `showPreferences()`**

```swift
private func showPreferences() {
    guard let application else { return }
    if self.preferencesWindow == nil {
        self.buildPreferencesWindow(application: application)
    }
    if let preferencesWindow = self.preferencesWindow {
        codexbar_linux_window_present(preferencesWindow)
    }
}
```

- [ ] **Step 5.6: Build the executable and confirm no compile errors**

```bash
swift build --target CodexBarLinux 2>&1 | tail -20
```

Fix any Swift compile errors. The app should build. Running it at this point still shows the preferences window (tray not wired yet).

- [ ] **Step 5.7: Commit**

```bash
git add Sources/CodexBarLinux/main.swift
git commit -m "feat(linux): add compact popup window and card rendering"
```

---

## Task 6: Swift — Register SNI + Wire Toggle/Context Menu

**Files:**
- Modify: `Sources/CodexBarLinux/main.swift`

- [ ] **Step 6.1: Add SNI callback free functions**

Below the existing `codexbarLinuxActivateCallback` free function, add:

```swift
private func codexbarLinuxSNIActivateCallback(_ x: Int32, _ y: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.togglePopup(x: Int(x), y: Int(y))
}

private func codexbarLinuxSNIContextMenuCallback(_ x: Int32, _ y: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let controller = Unmanaged<LinuxWindowController>.fromOpaque(userData).takeUnretainedValue()
    controller.showContextMenu(x: Int(x), y: Int(y))
}
```

- [ ] **Step 6.2: Add `togglePopup(x:y:)` and `showContextMenu(x:y:)`**

```swift
func togglePopup(x: Int, y: Int) {
    guard let popupWindow else { return }
    // Cast GtkWindow* to GtkWidget* via the bridge wrapper
    let popupWidget = UnsafeMutablePointer<GtkWidget>(OpaquePointer(popupWindow))
    let isVisible = codexbar_linux_widget_get_visible(popupWidget) != 0
    if isVisible {
        codexbar_linux_plain_window_hide(popupWindow)
    } else {
        // Position near tray icon (X11: respected; Wayland: compositor decides)
        codexbar_linux_plain_window_move(popupWindow, Int32(x - 280), Int32(y + 4))
        codexbar_linux_plain_window_present(popupWindow)
    }
}

func showContextMenu(x: Int, y: Int) {
    // Build a small undecorated window entirely from existing bridge functions.
    // A new window is created each time (not retained) — it destroys itself on hide.
    let menuWindow = requireValue(codexbar_linux_plain_window_new(), "Failed to create context menu window.")
    codexbar_linux_plain_window_move(menuWindow, Int32(x), Int32(y))

    let box = requireValue(codexbar_linux_box_new_vertical(0), "Failed to create context menu box.")
    codexbar_linux_widget_add_css_class(box, "menu")

    // Helper: adds a flat button that hides the menu window after running action
    func addItem(_ title: String, action: @escaping () -> Void) {
        codexbar_linux_box_append(box, self.makeButton(title: title) { [weak menuWindow] _ in
            if let menuWindow { codexbar_linux_plain_window_hide(menuWindow) }
            action()
        })
    }

    addItem("Show / Hide") { [weak self] in self?.togglePopup(x: x, y: y) }
    codexbar_linux_box_append(box, codexbar_linux_separator_new())
    addItem("↻  Actualizar") { [weak self] in self?.refresh() }
    addItem("⚙  Preferencias") { [weak self] in self?.showPreferences() }
    addItem("✕  Salir") { [weak self] in
        guard let self, let application = self.application else { return }
        g_application_quit(G_APPLICATION(application))
    }

    codexbar_linux_plain_window_set_child(menuWindow, box)
    codexbar_linux_plain_window_present(menuWindow)
}
```

- [ ] **Step 6.3: Update `handleActivate` to register SNI and build popup**

In `handleActivate(application:)`, replace the block that calls `buildWindow`:

```swift
func handleActivate(application: LinuxAppPtr?) {
    guard let application, let retainedPointer else { return }

    // Build popup (once) — always present, toggled show/hide
    if self.popupWindow == nil {
        self.buildAndHidePopup()
    }

    // Register SNI tray icon (once)
    if !self.sniRegistered {
        var sniError: UnsafeMutablePointer<GError>? = nil
        let registered = "codexbar".withCString { iconName in
            codexbar_linux_sni_register(
                iconName,
                codexbarLinuxSNIActivateCallback,
                codexbarLinuxSNIContextMenuCallback,
                retainedPointer,
                &sniError)
        }
        if registered != 0 {
            self.sniRegistered = true
        } else {
            // SNI unavailable (no D-Bus session) — fall back to opening preferences window
            print("CodexBar: SNI registration failed, falling back to preferences window")
            if self.preferencesWindow == nil {
                self.buildPreferencesWindow(application: application)
            }
            if let preferencesWindow = self.preferencesWindow {
                codexbar_linux_window_present(preferencesWindow)
            }
        }
        if let err = sniError { g_error_free(err) }
    }

    self.configureRefreshTimer()
    self.refresh()
}
```

- [ ] **Step 6.4: Update `applyRefreshResult` to also update popup cards**

In `applyRefreshResult(_:options:)`, after the existing `renderOverview` / `renderProvidersPage` etc. calls, add:

```swift
self.updatePopupCards(snapshot: snapshot, options: options)
```

- [ ] **Step 6.5: Build and run the app**

```bash
swift build --target CodexBarLinux 2>&1 | tail -20
.build/debug/CodexBarLinux
```

Expected behaviour:
- App launches without opening a window.
- If the **AppIndicator GNOME extension** is installed: a `CB` icon (or theme icon) appears in the top bar. Left-click toggles the popup. Right-click shows context menu.
- If the extension is not installed: no visible icon; press Ctrl+C to quit or check `~/.config/codexbar-linux/` for prefs.
- Popup shows provider cards with usage bars and ⚙ ↻ ✕ footer.
- ⚙ opens the preferences window.

- [ ] **Step 6.6: Commit**

```bash
git add Sources/CodexBarLinux/main.swift
git commit -m "feat(linux): wire SNI tray icon toggle and context menu"
```

---

## Task 7: Integration Smoke Test + Branch Cleanup

- [ ] **Step 7.1: Run the full test suite**

```bash
swift test --filter CodexBarLinuxTests 2>&1
```

Expected: all tests pass (no regressions from `statusLevel` change).

- [ ] **Step 7.2: Manual smoke test checklist**

With the AppIndicator GNOME extension installed (package: `gnome-shell-extension-appindicator`):

```
□ App starts without a window opening
□ Tray icon appears in top bar within 2 seconds
□ Left-click: popup appears near top-right
□ Left-click again: popup hides
□ Right-click: context menu appears at cursor position
□ Context menu "Show / Hide": toggles popup
□ Context menu "Actualizar": triggers refresh, timestamp updates
□ Context menu "Preferencias": opens the full tabbed preferences window
□ Context menu "Salir": app quits
□ Popup footer ⚙: opens preferences window
□ Popup footer ↻: triggers refresh
□ Popup footer ✕: app quits
□ Each provider card shows: logo (or initial), name, status dot, usage bars
□ Usage bar < 20%: percentage shown in red
□ Auto-refresh fires at configured interval and updates popup cards
```

Without the extension:

```
□ App starts and opens preferences window as fallback
□ All tabs work (Overview, Providers, General, Display, About)
□ Preferences window shows provider cards in Overview tab
```

- [ ] **Step 7.3: Final commit**

```bash
git add .
git commit -m "feat(linux): system tray icon with compact popup — complete

Replaces the floating AdwApplicationWindow with an SNI D-Bus tray icon
(no GTK3 dependency). Compact 280px popup shows provider cards with
Simple Icons logos, usage bars, and status dots. Falls back to the
preferences window when the AppIndicator GNOME extension is absent."
```

---

## Common Pitfalls

**`gtk_window_move` not found:** This API was deprecated but exists in GTK4 as `gtk_window_move` only on X11 builds. On Wayland-only builds it may not compile. Wrap with `#ifdef GDK_WINDOWING_X11`.

**GResource icons appear blank:** The SVG files from Simple Icons are white-on-transparent. They need a colored background container. Apply background via CSS class on the wrapping widget.

**SNI watcher not found:** `RegisterStatusNotifierItem` call will fail silently if `org.kde.StatusNotifierWatcher` is not on the bus. This is expected on GNOME without the extension. The `on_name_lost` callback handles this gracefully.

**`statusLevel` compiler error in tests:** The `makeSnapshot` call in existing tests doesn't need to change — `statusLevel` is populated internally by `makeCard`. Only direct `LinuxProviderCard.init` calls (if any exist) need the new parameter.

**Swift `withCString` and pointer lifetimes:** Never pass a `withCString` pointer outside the closure. The pattern `label.withCString { codexbar_linux_label_new($0) }` is safe because the C function copies the string internally.

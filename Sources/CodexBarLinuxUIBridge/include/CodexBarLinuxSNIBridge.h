#pragma once

#include <adwaita.h>

/* Called when the tray icon receives Activate(x, y) — use to toggle popup */
typedef void (*CodexBarLinuxSNIActivateCallback)(int x, int y, void *user_data);

/* Called when the tray icon receives ContextMenu(x, y) */
typedef void (*CodexBarLinuxSNIContextMenuCallback)(int x, int y, void *user_data);

/* Called when a com.canonical.dbusmenu item is clicked (item_id matches the menu item ID).
   For item_id = -1 the callback is fired by AboutToShow, not a menu click: x,y hold the
   current cursor position so the caller can show its popup window at the right location. */
typedef void (*CodexBarLinuxSNIMenuCallback)(int item_id, int x, int y, void *user_data);

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

/* Set the callback invoked when a dbusmenu item is clicked.
   Must be called with the same user_data pointer as sni_register. */
void codexbar_linux_sni_set_menu_callback(CodexBarLinuxSNIMenuCallback callback);

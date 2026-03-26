#include "CodexBarLinuxSNIBridge.h"
#include <unistd.h>   /* getpid() */
#ifdef GDK_WINDOWING_X11
#include <gdk/x11/gdkx.h>
#endif

/* --- D-Bus introspection XML for org.kde.StatusNotifierItem ---
 * Must include all properties the ubuntu-appindicators GNOME Shell extension
 * queries. Specifically 'Menu' (object path) is required: the extension calls
 * refreshProperty('Menu') up to three times; if it keeps failing it calls
 * destroy() and the tray icon disappears after ~3 seconds. */
static const gchar SNI_INTROSPECTION_XML[] =
    "<node>"
    "  <interface name='org.kde.StatusNotifierItem'>"
    "    <property name='Category'           type='s'       access='read'/>"
    "    <property name='Id'                 type='s'       access='read'/>"
    "    <property name='Title'              type='s'       access='read'/>"
    "    <property name='Status'             type='s'       access='read'/>"
    "    <property name='WindowId'           type='i'       access='read'/>"
    "    <property name='IconName'           type='s'       access='read'/>"
    "    <property name='IconThemePath'      type='s'       access='read'/>"
    "    <property name='IconPixmap'         type='a(iiay)' access='read'/>"
    "    <property name='OverlayIconName'    type='s'       access='read'/>"
    "    <property name='OverlayIconPixmap'  type='a(iiay)' access='read'/>"
    "    <property name='AttentionIconName'  type='s'       access='read'/>"
    "    <property name='AttentionIconPixmap' type='a(iiay)' access='read'/>"
    "    <property name='Menu'               type='o'       access='read'/>"
    "    <property name='ItemIsMenu'         type='b'       access='read'/>"
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
    guint            dbus_menu_object_id;
    gchar           *icon_name;
    CodexBarLinuxSNIActivateCallback      activate_cb;
    CodexBarLinuxSNIContextMenuCallback   context_menu_cb;
    CodexBarLinuxSNIMenuCallback          menu_cb;
    void            *user_data;
} SNIState;

static SNIState g_sni = {0};

/* --- Icon pixmap builder ---
 * Loads codexbar.png from the user's local icon directory and returns it as
 * SNI IconPixmap data (a(iiay), big-endian ARGB32).  This bypasses the icon
 * theme cache so the correct logo is always shown regardless of cache state. */
static GVariant *sni_build_icon_pixmap(int size) {
    const gchar *home = g_get_home_dir();
    /* Prefer the highest-resolution source we installed */
    static const int SOURCES[] = {256, 128, 64, 48, 32, 22, 0};
    GdkPixbuf *pixbuf = NULL;
    for (int i = 0; SOURCES[i] != 0 && !pixbuf; i++) {
        gchar *path = g_strdup_printf(
            "%s/.local/share/icons/hicolor/%dx%d/apps/codexbar.png",
            home ? home : "", SOURCES[i], SOURCES[i]);
        pixbuf = gdk_pixbuf_new_from_file_at_size(path, size, size, NULL);
        g_free(path);
    }
    if (!pixbuf) {
        return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0);
    }
    int w = gdk_pixbuf_get_width(pixbuf);
    int h = gdk_pixbuf_get_height(pixbuf);
    int n_ch = gdk_pixbuf_get_n_channels(pixbuf);
    int rowstride = gdk_pixbuf_get_rowstride(pixbuf);
    const guchar *pixels = gdk_pixbuf_get_pixels(pixbuf);
    /* Build raw ARGB byte array */
    GVariantBuilder argb;
    g_variant_builder_init(&argb, G_VARIANT_TYPE("ay"));
    for (int row = 0; row < h; row++) {
        for (int col = 0; col < w; col++) {
            const guchar *p = pixels + row * rowstride + col * n_ch;
            guchar a = n_ch >= 4 ? p[3] : 0xFF;
            g_variant_builder_add(&argb, "y", a);
            g_variant_builder_add(&argb, "y", p[0]);   /* R */
            g_variant_builder_add(&argb, "y", p[1]);   /* G */
            g_variant_builder_add(&argb, "y", p[2]);   /* B */
        }
    }
    GVariantBuilder entry;
    g_variant_builder_init(&entry, G_VARIANT_TYPE("(iiay)"));
    g_variant_builder_add(&entry, "i", (gint32)w);
    g_variant_builder_add(&entry, "i", (gint32)h);
    g_variant_builder_add_value(&entry, g_variant_builder_end(&argb));
    GVariantBuilder arr;
    g_variant_builder_init(&arr, G_VARIANT_TYPE("a(iiay)"));
    g_variant_builder_add_value(&arr, g_variant_builder_end(&entry));
    g_object_unref(pixbuf);
    return g_variant_builder_end(&arr);
}

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

    if (g_strcmp0(property_name, "Category")            == 0) return g_variant_new_string("ApplicationStatus");
    if (g_strcmp0(property_name, "Id")                  == 0) return g_variant_new_string("codexbar");
    if (g_strcmp0(property_name, "Title")               == 0) return g_variant_new_string("CodexBar");
    if (g_strcmp0(property_name, "Status")              == 0) return g_variant_new_string("Active");
    if (g_strcmp0(property_name, "WindowId")            == 0) return g_variant_new_int32(0);
    if (g_strcmp0(property_name, "IconName")            == 0) return g_variant_new_string(g_sni.icon_name ? g_sni.icon_name : "dialog-information");
    if (g_strcmp0(property_name, "IconThemePath")       == 0) {
        /* Point at the user's local hicolor theme so the appindicator shell extension
         * finds codexbar.png without requiring a system-wide icon cache update. */
        const gchar *home = g_get_home_dir();
        return g_variant_new_take_string(
            g_strdup_printf("%s/.local/share/icons", home ? home : ""));
    }
    if (g_strcmp0(property_name, "IconPixmap")          == 0) return sni_build_icon_pixmap(32);
    if (g_strcmp0(property_name, "OverlayIconName")     == 0) return g_variant_new_string("");
    if (g_strcmp0(property_name, "OverlayIconPixmap")   == 0) return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0);
    if (g_strcmp0(property_name, "AttentionIconName")   == 0) return g_variant_new_string("");
    if (g_strcmp0(property_name, "AttentionIconPixmap") == 0) return g_variant_new_array(G_VARIANT_TYPE("(iiay)"), NULL, 0);
    /* Menu: any valid object path (not /NO_DBUSMENU) satisfies the extension's
     * _checkIfReady() check. We don't implement com.canonical.dbusmenu; the
     * DBusMenu.Client will fail silently when it can't find the interface here. */
    if (g_strcmp0(property_name, "Menu")                == 0) return g_variant_new_object_path("/StatusNotifierItem");
    if (g_strcmp0(property_name, "ItemIsMenu")          == 0) return g_variant_new_boolean(FALSE);
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

/* --- com.canonical.dbusmenu implementation ---
 *
 * ubuntu-appindicators@ubuntu.com does NOT forward left/right-click as SNI
 * Activate/ContextMenu calls.  Instead it fetches the DBusMenu via GetLayout
 * and renders it inside GNOME Shell.  Without this interface the tray icon
 * appears but clicks do nothing.
 */

static const gchar DBUSMENU_INTROSPECTION_XML[] =
    "<node>"
    "  <interface name='com.canonical.dbusmenu'>"
    "    <property name='Version'       type='u'  access='read'/>"
    "    <property name='TextDirection' type='s'  access='read'/>"
    "    <property name='Status'        type='s'  access='read'/>"
    "    <property name='IconThemePath' type='as' access='read'/>"
    "    <method name='GetLayout'>"
    "      <arg name='parentId'       type='i'          direction='in'/>"
    "      <arg name='recursionDepth' type='i'          direction='in'/>"
    "      <arg name='propertyNames'  type='as'         direction='in'/>"
    "      <arg name='revision'       type='u'          direction='out'/>"
    "      <arg name='layout'         type='(ia{sv}av)' direction='out'/>"
    "    </method>"
    "    <method name='GetGroupProperties'>"
    "      <arg name='ids'           type='ai'        direction='in'/>"
    "      <arg name='propertyNames' type='as'        direction='in'/>"
    "      <arg name='properties'    type='a(ia{sv})' direction='out'/>"
    "    </method>"
    "    <method name='GetProperty'>"
    "      <arg name='id'    type='i' direction='in'/>"
    "      <arg name='name'  type='s' direction='in'/>"
    "      <arg name='value' type='v' direction='out'/>"
    "    </method>"
    "    <method name='Event'>"
    "      <arg name='id'        type='i' direction='in'/>"
    "      <arg name='eventId'   type='s' direction='in'/>"
    "      <arg name='data'      type='v' direction='in'/>"
    "      <arg name='timestamp' type='u' direction='in'/>"
    "    </method>"
    "    <method name='EventGroup'>"
    "      <arg name='events'   type='a(isvu)' direction='in'/>"
    "      <arg name='idErrors' type='ai'      direction='out'/>"
    "    </method>"
    "    <method name='AboutToShow'>"
    "      <arg name='id'         type='i' direction='in'/>"
    "      <arg name='needUpdate' type='b' direction='out'/>"
    "    </method>"
    "    <method name='AboutToShowGroup'>"
    "      <arg name='ids'           type='ai' direction='in'/>"
    "      <arg name='updatesNeeded' type='ai' direction='out'/>"
    "      <arg name='idErrors'      type='ai' direction='out'/>"
    "    </method>"
    "    <signal name='ItemsPropertiesUpdated'>"
    "      <arg name='updatedProps' type='a(ia{sv})'/>"
    "      <arg name='removedProps' type='a(ias)'/>"
    "    </signal>"
    "    <signal name='LayoutUpdated'>"
    "      <arg name='revision' type='u'/>"
    "      <arg name='parent'   type='i'/>"
    "    </signal>"
    "    <signal name='ItemActivationRequested'>"
    "      <arg name='id'        type='i'/>"
    "      <arg name='timestamp' type='u'/>"
    "    </signal>"
    "  </interface>"
    "</node>";

/* Build a leaf menu item: (ia{sv}av) — no children */
static GVariant *dbusmenu_leaf(gint32 id, const char *type, const char *label) {
    GVariantBuilder props;
    g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
    if (type) {
        g_variant_builder_add(&props, "{sv}", "type", g_variant_new_string(type));
    }
    if (label) {
        g_variant_builder_add(&props, "{sv}", "label",   g_variant_new_string(label));
        g_variant_builder_add(&props, "{sv}", "enabled", g_variant_new_boolean(TRUE));
        g_variant_builder_add(&props, "{sv}", "visible", g_variant_new_boolean(TRUE));
    }
    GVariantBuilder no_children;
    g_variant_builder_init(&no_children, G_VARIANT_TYPE("av"));
    return g_variant_new("(ia{sv}av)", id, &props, &no_children);
}

static GVariant *dbusmenu_get_property(
    GDBusConnection *conn, const gchar *sender, const gchar *object_path,
    const gchar *interface_name, const gchar *property_name,
    GError **error, gpointer user_data)
{
    (void)conn; (void)sender; (void)object_path;
    (void)interface_name; (void)error; (void)user_data;
    if (g_strcmp0(property_name, "Version")       == 0) return g_variant_new_uint32(3);
    if (g_strcmp0(property_name, "TextDirection") == 0) return g_variant_new_string("ltr");
    if (g_strcmp0(property_name, "Status")        == 0) return g_variant_new_string("normal");
    if (g_strcmp0(property_name, "IconThemePath") == 0) {
        GVariantBuilder b;
        g_variant_builder_init(&b, G_VARIANT_TYPE("as"));
        return g_variant_builder_end(&b);
    }
    return NULL;
}

static void dbusmenu_method_call(
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

    if (g_strcmp0(method_name, "GetLayout") == 0) {
        /* Return an empty menu — interaction is handled via AboutToShow (popup window).
         * A non-empty children-display property is still set so the extension
         * considers the indicator valid and keeps calling AboutToShow on clicks. */
        GVariantBuilder root_children;
        g_variant_builder_init(&root_children, G_VARIANT_TYPE("av"));

        GVariantBuilder root_props;
        g_variant_builder_init(&root_props, G_VARIANT_TYPE("a{sv}"));
        g_variant_builder_add(&root_props, "{sv}", "children-display",
                              g_variant_new_string("submenu"));

        GVariant *layout = g_variant_new("(ia{sv}av)", 0, &root_props, &root_children);
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(u@(ia{sv}av))", 1u, layout));
        return;
    }

    if (g_strcmp0(method_name, "GetGroupProperties") == 0) {
        GVariantBuilder result;
        g_variant_builder_init(&result, G_VARIANT_TYPE("a(ia{sv})"));
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(@a(ia{sv}))", g_variant_builder_end(&result)));
        return;
    }

    if (g_strcmp0(method_name, "GetProperty") == 0) {
        /* Return an empty string variant as a safe default */
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(@v)", g_variant_new_variant(g_variant_new_string(""))));
        return;
    }

    if (g_strcmp0(method_name, "Event") == 0) {
        gint32 item_id = 0;
        gchar *event_id = NULL;
        GVariant *data = NULL;
        guint32 ts = 0;
        g_variant_get(parameters, "(is@vu)", &item_id, &event_id, &data, &ts);
        if (g_strcmp0(event_id, "clicked") == 0 && g_sni.menu_cb) {
            g_sni.menu_cb((int)item_id, 0, 0, g_sni.user_data);
        }
        g_free(event_id);
        if (data) g_variant_unref(data);
        g_dbus_method_invocation_return_value(invocation, NULL);
        return;
    }

    if (g_strcmp0(method_name, "EventGroup") == 0) {
        GVariant *events = NULL;
        g_variant_get(parameters, "(@a(isvu))", &events);
        if (events) {
            GVariantIter iter;
            g_variant_iter_init(&iter, events);
            gint32 item_id; gchar *event_id; GVariant *data; guint32 ts;
            while (g_variant_iter_next(&iter, "(is@vu)", &item_id, &event_id, &data, &ts)) {
                if (g_strcmp0(event_id, "clicked") == 0 && g_sni.menu_cb) {
                    g_sni.menu_cb((int)item_id, 0, 0, g_sni.user_data);
                }
                g_free(event_id);
                if (data) g_variant_unref(data);
            }
            g_variant_unref(events);
        }
        GVariantBuilder errors;
        g_variant_builder_init(&errors, G_VARIANT_TYPE("ai"));
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(@ai)", g_variant_builder_end(&errors)));
        return;
    }

    if (g_strcmp0(method_name, "AboutToShow") == 0) {
        /* ubuntu-appindicators calls AboutToShow(0) on every click.
         * We use this as the primary trigger to show the popup window at the
         * cursor position, bypassing the GNOME menu entirely. */
        int px = 0, py = 0;
#ifdef GDK_WINDOWING_X11
        GdkDisplay *display = gdk_display_get_default();
        if (GDK_IS_X11_DISPLAY(display)) {
            Display *xdisplay = gdk_x11_display_get_xdisplay(display);
            Window root = DefaultRootWindow(xdisplay);
            Window root_ret, child_ret;
            int wx = 0, wy = 0;
            unsigned int mask = 0;
            XQueryPointer(xdisplay, root, &root_ret, &child_ret, &px, &py, &wx, &wy, &mask);
        }
#endif
        if (g_sni.menu_cb) {
            /* item_id = -1 signals "show popup at (x, y)" rather than a menu item click */
            g_sni.menu_cb(-1, px, py, g_sni.user_data);
        }
        /* Return needUpdate = FALSE so the extension uses the cached (empty) layout
         * and does not render a GNOME dropdown menu on top of our popup. */
        g_dbus_method_invocation_return_value(invocation, g_variant_new("(b)", FALSE));
        return;
    }

    if (g_strcmp0(method_name, "AboutToShowGroup") == 0) {
        GVariantBuilder b1, b2;
        g_variant_builder_init(&b1, G_VARIANT_TYPE("ai"));
        g_variant_builder_init(&b2, G_VARIANT_TYPE("ai"));
        g_dbus_method_invocation_return_value(invocation,
            g_variant_new("(@ai@ai)", g_variant_builder_end(&b1), g_variant_builder_end(&b2)));
        return;
    }

    /* Unknown method — return empty success */
    g_dbus_method_invocation_return_value(invocation, NULL);
}

static const GDBusInterfaceVTable DBUSMENU_VTABLE = {
    .method_call  = dbusmenu_method_call,
    .get_property = dbusmenu_get_property,
    .set_property = NULL,
};

/* --- Called once we own the bus name --- */
static void on_name_acquired(GDBusConnection *conn, const gchar *name, gpointer user_data) {
    (void)user_data;

    /* Register com.canonical.dbusmenu at the same path as the SNI object.
     * ubuntu-appindicators reads the SNI 'Menu' property (/StatusNotifierItem)
     * and connects to dbusmenu there; without this interface clicks do nothing. */
    GDBusNodeInfo *dbusmenu_info = g_dbus_node_info_new_for_xml(DBUSMENU_INTROSPECTION_XML, NULL);
    if (dbusmenu_info) {
        g_sni.dbus_menu_object_id = g_dbus_connection_register_object(
            conn,
            "/StatusNotifierItem",
            dbusmenu_info->interfaces[0],
            &DBUSMENU_VTABLE,
            NULL, NULL, NULL);
        g_dbus_node_info_unref(dbusmenu_info);
    }

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
    (void)conn; (void)user_data;
    /* StatusNotifierWatcher not present or name was stolen — tray icon invisible, app still runs */
    g_warning("CodexBar SNI: lost bus name '%s' — tray icon will not be visible", name);
}

/* --- Public API --- */
gboolean codexbar_linux_sni_register(
    const char *icon_name,
    CodexBarLinuxSNIActivateCallback activate_cb,
    CodexBarLinuxSNIContextMenuCallback context_menu_cb,
    void *user_data,
    GError **error)
{
    /* Guard against double-registration (e.g. activate signal fired twice). */
    if (g_sni.connection != NULL) return TRUE;

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
    if (g_sni.connection && g_sni.dbus_menu_object_id) {
        g_dbus_connection_unregister_object(g_sni.connection, g_sni.dbus_menu_object_id);
        g_sni.dbus_menu_object_id = 0;
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

void codexbar_linux_sni_set_menu_callback(CodexBarLinuxSNIMenuCallback callback) {
    g_sni.menu_cb = callback;
}

#include "CodexBarLinuxSNIBridge.h"
#include <gio/gio.h>
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

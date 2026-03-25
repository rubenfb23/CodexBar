#include "CodexBarLinuxUIBridge.h"

typedef struct {
    CodexBarLinuxMainThreadCallback callback;
    void *user_data;
} CodexBarLinuxMainThreadInvocation;

void codexbar_linux_init(void) {
    adw_init();
}

static gboolean codexbar_linux_main_context_trampoline(gpointer data) {
    CodexBarLinuxMainThreadInvocation *invocation = data;
    invocation->callback(invocation->user_data);
    g_free(invocation);
    return G_SOURCE_REMOVE;
}

AdwApplication *codexbar_linux_application_new(const char *application_id) {
    return adw_application_new(application_id, G_APPLICATION_DEFAULT_FLAGS);
}

void codexbar_linux_application_on_activate(
    AdwApplication *app,
    CodexBarLinuxActivateCallback callback,
    void *user_data)
{
    g_signal_connect_data(app, "activate", G_CALLBACK(callback), user_data, NULL, 0);
}

int codexbar_linux_application_run(AdwApplication *app) {
    return g_application_run(G_APPLICATION(app), 0, NULL);
}

void codexbar_linux_application_hold(AdwApplication *app) {
    g_application_hold(G_APPLICATION(app));
}

AdwApplicationWindow *codexbar_linux_window_new(AdwApplication *app) {
    return ADW_APPLICATION_WINDOW(adw_application_window_new(GTK_APPLICATION(app)));
}

void codexbar_linux_window_set_title(AdwApplicationWindow *window, const char *title) {
    gtk_window_set_title(GTK_WINDOW(window), title);
}

void codexbar_linux_window_set_default_size(AdwApplicationWindow *window, int width, int height) {
    gtk_window_set_default_size(GTK_WINDOW(window), width, height);
}

void codexbar_linux_window_set_content(AdwApplicationWindow *window, GtkWidget *child) {
    adw_application_window_set_content(window, child);
}

void codexbar_linux_window_present(AdwApplicationWindow *window) {
    gtk_window_present(GTK_WINDOW(window));
}

GtkWidget *codexbar_linux_box_new_vertical(int spacing) {
    return gtk_box_new(GTK_ORIENTATION_VERTICAL, spacing);
}

GtkWidget *codexbar_linux_box_new_horizontal(int spacing) {
    return gtk_box_new(GTK_ORIENTATION_HORIZONTAL, spacing);
}

void codexbar_linux_box_append(GtkWidget *box, GtkWidget *child) {
    gtk_box_append(GTK_BOX(box), child);
}

void codexbar_linux_box_remove_all(GtkWidget *box) {
    GtkWidget *child = gtk_widget_get_first_child(box);
    while (child != NULL) {
        GtkWidget *next = gtk_widget_get_next_sibling(child);
        gtk_box_remove(GTK_BOX(box), child);
        child = next;
    }
}

GtkWidget *codexbar_linux_label_new(const char *text) {
    return gtk_label_new(text);
}

void codexbar_linux_label_set_text(GtkWidget *label, const char *text) {
    gtk_label_set_text(GTK_LABEL(label), text);
}

void codexbar_linux_label_set_wrap(GtkWidget *label, gboolean wrap) {
    gtk_label_set_wrap(GTK_LABEL(label), wrap);
}

void codexbar_linux_label_set_xalign(GtkWidget *label, float xalign) {
    gtk_label_set_xalign(GTK_LABEL(label), xalign);
}

GtkWidget *codexbar_linux_button_new(const char *label) {
    return gtk_button_new_with_label(label);
}

void codexbar_linux_button_on_clicked(GtkWidget *button, CodexBarLinuxWidgetCallback callback, void *user_data) {
    g_signal_connect_data(button, "clicked", G_CALLBACK(callback), user_data, NULL, 0);
}

GtkWidget *codexbar_linux_check_button_new(const char *label) {
    return gtk_check_button_new_with_label(label);
}

gboolean codexbar_linux_check_button_get_active(GtkWidget *check_button) {
    return gtk_check_button_get_active(GTK_CHECK_BUTTON(check_button));
}

void codexbar_linux_check_button_set_active(GtkWidget *check_button, gboolean active) {
    gtk_check_button_set_active(GTK_CHECK_BUTTON(check_button), active);
}

void codexbar_linux_check_button_on_toggled(
    GtkWidget *check_button,
    CodexBarLinuxWidgetCallback callback,
    void *user_data)
{
    g_signal_connect_data(check_button, "toggled", G_CALLBACK(callback), user_data, NULL, 0);
}

GtkWidget *codexbar_linux_progress_bar_new(void) {
    return gtk_progress_bar_new();
}

void codexbar_linux_progress_bar_set_fraction(GtkWidget *progress_bar, double fraction) {
    gtk_progress_bar_set_fraction(GTK_PROGRESS_BAR(progress_bar), fraction);
}

void codexbar_linux_progress_bar_set_text(GtkWidget *progress_bar, const char *text) {
    gtk_progress_bar_set_text(GTK_PROGRESS_BAR(progress_bar), text);
}

void codexbar_linux_progress_bar_set_show_text(GtkWidget *progress_bar, gboolean show_text) {
    gtk_progress_bar_set_show_text(GTK_PROGRESS_BAR(progress_bar), show_text);
}

GtkWidget *codexbar_linux_scrolled_window_new(void) {
    return gtk_scrolled_window_new();
}

void codexbar_linux_scrolled_window_set_child(GtkWidget *scrolled_window, GtkWidget *child) {
    gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(scrolled_window), child);
}

GtkWidget *codexbar_linux_frame_new(const char *label) {
    return gtk_frame_new(label);
}

void codexbar_linux_frame_set_child(GtkWidget *frame, GtkWidget *child) {
    gtk_frame_set_child(GTK_FRAME(frame), child);
}

GtkWidget *codexbar_linux_separator_new(void) {
    return gtk_separator_new(GTK_ORIENTATION_HORIZONTAL);
}

GtkWidget *codexbar_linux_stack_new(void) {
    return gtk_stack_new();
}

void codexbar_linux_stack_add_titled(
    GtkWidget *stack,
    GtkWidget *child,
    const char *name,
    const char *title)
{
    gtk_stack_add_titled(GTK_STACK(stack), child, name, title);
}

GtkWidget *codexbar_linux_stack_switcher_new(void) {
    return gtk_stack_switcher_new();
}

void codexbar_linux_stack_switcher_set_stack(GtkWidget *switcher, GtkWidget *stack) {
    gtk_stack_switcher_set_stack(GTK_STACK_SWITCHER(switcher), GTK_STACK(stack));
}

void codexbar_linux_widget_add_css_class(GtkWidget *widget, const char *class_name) {
    gtk_widget_add_css_class(widget, class_name);
}

void codexbar_linux_widget_set_hexpand(GtkWidget *widget, gboolean hexpand) {
    gtk_widget_set_hexpand(widget, hexpand);
}

void codexbar_linux_widget_set_vexpand(GtkWidget *widget, gboolean vexpand) {
    gtk_widget_set_vexpand(widget, vexpand);
}

void codexbar_linux_widget_set_margin_all(GtkWidget *widget, int margin) {
    gtk_widget_set_margin_top(widget, margin);
    gtk_widget_set_margin_bottom(widget, margin);
    gtk_widget_set_margin_start(widget, margin);
    gtk_widget_set_margin_end(widget, margin);
}

guint codexbar_linux_timeout_add_seconds(
    guint interval,
    CodexBarLinuxTimeoutCallback callback,
    void *user_data)
{
    return g_timeout_add_seconds(interval, callback, user_data);
}

void codexbar_linux_source_remove(guint source_id) {
    if (source_id != 0) {
        g_source_remove(source_id);
    }
}

void codexbar_linux_main_context_invoke(
    CodexBarLinuxMainThreadCallback callback,
    void *user_data)
{
    CodexBarLinuxMainThreadInvocation *invocation = g_new0(CodexBarLinuxMainThreadInvocation, 1);
    invocation->callback = callback;
    invocation->user_data = user_data;
    g_main_context_invoke(NULL, codexbar_linux_main_context_trampoline, invocation);
}

GtkWindow *codexbar_linux_plain_window_new(void) {
    GtkWidget *window = gtk_window_new();
    gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
    gtk_window_set_resizable(GTK_WINDOW(window), FALSE);
    return GTK_WINDOW(window);
}

void codexbar_linux_plain_window_move(GtkWindow *window, int x, int y) {
    /* gtk_window_move was removed in GTK4; positioning is compositor-controlled.
       Callers should position via display geometry hints or startup notification. */
    (void)window; (void)x; (void)y;
}

void codexbar_linux_plain_window_present(GtkWindow *window) {
    gtk_window_present(window);
}

void codexbar_linux_plain_window_hide(GtkWindow *window) {
    gtk_widget_set_visible(GTK_WIDGET(window), FALSE);
}

void codexbar_linux_plain_window_destroy(GtkWindow *window) {
    gtk_window_destroy(window);
}

void codexbar_linux_plain_window_set_child(GtkWindow *window, GtkWidget *child) {
    gtk_window_set_child(window, child);
}

void codexbar_linux_window_set_decorated(GtkWindow *window, gboolean decorated) {
    gtk_window_set_decorated(window, decorated);
}

void codexbar_linux_window_set_skip_taskbar(GtkWindow *window, gboolean skip) {
    /* gtk_window_set_skip_taskbar_hint was removed in GTK4; no direct replacement.
       Taskbar exclusion is now handled by the compositor based on window type. */
    (void)window; (void)skip;
}

void codexbar_linux_window_set_keep_above(GtkWindow *window, gboolean keep_above) {
    /* gtk_window_set_keep_above was removed in GTK4; no direct replacement.
       Always-on-top is now a compositor-level policy outside GTK's control. */
    (void)window; (void)keep_above;
}

void codexbar_linux_widget_set_visible(GtkWidget *widget, gboolean visible) {
    gtk_widget_set_visible(widget, visible);
}

gboolean codexbar_linux_widget_get_visible(GtkWidget *widget) {
    return gtk_widget_get_visible(widget);
}

void codexbar_linux_widget_set_background_color(GtkWidget *widget, const char *css_color) {
    /* Use a unique widget name so the display-scoped CSS provider targets only this widget.
     * gtk_style_context_add_provider (per-widget) was removed in GTK 4.10; the non-deprecated
     * path is gtk_style_context_add_provider_for_display scoped by widget name selector. */
    static guint color_widget_counter = 0;
    gchar *widget_name = g_strdup_printf("codexbar-colored-%u", ++color_widget_counter);
    gtk_widget_set_name(widget, widget_name);

    GtkCssProvider *provider = gtk_css_provider_new();
    gchar *css = g_strdup_printf(
        "#%s { background-color: %s; border-radius: 4px; min-width: 18px; min-height: 18px; }",
        widget_name, css_color);
    g_free(widget_name);
    gtk_css_provider_load_from_string(provider, css);
    g_free(css);
    gtk_style_context_add_provider_for_display(
        gdk_display_get_default(),
        GTK_STYLE_PROVIDER(provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(provider);
}

GtkWidget *codexbar_linux_image_from_resource(const char *resource_path, int size) {
    /* gtk_image_new_from_resource never returns NULL in GTK4 — on a missing path it
     * returns a valid but empty GtkImage and logs a GLib critical warning. Callers
     * must verify the resource path is registered (e.g. via g_resources_lookup_data)
     * before calling this function if they need to detect missing icons. */
    GtkWidget *image = gtk_image_new_from_resource(resource_path);
    gtk_image_set_pixel_size(GTK_IMAGE(image), size);
    return image;
}

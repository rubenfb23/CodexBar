#pragma once

#include <adwaita.h>

typedef void (*CodexBarLinuxActivateCallback)(AdwApplication *app, void *user_data);
typedef void (*CodexBarLinuxWidgetCallback)(GtkWidget *widget, void *user_data);
typedef void (*CodexBarLinuxMainThreadCallback)(void *user_data);
typedef gboolean (*CodexBarLinuxTimeoutCallback)(void *user_data);

void codexbar_linux_init(void);

AdwApplication *codexbar_linux_application_new(const char *application_id);
void codexbar_linux_application_on_activate(
    AdwApplication *app,
    CodexBarLinuxActivateCallback callback,
    void *user_data);
int codexbar_linux_application_run(AdwApplication *app);

AdwApplicationWindow *codexbar_linux_window_new(AdwApplication *app);
void codexbar_linux_window_set_title(AdwApplicationWindow *window, const char *title);
void codexbar_linux_window_set_default_size(AdwApplicationWindow *window, int width, int height);
void codexbar_linux_window_set_content(AdwApplicationWindow *window, GtkWidget *child);
void codexbar_linux_window_present(AdwApplicationWindow *window);

GtkWidget *codexbar_linux_box_new_vertical(int spacing);
GtkWidget *codexbar_linux_box_new_horizontal(int spacing);
void codexbar_linux_box_append(GtkWidget *box, GtkWidget *child);
void codexbar_linux_box_remove_all(GtkWidget *box);

GtkWidget *codexbar_linux_label_new(const char *text);
void codexbar_linux_label_set_text(GtkWidget *label, const char *text);
void codexbar_linux_label_set_wrap(GtkWidget *label, gboolean wrap);
void codexbar_linux_label_set_xalign(GtkWidget *label, float xalign);

GtkWidget *codexbar_linux_button_new(const char *label);
void codexbar_linux_button_on_clicked(GtkWidget *button, CodexBarLinuxWidgetCallback callback, void *user_data);

GtkWidget *codexbar_linux_check_button_new(const char *label);
gboolean codexbar_linux_check_button_get_active(GtkWidget *check_button);
void codexbar_linux_check_button_set_active(GtkWidget *check_button, gboolean active);
void codexbar_linux_check_button_on_toggled(
    GtkWidget *check_button,
    CodexBarLinuxWidgetCallback callback,
    void *user_data);

GtkWidget *codexbar_linux_progress_bar_new(void);
void codexbar_linux_progress_bar_set_fraction(GtkWidget *progress_bar, double fraction);
void codexbar_linux_progress_bar_set_text(GtkWidget *progress_bar, const char *text);
void codexbar_linux_progress_bar_set_show_text(GtkWidget *progress_bar, gboolean show_text);

GtkWidget *codexbar_linux_scrolled_window_new(void);
void codexbar_linux_scrolled_window_set_child(GtkWidget *scrolled_window, GtkWidget *child);

GtkWidget *codexbar_linux_frame_new(const char *label);
void codexbar_linux_frame_set_child(GtkWidget *frame, GtkWidget *child);

GtkWidget *codexbar_linux_separator_new(void);

GtkWidget *codexbar_linux_stack_new(void);
void codexbar_linux_stack_add_titled(
    GtkWidget *stack,
    GtkWidget *child,
    const char *name,
    const char *title);
GtkWidget *codexbar_linux_stack_switcher_new(void);
void codexbar_linux_stack_switcher_set_stack(GtkWidget *switcher, GtkWidget *stack);

void codexbar_linux_widget_add_css_class(GtkWidget *widget, const char *class_name);
void codexbar_linux_widget_set_hexpand(GtkWidget *widget, gboolean hexpand);
void codexbar_linux_widget_set_vexpand(GtkWidget *widget, gboolean vexpand);
void codexbar_linux_widget_set_margin_all(GtkWidget *widget, int margin);
guint codexbar_linux_timeout_add_seconds(
    guint interval,
    CodexBarLinuxTimeoutCallback callback,
    void *user_data);
void codexbar_linux_source_remove(guint source_id);
void codexbar_linux_main_context_invoke(
    CodexBarLinuxMainThreadCallback callback,
    void *user_data);

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

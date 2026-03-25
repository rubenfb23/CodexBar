#pragma once

#include <adwaita.h>

typedef void (*CodexBarLinuxActivateCallback)(AdwApplication *app, void *user_data);
typedef void (*CodexBarLinuxWidgetCallback)(GtkWidget *widget, void *user_data);

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

GtkWidget *codexbar_linux_progress_bar_new(void);
void codexbar_linux_progress_bar_set_fraction(GtkWidget *progress_bar, double fraction);
void codexbar_linux_progress_bar_set_text(GtkWidget *progress_bar, const char *text);
void codexbar_linux_progress_bar_set_show_text(GtkWidget *progress_bar, gboolean show_text);

GtkWidget *codexbar_linux_scrolled_window_new(void);
void codexbar_linux_scrolled_window_set_child(GtkWidget *scrolled_window, GtkWidget *child);

GtkWidget *codexbar_linux_frame_new(const char *label);
void codexbar_linux_frame_set_child(GtkWidget *frame, GtkWidget *child);

GtkWidget *codexbar_linux_separator_new(void);

void codexbar_linux_widget_add_css_class(GtkWidget *widget, const char *class_name);
void codexbar_linux_widget_set_hexpand(GtkWidget *widget, gboolean hexpand);
void codexbar_linux_widget_set_vexpand(GtkWidget *widget, gboolean vexpand);
void codexbar_linux_widget_set_margin_all(GtkWidget *widget, int margin);

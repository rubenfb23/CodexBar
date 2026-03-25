#include "CodexBarLinuxUIBridge.h"

void codexbar_linux_init(void) {
    adw_init();
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
    gtk_window_set_child(GTK_WINDOW(window), child);
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

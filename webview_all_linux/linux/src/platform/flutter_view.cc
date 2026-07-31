#include "plugin/webview_all_linux_plugin_private.h"

#include <cstring>

namespace {

constexpr const gchar* kFlutterViewOverlayKey = "webview_all_linux_overlay";

// Flutter registers Linux plugins after the runner realizes FlView. Reparenting
// FlView at that point destroys the GL surface used by the engine. Install the
// overlay inside FlView when the runner first parents it instead, which happens
// before realization in the standard Flutter runner.
gboolean flutter_view_parent_set_emission_hook(
    GSignalInvocationHint*,
    guint parameter_count,
    const GValue* parameters,
    gpointer) {
  if (parameter_count == 0) {
    return TRUE;
  }

  GObject* instance = G_OBJECT(g_value_get_object(&parameters[0]));
  if (instance == nullptr || !FL_IS_VIEW(instance)) {
    return TRUE;
  }

  GtkWidget* view_widget = GTK_WIDGET(instance);
  GtkWidget* parent = gtk_widget_get_parent(view_widget);
  if (parent != nullptr && GTK_IS_OVERLAY(parent)) {
    // Preserve runners that already wrap FlView in a GtkOverlay. The plugin
    // registration path will detect and reuse this parent.
    return TRUE;
  }
  if (g_object_get_data(instance, kFlutterViewOverlayKey) != nullptr) {
    return TRUE;
  }
  if (gtk_widget_get_realized(view_widget)) {
    g_warning(
        "webview_all_linux could not install its GtkOverlay before FlView "
        "was realized.");
    return TRUE;
  }

  GList* children = gtk_container_get_children(GTK_CONTAINER(view_widget));
  if (children == nullptr || children->next != nullptr) {
    g_warning(
        "webview_all_linux expected an unrealized FlView with one child.");
    g_list_free(children);
    return TRUE;
  }

  GtkWidget* flutter_content = GTK_WIDGET(children->data);
  g_object_ref(flutter_content);
  gtk_container_remove(GTK_CONTAINER(view_widget), flutter_content);

  GtkWidget* overlay = gtk_overlay_new();
  g_object_set_data(instance, kFlutterViewOverlayKey, overlay);
  gtk_widget_set_hexpand(overlay, TRUE);
  gtk_widget_set_vexpand(overlay, TRUE);
  gtk_container_add(GTK_CONTAINER(overlay), flutter_content);
  gtk_container_add(GTK_CONTAINER(view_widget), overlay);
  gtk_widget_show(overlay);

  g_object_unref(flutter_content);
  g_list_free(children);
  return TRUE;
}

__attribute__((constructor)) void install_flutter_view_overlay_hook() {
  gpointer widget_class = g_type_class_ref(GTK_TYPE_WIDGET);
  const guint signal_id = g_signal_lookup("parent-set", GTK_TYPE_WIDGET);
  if (signal_id != 0) {
    g_signal_add_emission_hook(signal_id, 0,
                               flutter_view_parent_set_emission_hook, nullptr,
                               nullptr);
  }
  g_type_class_unref(widget_class);
}

}  // namespace

static void flutter_view_size_allocate_cb(GtkWidget* widget,
                                          GtkAllocation* allocation,
                                          gpointer user_data) {
  update_flutter_view_input_region(
      static_cast<WebviewAllLinuxPlugin*>(user_data));
}

GtkOverlay* ensure_overlay(WebviewAllLinuxPlugin* self) {
  if (self->overlay != nullptr) {
    return self->overlay;
  }

  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return nullptr;
  }

  GtkWidget* view_widget = GTK_WIDGET(view);
  GtkOverlay* installed_overlay = GTK_OVERLAY(
      g_object_get_data(G_OBJECT(view_widget), kFlutterViewOverlayKey));
  if (installed_overlay != nullptr) {
    self->overlay = installed_overlay;
    g_signal_connect(view_widget, "size-allocate",
                     G_CALLBACK(flutter_view_size_allocate_cb), self);
    return self->overlay;
  }

  GtkWidget* parent = gtk_widget_get_parent(view_widget);
  if (parent == nullptr) {
    return nullptr;
  }

  if (GTK_IS_OVERLAY(parent)) {
    self->overlay = GTK_OVERLAY(parent);
    g_signal_connect(view_widget, "size-allocate",
                     G_CALLBACK(flutter_view_size_allocate_cb), self);
    return self->overlay;
  }

  g_warning(
      "webview_all_linux requires its automatic GtkOverlay to be installed "
      "before FlView is realized.");
  return nullptr;
}

void update_flutter_view_input_region(WebviewAllLinuxPlugin* self) {
  FlView* view = fl_plugin_registrar_get_view(self->registrar);
  if (view == nullptr) {
    return;
  }

  GtkWidget* view_widget = GTK_WIDGET(view);
  GdkWindow* parent_window = gtk_widget_get_parent_window(view_widget);
  if (parent_window == nullptr) {
    return;
  }
  const gint width = gtk_widget_get_allocated_width(view_widget);
  const gint height = gtk_widget_get_allocated_height(view_widget);
  if (width <= 0 || height <= 0) {
    return;
  }

  cairo_rectangle_int_t full_rect = {0, 0, width, height};
  cairo_region_t* region = cairo_region_create_rectangle(&full_rect);

  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  g_hash_table_iter_init(&iter, self->webviews);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    LinuxWebView* webview = static_cast<LinuxWebView*>(value);
    if (webview == nullptr || !webview->visible || webview->frame_width <= 0 ||
        webview->frame_height <= 0) {
      continue;
    }

    cairo_rectangle_int_t webview_rect = {
        webview->frame_x, webview->frame_y, webview->frame_width,
        webview->frame_height};
    cairo_region_subtract_rectangle(region, &webview_rect);
  }

  gdk_window_input_shape_combine_region(parent_window, region, 0, 0);
  cairo_region_destroy(region);
}

#include "plugin/webview_all_linux_plugin_private.h"

#include <cstring>

namespace {

constexpr const gchar* kFlutterViewOverlayKey = "webview_all_linux_overlay";
constexpr const gchar *kFlutterInputWidgetKey =
    "webview_all_linux_flutter_input_widget";

GtkWidget *find_flutter_input_widget(GtkWidget *widget) {
  if (widget == nullptr) {
    return nullptr;
  }
  if (GTK_IS_EVENT_BOX(widget)) {
    return widget;
  }
  if (!GTK_IS_CONTAINER(widget)) {
    return nullptr;
  }

  GList *children = gtk_container_get_children(GTK_CONTAINER(widget));
  GtkWidget *result = nullptr;
  for (GList *item = children; item != nullptr && result == nullptr;
       item = item->next) {
    result = find_flutter_input_widget(GTK_WIDGET(item->data));
  }
  g_list_free(children);
  return result;
}

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
  gtk_widget_set_hexpand(overlay, TRUE);
  gtk_widget_set_vexpand(overlay, TRUE);
  gtk_container_add(GTK_CONTAINER(overlay), flutter_content);
  gtk_container_add(GTK_CONTAINER(view_widget), overlay);
  gtk_widget_show(overlay);
  g_object_set_data_full(instance, kFlutterViewOverlayKey,
                         g_object_ref(overlay), g_object_unref);
  g_object_set_data_full(instance, kFlutterInputWidgetKey,
                         g_object_ref(flutter_content), g_object_unref);

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
  schedule_flutter_view_input_region_update(
      static_cast<WebviewAllLinuxPlugin *>(user_data));
}

static void flutter_view_layout_changed_cb(GtkWidget *widget,
                                           gpointer user_data) {
  schedule_flutter_view_input_region_update(
      static_cast<WebviewAllLinuxPlugin *>(user_data));
}

static void overlay_destroy_cb(GtkWidget *widget, gpointer user_data) {
  detach_linux_webview_host(static_cast<WebviewAllLinuxPlugin *>(user_data));
}

static gboolean overlay_get_child_position_cb(GtkOverlay *overlay,
                                              GtkWidget *widget,
                                              GtkAllocation *allocation,
                                              gpointer user_data) {
  LinuxWebView *webview = static_cast<LinuxWebView *>(
      g_object_get_data(G_OBJECT(widget), kLinuxWebViewInstanceKey));
  WebviewAllLinuxPlugin *self = static_cast<WebviewAllLinuxPlugin *>(user_data);
  if (webview == nullptr || webview->plugin != self) {
    return FALSE;
  }

  gint frame_x = webview->frame_x;
  gint frame_y = webview->frame_y;
  if (self->flutter_view != nullptr &&
      gtk_widget_get_parent(self->flutter_view) == GTK_WIDGET(overlay)) {
    GtkAllocation flutter_view_allocation;
    gtk_widget_get_allocation(self->flutter_view, &flutter_view_allocation);
    frame_x = static_cast<gint>(
        CLAMP(static_cast<gint64>(frame_x) + flutter_view_allocation.x,
              static_cast<gint64>(G_MININT), static_cast<gint64>(G_MAXINT)));
    frame_y = static_cast<gint>(
        CLAMP(static_cast<gint64>(frame_y) + flutter_view_allocation.y,
              static_cast<gint64>(G_MININT), static_cast<gint64>(G_MAXINT)));
  }

  allocation->x = frame_x;
  allocation->y = frame_y;
  allocation->width = webview->frame_width;
  allocation->height = webview->frame_height;
  return TRUE;
}

template <typename WidgetType>
static void clear_weak_widget_pointer(WidgetType **widget,
                                      WebviewAllLinuxPlugin *self) {
  if (*widget == nullptr) {
    return;
  }
  g_signal_handlers_disconnect_by_data(*widget, self);
  g_object_remove_weak_pointer(G_OBJECT(*widget),
                               reinterpret_cast<gpointer *>(widget));
  *widget = nullptr;
}

static void attach_linux_webview_host(WebviewAllLinuxPlugin *self,
                                      GtkWidget *view_widget,
                                      GtkOverlay *overlay,
                                      GtkWidget *input_widget) {
  if (self->flutter_view == view_widget && self->overlay == overlay &&
      self->flutter_input_widget == input_widget) {
    return;
  }

  detach_linux_webview_host(self);
  self->flutter_view = view_widget;
  self->overlay = overlay;
  self->flutter_input_widget = input_widget;
  self->input_region_warning_emitted = FALSE;

  if (self->flutter_input_widget == nullptr) {
    g_warning(
        "webview_all_linux could not locate Flutter's GTK input widget; "
        "native GtkOverlay routing will be used without changing any parent "
        "window input region.");
  }

  g_object_add_weak_pointer(G_OBJECT(self->flutter_view),
                            reinterpret_cast<gpointer *>(&self->flutter_view));
  g_object_add_weak_pointer(G_OBJECT(self->overlay),
                            reinterpret_cast<gpointer *>(&self->overlay));
  if (self->flutter_input_widget != nullptr) {
    g_object_add_weak_pointer(
        G_OBJECT(self->flutter_input_widget),
        reinterpret_cast<gpointer *>(&self->flutter_input_widget));
  }

  g_signal_connect(self->flutter_view, "size-allocate",
                   G_CALLBACK(flutter_view_size_allocate_cb), self);
  g_signal_connect(self->overlay, "size-allocate",
                   G_CALLBACK(flutter_view_size_allocate_cb), self);
  g_signal_connect(self->overlay, "get-child-position",
                   G_CALLBACK(overlay_get_child_position_cb), self);
  g_signal_connect(self->overlay, "destroy", G_CALLBACK(overlay_destroy_cb),
                   self);
  if (self->flutter_input_widget != nullptr) {
    g_signal_connect(self->flutter_input_widget, "size-allocate",
                     G_CALLBACK(flutter_view_size_allocate_cb), self);
    g_signal_connect(self->flutter_input_widget, "realize",
                     G_CALLBACK(flutter_view_layout_changed_cb), self);
    g_signal_connect(self->flutter_input_widget, "map",
                     G_CALLBACK(flutter_view_layout_changed_cb), self);
  }
  schedule_flutter_view_input_region_update(self);
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
    GtkWidget *input_widget = GTK_WIDGET(
        g_object_get_data(G_OBJECT(view_widget), kFlutterInputWidgetKey));
    if (input_widget == nullptr) {
      input_widget = find_flutter_input_widget(view_widget);
    }
    attach_linux_webview_host(self, view_widget, installed_overlay,
                              input_widget);
    return self->overlay;
  }

  GtkWidget* parent = gtk_widget_get_parent(view_widget);
  if (parent == nullptr) {
    return nullptr;
  }

  if (GTK_IS_OVERLAY(parent)) {
    attach_linux_webview_host(self, view_widget, GTK_OVERLAY(parent),
                              find_flutter_input_widget(view_widget));
    return self->overlay;
  }

  g_warning(
      "webview_all_linux requires its automatic GtkOverlay to be installed "
      "before FlView is realized.");
  return nullptr;
}

void update_flutter_view_input_region(WebviewAllLinuxPlugin* self) {
  if (self == nullptr || self->disposing ||
      self->flutter_input_widget == nullptr || self->overlay == nullptr) {
    return;
  }

  GtkWidget *input_widget = self->flutter_input_widget;
  if (!gtk_widget_get_realized(input_widget) ||
      !gtk_widget_get_has_window(input_widget) ||
      gtk_widget_get_window(input_widget) == nullptr) {
    return;
  }
  const gint width = gtk_widget_get_allocated_width(input_widget);
  const gint height = gtk_widget_get_allocated_height(input_widget);
  if (width <= 0 || height <= 0) {
    return;
  }

  cairo_rectangle_int_t full_rect = {0, 0, width, height};
  cairo_region_t* region = cairo_region_create_rectangle(&full_rect);

  GHashTableIter iter;
  gpointer key = nullptr;
  gpointer value = nullptr;
  gboolean has_visible_webview = FALSE;
  g_hash_table_iter_init(&iter, self->webviews);
  while (g_hash_table_iter_next(&iter, &key, &value)) {
    LinuxWebView* webview = static_cast<LinuxWebView*>(value);
    if (webview == nullptr || !webview->visible || webview->frame_width <= 0 ||
        webview->frame_height <= 0 || webview->web_view == nullptr ||
        !gtk_widget_get_mapped(GTK_WIDGET(webview->web_view))) {
      continue;
    }

    gint translated_x = 0;
    gint translated_y = 0;
    if (!gtk_widget_translate_coordinates(GTK_WIDGET(webview->web_view),
                                          input_widget, 0, 0, &translated_x,
                                          &translated_y)) {
      if (!self->input_region_warning_emitted) {
        g_warning(
            "webview_all_linux could not translate the WebView input region "
            "into Flutter content coordinates; the top-level window was left "
            "unchanged.");
        self->input_region_warning_emitted = TRUE;
      }
      continue;
    }

    const gint webview_width =
        gtk_widget_get_allocated_width(GTK_WIDGET(webview->web_view));
    const gint webview_height =
        gtk_widget_get_allocated_height(GTK_WIDGET(webview->web_view));
    if (webview_width <= 0 || webview_height <= 0) {
      continue;
    }
    const gint left = MAX(0, translated_x);
    const gint top = MAX(0, translated_y);
    const gint64 translated_right =
        static_cast<gint64>(translated_x) + webview_width;
    const gint64 translated_bottom =
        static_cast<gint64>(translated_y) + webview_height;
    const gint right =
        static_cast<gint>(MIN(static_cast<gint64>(width), translated_right));
    const gint bottom =
        static_cast<gint>(MIN(static_cast<gint64>(height), translated_bottom));
    if (right <= left || bottom <= top) {
      continue;
    }

    cairo_rectangle_int_t webview_rect = {left, top, right - left,
                                          bottom - top};
    cairo_region_subtract_rectangle(region, &webview_rect);
    has_visible_webview = TRUE;
  }

  // Only the Flutter event surface is shaped. Shaping FlView's parent window
  // creates a hole in the entire application and can send clicks to another
  // application instead of the WebKit overlay.
  gtk_widget_input_shape_combine_region(input_widget,
                                        has_visible_webview ? region : nullptr);
  cairo_region_destroy(region);
}

static gboolean update_flutter_view_input_region_idle_cb(gpointer user_data) {
  WebviewAllLinuxPlugin *self = static_cast<WebviewAllLinuxPlugin *>(user_data);
  self->input_region_update_source_id = 0;
  update_flutter_view_input_region(self);
  return G_SOURCE_REMOVE;
}

void schedule_flutter_view_input_region_update(WebviewAllLinuxPlugin *self) {
  if (self == nullptr || self->disposing ||
      self->input_region_update_source_id != 0) {
    return;
  }
  self->input_region_update_source_id = g_idle_add_full(
      G_PRIORITY_DEFAULT_IDLE, update_flutter_view_input_region_idle_cb,
      g_object_ref(self), g_object_unref);
}

void restore_flutter_view_input_region(WebviewAllLinuxPlugin *self) {
  if (self == nullptr || self->flutter_input_widget == nullptr ||
      !gtk_widget_get_realized(self->flutter_input_widget) ||
      !gtk_widget_get_has_window(self->flutter_input_widget)) {
    return;
  }
  gtk_widget_input_shape_combine_region(self->flutter_input_widget, nullptr);
}

void detach_linux_webview_host(WebviewAllLinuxPlugin *self) {
  if (self == nullptr) {
    return;
  }
  if (self->input_region_update_source_id != 0) {
    g_source_remove(self->input_region_update_source_id);
    self->input_region_update_source_id = 0;
  }
  restore_flutter_view_input_region(self);
  clear_weak_widget_pointer(&self->flutter_input_widget, self);
  clear_weak_widget_pointer(&self->flutter_view, self);
  clear_weak_widget_pointer(&self->overlay, self);
}

void release_linux_webview_focus(LinuxWebView *webview) {
  if (webview == nullptr || webview->web_view == nullptr ||
      webview->plugin == nullptr || webview->plugin->flutter_view == nullptr) {
    return;
  }
  GtkWidget *webview_widget = GTK_WIDGET(webview->web_view);
  GtkWidget *toplevel = gtk_widget_get_toplevel(webview_widget);
  if (toplevel == nullptr || !GTK_IS_WINDOW(toplevel)) {
    return;
  }
  GtkWidget *focus = gtk_window_get_focus(GTK_WINDOW(toplevel));
  if (focus == webview_widget ||
      (focus != nullptr && gtk_widget_is_ancestor(focus, webview_widget))) {
    gtk_widget_grab_focus(webview->plugin->flutter_view);
  }
}

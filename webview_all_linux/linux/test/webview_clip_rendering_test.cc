#include <webkit2/webkit2.h>

#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "../src/platform/webview_clip.h"
#include "javascript_test_helpers.h"

namespace {

gboolean draw_background(GtkWidget *, cairo_t *cr, gpointer) {
  cairo_set_source_rgb(cr, 0, 1, 1);
  cairo_paint(cr);
  return FALSE;
}

bool pixel_matches(GtkWidget *window, int x, int y, bool webview) {
  GdkPixbuf *pixels =
      gdk_pixbuf_get_from_window(gtk_widget_get_window(window), 0, 0,
                                 gtk_widget_get_allocated_width(window),
                                 gtk_widget_get_allocated_height(window));
  g_assert_nonnull(pixels);
  const int scale = gtk_widget_get_scale_factor(window);
  const guchar *pixel = gdk_pixbuf_get_pixels(pixels) +
                        y * scale * gdk_pixbuf_get_rowstride(pixels) +
                        x * scale * gdk_pixbuf_get_n_channels(pixels);
  const bool matches = webview
                           ? pixel[0] > 240 && pixel[1] < 15 && pixel[2] > 240
                           : pixel[0] < 15 && pixel[1] > 240 && pixel[2] > 240;
  g_object_unref(pixels);
  return matches;
}

void wait_for_pixel(GtkWidget *window, int x, int y, bool webview) {
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  do {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    if (pixel_matches(window, x, y, webview)) {
      return;
    }
    g_usleep(10000);
  } while (g_get_monotonic_time() < deadline);
  g_error("Pixel (%d, %d) did not show %s", x, y,
          webview ? "WebKit content" : "the background outside its clip");
}

void rounded_webkit_rendering_test() {
#ifdef GDK_WINDOWING_X11
  if (!GDK_IS_X11_DISPLAY(gdk_display_get_default())) {
    // Wayland's client-side GDK readback omits WebKit's composed child pixels.
    // Its final output must be captured from the compositor instead.
    g_test_skip("Window pixel readback requires X11.");
    return;
  }
#else
  g_test_skip("Window pixel readback requires the X11 GDK backend.");
  return;
#endif
  GtkWidget *window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_decorated(GTK_WINDOW(window), FALSE);
  gtk_window_set_default_size(GTK_WINDOW(window), 200, 160);
  GtkWidget *overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(window), overlay);
  GtkWidget *background = gtk_drawing_area_new();
  g_signal_connect(background, "draw", G_CALLBACK(draw_background), nullptr);
  gtk_container_add(GTK_CONTAINER(overlay), background);
  GtkWidget *container = create_linux_webview_clip_container();
  gtk_widget_set_halign(container, GTK_ALIGN_START);
  gtk_widget_set_valign(container, GTK_ALIGN_START);
  gtk_widget_set_margin_start(container, 20);
  gtk_widget_set_margin_top(container, 20);
  gtk_widget_set_size_request(container, 100, 80);
  gtk_layout_set_size(GTK_LAYOUT(container), 100, 80);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), container);
  WebKitWebContext *context = webkit_web_context_new_ephemeral();
  GtkWidget *view = webkit_web_view_new_with_context(context);
  g_object_unref(context);
  gtk_widget_set_size_request(view, 100, 80);
  gtk_layout_put(GTK_LAYOUT(container), view, 0, 0);

  cairo_region_t *region = create_linux_webview_clip_region(
      20, 20, 100, 80, {{{20, 20, 120, 100, 30, 30, 30, 30, 30, 30, 30, 30}}});
  // Install before realization, as happens when Flutter first supplies its
  // geometry. Both WebKit and GTK must respect the parent window's shape.
  set_linux_webview_clip(container, region);
  gtk_widget_show_all(window);
  webview_test::load_html(WEBKIT_WEB_VIEW(view),
                          "<style>html,body{margin:0;width:100%;height:100%;"
                          "background:#ff00ff}</style>",
                          "about:blank");
  wait_for_pixel(window, 70, 60, true);
  wait_for_pixel(window, 21, 21, false);
  wait_for_pixel(window, 118, 98, false);

  gtk_widget_hide(container);
  gtk_widget_show(container);
  wait_for_pixel(window, 70, 60, true);
  wait_for_pixel(window, 21, 21, false);

  // A later ordinary rectangular frame must clear both native masks.
  set_linux_webview_clip(container, nullptr);
  wait_for_pixel(window, 21, 21, true);
  wait_for_pixel(window, 118, 98, true);
  cairo_region_destroy(region);
  gtk_widget_destroy(window);
}

} // namespace

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/webview_clip/gtk_rendering", rounded_webkit_rendering_test);
  return g_test_run();
}

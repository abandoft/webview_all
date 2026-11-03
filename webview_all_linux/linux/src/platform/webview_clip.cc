#include "webview_clip.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr const char *kClipRegionKey = "webview_all_linux_clip_region";

void update_bin_clip(GtkWidget *container, gpointer) {
  if (!gtk_widget_get_realized(container)) {
    return;
  }
  auto *region = static_cast<cairo_region_t *>(
      g_object_get_data(G_OBJECT(container), kClipRegionKey));
  GdkWindow *bin_window = gtk_layout_get_bin_window(GTK_LAYOUT(container));
  // GtkLayout has separate viewport and bin windows. Keep its bin window
  // consistent with the viewport and the clipped WebKit child.
  gdk_window_shape_combine_region(bin_window, region, 0, 0);
  gdk_window_input_shape_combine_region(bin_window, region, 0, 0);
}

gboolean draw_clipped_container(GtkWidget *widget, cairo_t *cr, gpointer) {
  auto *region = static_cast<cairo_region_t *>(
      g_object_get_data(G_OBJECT(widget), kClipRegionKey));
  if (region == nullptr) {
    return FALSE;
  }
  // A GTK window shape alone does not clip every WebKit drawing path. Call
  // GtkLayout's default drawing inside our Cairo clip, then stop the signal's
  // default handler from painting the children a second time without it.
  cairo_save(cr);
  gdk_cairo_region(cr, region);
  cairo_clip(cr);
  GTK_WIDGET_GET_CLASS(widget)->draw(widget, cr);
  cairo_restore(cr);
  return TRUE;
}

double corner_inset(double distance, double radius_x, double radius_y) {
  if (radius_x <= 0 || radius_y <= 0 || distance >= radius_y) {
    return 0;
  }
  const double ratio = (radius_y - distance) / radius_y;
  return radius_x * (1 - std::sqrt(std::max(0.0, 1 - ratio * ratio)));
}

bool contains_point(const LinuxRoundedClip &clip, double x, double y) {
  if (x < clip[0] || x >= clip[2] || y < clip[1] || y >= clip[3]) {
    return false;
  }
  for (size_t corner = 0; corner < 4; ++corner) {
    const double radius_x = clip[4 + corner * 2];
    const double radius_y = clip[5 + corner * 2];
    if (radius_x <= 0 || radius_y <= 0) {
      continue;
    }
    const bool right = corner == 1 || corner == 2;
    const bool bottom = corner >= 2;
    const double center_x = right ? clip[2] - radius_x : clip[0] + radius_x;
    const double center_y = bottom ? clip[3] - radius_y : clip[1] + radius_y;
    if ((right ? x > center_x : x < center_x) &&
        (bottom ? y > center_y : y < center_y)) {
      const double dx = (x - center_x) / radius_x;
      const double dy = (y - center_y) / radius_y;
      if (dx * dx + dy * dy > 1) {
        return false;
      }
    }
  }
  return true;
}

} // namespace

GtkWidget *create_linux_webview_clip_container() {
  GtkWidget *container = gtk_layout_new(nullptr, nullptr);
  g_signal_connect(container, "draw", G_CALLBACK(draw_clipped_container),
                   nullptr);
  g_signal_connect_after(container, "realize", G_CALLBACK(update_bin_clip),
                         nullptr);
  return container;
}

void set_linux_webview_clip(GtkWidget *container, cairo_region_t *region) {
  g_object_set_data_full(
      G_OBJECT(container), kClipRegionKey,
      region == nullptr ? nullptr : cairo_region_reference(region),
      reinterpret_cast<GDestroyNotify>(cairo_region_destroy));
  gtk_widget_shape_combine_region(container, region);
  gtk_widget_input_shape_combine_region(container, region);
  update_bin_clip(container, nullptr);
  gtk_widget_queue_draw(container);
}

cairo_region_t *
create_linux_webview_clip_region(int x, int y, int width, int height,
                                 const std::vector<LinuxRoundedClip> &clips) {
  cairo_region_t *region = cairo_region_create();
  if (width <= 0 || height <= 0) {
    return region;
  }

  cairo_rectangle_int_t run = {0, 0, 0, 0};
  for (int row = 0; row < height; ++row) {
    const double center_y = static_cast<double>(y) + row + 0.5;
    double left = 0;
    double right = width;
    for (const auto &clip : clips) {
      if (center_y < clip[1] || center_y >= clip[3]) {
        right = left;
        break;
      }
      const double top = center_y - clip[1];
      const double bottom = clip[3] - center_y;
      const double left_inset =
          std::max(corner_inset(top, clip[4], clip[5]),
                   corner_inset(bottom, clip[10], clip[11]));
      const double right_inset =
          std::max(corner_inset(top, clip[6], clip[7]),
                   corner_inset(bottom, clip[8], clip[9]));
      left = std::max(left, clip[0] - x + left_inset);
      right = std::min(right, clip[2] - x - right_inset);
    }
    const int estimated_first = static_cast<int>(std::ceil(
        std::min(std::max(left - 0.5, 0.0), static_cast<double>(width))));
    const int estimated_last = static_cast<int>(std::ceil(
        std::min(std::max(right - 0.5, 0.0), static_cast<double>(width))));
    // sqrt/ceil can round a point on the curved boundary to the wrong pixel.
    // Inspect one extra candidate on each side, then use ellipse containment
    // to retain boundary pixels without expanding outside any ancestor clip.
    int first = std::max(0, estimated_first - 1);
    int last = estimated_last < width ? estimated_last + 1 : width;
    const auto contains_column = [&](int column) {
      const double center_x = static_cast<double>(x) + column + 0.5;
      for (const auto &clip : clips) {
        if (!contains_point(clip, center_x, center_y)) {
          return false;
        }
      }
      return true;
    };
    while (first < last && !contains_column(first)) {
      ++first;
    }
    while (last > first && !contains_column(last - 1)) {
      --last;
    }
    const int extent = std::max(0, last - first);
    if (run.height > 0 && run.x == first && run.width == extent) {
      ++run.height;
    } else {
      if (run.width > 0 && run.height > 0) {
        cairo_region_union_rectangle(region, &run);
      }
      run = {first, row, extent, 1};
    }
  }
  if (run.width > 0 && run.height > 0) {
    cairo_region_union_rectangle(region, &run);
  }
  return region;
}

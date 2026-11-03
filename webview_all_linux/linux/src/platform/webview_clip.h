#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_CLIP_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_CLIP_H_

#include <gtk/gtk.h>

#include <array>
#include <vector>

// Bounds and corner radii in GTK logical pixels: left, top, right, bottom,
// followed by x/y radii for the top-left, top-right, bottom-right, bottom-left.
using LinuxRoundedClip = std::array<double, 12>;

// Returns an owned region in the clip container's local coordinates. Pixel
// centers determine coverage so drawing and native pointer routing agree.
// Radii must be finite, nonnegative, and normalized to fit their bounds.
cairo_region_t *
create_linux_webview_clip_region(int x, int y, int width, int height,
                                 const std::vector<LinuxRoundedClip> &clips);

GtkWidget *create_linux_webview_clip_container();
void set_linux_webview_clip(GtkWidget *container, cairo_region_t *region);

#endif

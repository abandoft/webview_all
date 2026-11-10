#pragma once

#include <cmath>
#include <cstdint>
#include <initializer_list>
#include <limits>
#include <optional>

namespace webview_all_windows {

struct SurfaceOrigin {
  double x;
  double y;
};

struct SurfaceBounds {
  int32_t left;
  int32_t top;
  int32_t right;
  int32_t bottom;
};

// Preserve page zoom while changing the view's visual scale independently of
// monitor DPI. Treating a Flutter transform as monitor DPI misplaces native
// IME.
inline std::optional<double> CalculateSurfaceZoom(double current_zoom,
                                                  double previous_scale,
                                                  double previous_dpi_scale,
                                                  double scale,
                                                  double dpi_scale) {
  for (const double value :
       {current_zoom, previous_scale, previous_dpi_scale, scale, dpi_scale}) {
    if (!std::isfinite(value) || value <= 0)
      return std::nullopt;
  }
  const double result = current_zoom * (scale / dpi_scale) /
                        (previous_scale / previous_dpi_scale);
  return std::isfinite(result) && result > 0 ? std::optional<double>(result)
                                             : std::nullopt;
}

// Coordinates are raw physical pixels in the parent HWND's client area.
// Hidden/unmounted views use a position beyond the entire virtual desktop.
inline std::optional<SurfaceBounds>
CalculateSurfaceBounds(double width, double height, double scale,
                       std::optional<SurfaceOrigin> origin,
                       int32_t parent_screen_x, int32_t parent_screen_y,
                       int32_t desktop_left, int32_t desktop_top) {
  if (!std::isfinite(width) || !std::isfinite(height) ||
      !std::isfinite(scale) || width <= 0 || height <= 0 || scale <= 0) {
    return std::nullopt;
  }
  const double pixel_width = std::ceil(width * scale);
  const double pixel_height = std::ceil(height * scale);
  if (!std::isfinite(pixel_width) || !std::isfinite(pixel_height) ||
      pixel_width <= 0 || pixel_height <= 0 || pixel_width > 16384 ||
      pixel_height > 16384) {
    return std::nullopt;
  }
  constexpr auto minimum = (std::numeric_limits<int32_t>::min)();
  constexpr auto maximum = (std::numeric_limits<int32_t>::max)();
  const int64_t w = static_cast<int64_t>(pixel_width);
  const int64_t h = static_cast<int64_t>(pixel_height);
  int64_t left;
  int64_t top;
  if (origin) {
    const double x = std::round(origin->x);
    const double y = std::round(origin->y);
    if (!std::isfinite(x) || !std::isfinite(y) || x < minimum || x > maximum ||
        y < minimum || y > maximum) {
      return std::nullopt;
    }
    left = static_cast<int64_t>(x);
    top = static_cast<int64_t>(y);
  } else {
    left = static_cast<int64_t>(desktop_left) - 1024 - parent_screen_x - w;
    top = static_cast<int64_t>(desktop_top) - 1024 - parent_screen_y - h;
  }
  if (left < minimum || top < minimum || left + w > maximum ||
      top + h > maximum) {
    return std::nullopt;
  }
  return SurfaceBounds{static_cast<int32_t>(left), static_cast<int32_t>(top),
                       static_cast<int32_t>(left + w),
                       static_cast<int32_t>(top + h)};
}

} // namespace webview_all_windows

#include "webview/surface_bounds.h"

#include <cstdlib>
#include <iostream>
#include <limits>

using namespace webview_all_windows;

static void Check(bool value, const char *message) {
  if (!value) {
    std::cerr << message << '\n';
    std::abort();
  }
}

int main() {
  const auto scaled = CalculateSurfaceZoom(1.2, 1.5, 1.5, 1.875, 1.5);
  Check(scaled && std::abs(*scaled - 1.5) < 1e-9,
        "visual scaling preserves the current page zoom");
  const auto restored = CalculateSurfaceZoom(1.5, 1.875, 1.5, 1.5, 1.5);
  Check(restored && std::abs(*restored - 1.2) < 1e-9,
        "restoring visual scale restores page zoom");
  for (const double dpi_scale : {1.0, 1.25, 1.5, 2.0}) {
    const auto zoom = CalculateSurfaceZoom(1.2, 1.5, 1.5, dpi_scale, dpi_scale);
    Check(zoom && std::abs(*zoom - 1.2) < 1e-9,
          "changing monitor DPI must not change page zoom");
  }
  for (const double scale : {1.0, 1.25, 1.5, 2.0}) {
    const auto rect = CalculateSurfaceBounds(
        600, 350, scale, SurfaceOrigin{150 * scale, 120 * scale}, 25, 60, -1920,
        -1080);
    Check(rect.has_value(), "valid visible geometry");
    Check(rect->left == std::round(150 * scale) &&
              rect->top == std::round(120 * scale),
          "physical client origin");
    Check(rect->right - rect->left == std::ceil(600 * scale) &&
              rect->bottom - rect->top == std::ceil(350 * scale),
          "physical extent");
  }
  const auto fractional = CalculateSurfaceBounds(
      10.5, 20.25, 1.5, SurfaceOrigin{-20.4, 30.6}, 0, 0, 0, 0);
  Check(fractional && fractional->left == -20 && fractional->top == 31 &&
            fractional->right == -4 && fractional->bottom == 62,
        "fractional sizes must not be truncated before scaling");
  for (const int parent_x : {-30000, -1920, 0, 1200}) {
    const auto parked = CalculateSurfaceBounds(600, 350, 1.5, std::nullopt,
                                               parent_x, 800, -3840, -1080);
    Check(parked && parked->right + parent_x == -3840 - 1024 &&
              parked->bottom + 800 == -1080 - 1024,
          "parking must stay beyond all monitors when the parent moves");
    const auto shown = CalculateSurfaceBounds(
        600, 350, 1.5, SurfaceOrigin{225, 180}, parent_x, 800, -3840, -1080);
    Check(shown && shown->left == 225 && shown->top == 180,
          "visible bounds stay relative to their parent");
  }
  const double infinity = std::numeric_limits<double>::infinity();
  const double nan = std::numeric_limits<double>::quiet_NaN();
  for (const double value : {0.0, -1.0, infinity, nan}) {
    Check(!CalculateSurfaceZoom(value, 1, 1, 1, 1) &&
              !CalculateSurfaceZoom(1, value, 1, 1, 1) &&
              !CalculateSurfaceZoom(1, 1, value, 1, 1) &&
              !CalculateSurfaceZoom(1, 1, 1, value, 1) &&
              !CalculateSurfaceZoom(1, 1, 1, 1, value),
          "invalid zoom geometry");
    Check(!CalculateSurfaceBounds(value, 20, 1, std::nullopt, 0, 0, 0, 0),
          "invalid width");
    Check(!CalculateSurfaceBounds(20, value, 1, std::nullopt, 0, 0, 0, 0),
          "invalid height");
    Check(!CalculateSurfaceBounds(20, 20, value, std::nullopt, 0, 0, 0, 0),
          "invalid scale");
  }
  Check(!CalculateSurfaceZoom((std::numeric_limits<double>::max)(), 1, 1, 2, 1),
        "zoom overflow");
  Check(!CalculateSurfaceBounds(16385, 20, 1, std::nullopt, 0, 0, 0, 0),
        "surface dimension limit");
  Check(!CalculateSurfaceBounds(20, 20, 1, SurfaceOrigin{infinity, 0}, 0, 0, 0,
                                0),
        "non-finite origin");
  Check(!CalculateSurfaceBounds(20, 20, 1, SurfaceOrigin{2147483640.0, 0}, 0, 0,
                                0, 0),
        "right edge overflow");
  Check(!CalculateSurfaceBounds(20, 20, 1, SurfaceOrigin{0, -2147483650.0}, 0,
                                0, 0, 0),
        "top edge overflow");
}

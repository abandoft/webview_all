#include "../src/platform/webview_clip.h"

#include <glib.h>

#include <cmath>

namespace {

bool contains(const LinuxRoundedClip &clip, double x, double y) {
  if (x < clip[0] || x >= clip[2] || y < clip[1] || y >= clip[3]) {
    return false;
  }
  const std::array<std::array<double, 4>, 4> corners = {{
      {{clip[0] + clip[4], clip[1] + clip[5], clip[4], clip[5]}},
      {{clip[2] - clip[6], clip[1] + clip[7], clip[6], clip[7]}},
      {{clip[2] - clip[8], clip[3] - clip[9], clip[8], clip[9]}},
      {{clip[0] + clip[10], clip[3] - clip[11], clip[10], clip[11]}},
  }};
  for (size_t i = 0; i < corners.size(); ++i) {
    const auto &corner = corners[i];
    const bool left = i == 0 || i == 3;
    const bool top = i < 2;
    if ((left ? x < corner[0] : x > corner[0]) &&
        (top ? y < corner[1] : y > corner[1]) && corner[2] > 0 &&
        corner[3] > 0) {
      const double dx = (x - corner[0]) / corner[2];
      const double dy = (y - corner[1]) / corner[3];
      if (dx * dx + dy * dy > 1) {
        return false;
      }
    }
  }
  return true;
}

void assert_coverage(int x, int y, int width, int height,
                     const std::vector<LinuxRoundedClip> &clips) {
  cairo_region_t *region =
      create_linux_webview_clip_region(x, y, width, height, clips);
  g_assert_cmpint(cairo_region_status(region), ==, CAIRO_STATUS_SUCCESS);
  for (int row = -1; row <= height; ++row) {
    for (int col = -1; col <= width; ++col) {
      bool expected = row >= 0 && row < height && col >= 0 && col < width;
      for (const auto &clip : clips) {
        expected = expected && contains(clip, x + col + 0.5, y + row + 0.5);
      }
      g_assert_cmpint(cairo_region_contains_point(region, col, row), ==,
                      expected);
    }
  }
  cairo_region_destroy(region);
}

void rounded_coverage_test() {
  // A NavigationView-style single rounded corner and unequal elliptical radii.
  assert_coverage(0, 0, 100, 80, {{{0, 0, 100, 80, 8, 8, 0, 0, 0, 0, 0, 0}}});
  assert_coverage(17, 29, 100, 80,
                  {{{17, 29, 117, 109, 24, 16, 8, 12, 20, 24, 12, 8}}});
  assert_coverage(
      17, 29, 100, 80,
      {{{17.25, 29.5, 116.75, 108.25, 24, 16, 8, 12, 20, 24, 12, 8}}});
}

void nested_coverage_test() {
  assert_coverage(20, 15, 60, 55,
                  {{{0, 0, 100, 80, 40, 40, 40, 40, 40, 40, 40, 40}},
                   {{20, 10, 90, 70, 16, 8, 12, 20, 24, 16, 4, 12}}});
  assert_coverage(0, 0, 100, 80,
                  {{{0, 0, 30, 30, 15, 15, 15, 15, 15, 15, 15, 15}},
                   {{25, 25, 55, 55, 15, 15, 15, 15, 15, 15, 15, 15}}});
}

void ellipse_coverage_test() {
  assert_coverage(0, 0, 100, 80,
                  {{{0, 0, 100, 80, 50, 40, 50, 40, 50, 40, 50, 40}}});
}

void fractional_boundary_coverage_test() {
  // Pixel centers can lie exactly on a curved edge after fractional layout
  // or application scaling. Rounded sqrt results must not drop those pixels.
  assert_coverage(
      0, 0, 5, 5,
      {{{-0.5, 0, 4.5, 5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5}}});
  assert_coverage(0, 0, 11, 11,
                  {{{0.5, 0.5, 10.5, 10.5, 5, 5, 5, 5, 5, 5, 5, 5}}});
  for (double x : {0.0, 0.25, 0.5, 0.75}) {
    for (double y : {0.0, 0.25, 0.5, 0.75}) {
      for (double radius : {0.5, 1.25, 2.5, 5.0, 10.0}) {
        assert_coverage(0, 0, 30, 24,
                        {{{x, y, x + 30, y + 24, radius, radius, radius, radius,
                           radius, radius, radius, radius}}});
      }
    }
  }
}

void rectangle_coverage_test() {
  assert_coverage(-20, -10, 100, 80, {});
  assert_coverage(0, 0, 0, 80, {});
  assert_coverage(0, 0, 100, 0, {});
  // Long runs should remain compact, rather than storing each scanline.
  cairo_region_t *region = create_linux_webview_clip_region(
      0, 0, 1920, 1080, {{{0, 0, 1920, 1080, 8, 8, 0, 0, 0, 0, 0, 0}}});
  g_assert_cmpint(cairo_region_num_rectangles(region), <, 12);
  cairo_region_destroy(region);
}

} // namespace

int main(int argc, char **argv) {
  g_test_init(&argc, &argv, nullptr);
  g_test_add_func("/webview_clip/rounded", rounded_coverage_test);
  g_test_add_func("/webview_clip/nested", nested_coverage_test);
  g_test_add_func("/webview_clip/ellipse", ellipse_coverage_test);
  g_test_add_func("/webview_clip/fractional_boundary",
                  fractional_boundary_coverage_test);
  g_test_add_func("/webview_clip/rectangle", rectangle_coverage_test);
  return g_test_run();
}

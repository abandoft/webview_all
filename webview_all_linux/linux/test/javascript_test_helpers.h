#ifndef WEBVIEW_ALL_LINUX_JAVASCRIPT_TEST_HELPERS_H_
#define WEBVIEW_ALL_LINUX_JAVASCRIPT_TEST_HELPERS_H_

#include <webkit2/webkit2.h>

namespace webview_test {

struct Evaluation {
  bool done = false;
};

inline void evaluated(GObject *object, GAsyncResult *result, gpointer data) {
  auto *evaluation = static_cast<Evaluation *>(data);
  GError *error = nullptr;
  JSCValue *value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  g_assert_no_error(error);
  g_assert_nonnull(value);
  g_object_unref(value);
  evaluation->done = true;
}

inline void evaluate(WebKitWebView *view, const char *source) {
  Evaluation evaluation;
  webkit_web_view_evaluate_javascript(view, source, -1, nullptr, nullptr,
                                      nullptr, evaluated, &evaluation);
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (!evaluation.done && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_true(evaluation.done);
}

inline void load_finished(WebKitWebView *, WebKitLoadEvent event,
                          gpointer data) {
  if (event == WEBKIT_LOAD_FINISHED)
    *static_cast<bool *>(data) = true;
}

inline void load_html(WebKitWebView *view, const char *html, const char *url) {
  bool loaded = false;
  gulong signal = g_signal_connect(view, "load-changed",
                                   G_CALLBACK(load_finished), &loaded);
  webkit_web_view_load_html(view, html, url);
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (!loaded && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_signal_handler_disconnect(view, signal);
  g_assert_true(loaded);
}

}  // namespace webview_test

#endif  // WEBVIEW_ALL_LINUX_JAVASCRIPT_TEST_HELPERS_H_

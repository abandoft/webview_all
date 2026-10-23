// Build with this directory's CMakeLists.txt and run ctest under xvfb-run.
#include <webkit2/webkit2.h>

#include <algorithm>
#include <string>
#include <vector>

#include "../src/webview/webview_scroll_hook.h"
#include "javascript_test_helpers.h"

using webview_test::evaluate;
using webview_test::load_html;

static std::vector<std::string> positions;

static void received(WebKitUserContentManager *, WebKitJavascriptResult *result,
                     gpointer) {
  gchar *text =
      jsc_value_to_string(webkit_javascript_result_get_js_value(result));
  positions.emplace_back(text ? text : "");
  g_test_message("Received scroll position %s", text ? text : "");
  g_free(text);
}

static void await_position(const char *position) {
  g_test_message("Awaiting scroll position %s", position);
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (std::find(positions.begin(), positions.end(), position) ==
             positions.end() &&
         g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_true(std::find(positions.begin(), positions.end(), position) !=
                positions.end());
}

static WebKitWebView *create_view(GtkWidget **window_out) {
  WebKitUserContentManager *manager = webkit_user_content_manager_new();
  g_signal_connect(manager, "script-message-received::__webview_all_scroll",
                   G_CALLBACK(received), nullptr);
  g_assert_true(webkit_user_content_manager_register_script_message_handler(
      manager, "__webview_all_scroll"));
  WebKitUserScript *script = webkit_user_script_new(
      kScrollHookScript, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(manager, script);
  webkit_user_script_unref(script);
  WebKitWebView *view =
      WEBKIT_WEB_VIEW(webkit_web_view_new_with_user_content_manager(manager));
  *window_out = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_window_set_default_size(GTK_WINDOW(*window_out), 800, 600);
  gtk_container_add(GTK_CONTAINER(*window_out), GTK_WIDGET(view));
  gtk_widget_show_all(*window_out);
  g_object_unref(manager);
  return view;
}

static void document_open_test() {
  GtkWidget *window;
  WebKitWebView *view = create_view(&window);
  load_html(view, "<body style='height:4000px'>Scrollable</body>",
            "http://sender.example/scroll");
  evaluate(view, "window.scrollTo(0, 200); null;");
  await_position("0,200");
  positions.clear();
  // Change the position while document.open has removed Window listeners.
  // Recovery must update the native cache without the next user scroll.
  evaluate(view, R"JS(
    window.savedRoot = document.documentElement;
    document.open();
    document.appendChild(savedRoot);
    window.scrollTo(0, 0);
    document.close();
    null;
  )JS");
  await_position("0,0");
  for (int rewrite = 0; rewrite < 3; ++rewrite) {
    evaluate(view, R"JS(
      (() => {
        const root = document.documentElement;
        document.open();
        document.appendChild(root);
        document.close();
        return null;
      })();
    )JS");
    positions.clear();
    evaluate(view, "window.scrollTo(0, 350); null;");
    await_position("0,350");
    positions.clear();
    evaluate(view, "window.scrollTo(0, 0); null;");
    await_position("0,0");
  }
  // Repeated root mutations and reinjection must still leave one listener.
  evaluate(view, R"JS(
    for (let i = 0; i < 3; ++i) {
      const marker = document.createComment('root mutation');
      document.appendChild(marker);
      marker.remove();
    }
    null;
  )JS");
  evaluate(view, kScrollHookScript);
  positions.clear();
  evaluate(view, "window.dispatchEvent(new Event('scroll')); null;");
  await_position("0,0");
  g_assert_cmpuint(positions.size(), ==, 1);
  g_assert_cmpstr(positions.front().c_str(), ==, "0,0");
  // document.write replaces the root instead of reusing it.
  evaluate(view, R"JS(
    document.open();
    document.write('<body style="height:4000px">New scrollable root</body>');
    document.close();
    null;
  )JS");
  positions.clear();
  evaluate(view, "window.scrollTo(0, 450); null;");
  await_position("0,450");
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/scroll/document-open", document_open_test);
  return g_test_run();
}

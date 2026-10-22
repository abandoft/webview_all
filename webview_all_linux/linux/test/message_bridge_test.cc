// Build with this directory's CMakeLists.txt and run ctest under xvfb-run.
#include <webkit2/webkit2.h>

#include <algorithm>
#include <string>
#include <vector>

#include "../src/webview/webview_message_bridge.h"

struct Message {
  std::string text;
  std::string url;
  std::string origin;
  bool has_metadata;
  bool main_frame;
};

static std::vector<Message> messages;

static std::string string_property(JSCValue *value, const char *key) {
  JSCValue *property = jsc_value_object_get_property(value, key);
  gchar *text = jsc_value_to_string(property);
  std::string result = text ? text : "";
  g_free(text);
  g_object_unref(property);
  return result;
}

static void received(WebKitUserContentManager *, WebKitJavascriptResult *result,
                     gpointer metadata) {
  JSCValue *value = webkit_javascript_result_get_js_value(result);
  if (metadata) {
    JSCValue *main = jsc_value_object_get_property(value, "isMainFrame");
    messages.push_back({string_property(value, "message"),
                        string_property(value, "sourceUrl"),
                        string_property(value, "sourceOrigin"), true,
                        bool(jsc_value_to_boolean(main))});
    g_object_unref(main);
  } else {
    gchar *text = jsc_value_to_string(value);
    messages.push_back({text ? text : "", "", "", false, false});
    g_free(text);
  }
}

static bool has_message(const char *text) {
  return std::any_of(messages.begin(), messages.end(), [text](const Message &m) {
    return m.text == text;
  });
}

static const Message &message(const char *text) {
  auto found = std::find_if(messages.begin(), messages.end(),
                            [text](const Message &m) { return m.text == text; });
  g_assert_true(found != messages.end());
  return *found;
}

static void await_message(const char *text) {
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (!has_message(text) && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {}
    g_usleep(1000);
  }
  g_assert_true(has_message(text));
}

static WebKitWebView *create_view(bool relay, GtkWidget **window_out,
                                  bool colliding_names = false) {
  WebKitUserContentManager *manager = webkit_user_content_manager_new();
  GHashTable *channels = g_hash_table_new(g_str_hash, g_str_equal);
  const char *names[] = {"TestChannel", "JSON", "CustomEvent", "dispatchEvent",
                         "String"};
  for (const char *name : names) {
    if (!colliding_names && std::string(name) != "TestChannel") continue;
    gchar *signal = g_strdup_printf("script-message-received::%s", name);
    g_signal_connect(manager, signal, G_CALLBACK(received), nullptr);
    g_free(signal);
    g_assert_true(webkit_user_content_manager_register_script_message_handler(
        manager, name));
    g_hash_table_add(channels, const_cast<char *>(name));
  }
  if (relay) {
    g_signal_connect(manager,
                      "script-message-received::__webview_all.message_metadata",
                      G_CALLBACK(received), GINT_TO_POINTER(1));
    g_assert_true(
        webkit_user_content_manager_register_script_message_handler_in_world(
            manager, kMessageHandler, kMessageWorld));
    WebKitUserScript *script = webkit_user_script_new_for_world(
        kMessageRelayScript, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
        WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, kMessageWorld, nullptr,
        nullptr);
    webkit_user_content_manager_add_script(manager, script);
    webkit_user_script_unref(script);
  }
  gchar *source = build_javascript_channels_script(channels);
  g_hash_table_unref(channels);
  WebKitUserScript *channel = webkit_user_script_new(
      source, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(manager, channel);
  g_free(source);
  webkit_user_script_unref(channel);
  WebKitUserScript *early = webkit_user_script_new(
      "TestChannel.postMessage('user-start');",
      WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(manager, early);
  webkit_user_script_unref(early);
  WebKitWebView *view = WEBKIT_WEB_VIEW(
      webkit_web_view_new_with_user_content_manager(manager));
  *window_out = gtk_window_new(GTK_WINDOW_TOPLEVEL);
  gtk_container_add(GTK_CONTAINER(*window_out), GTK_WIDGET(view));
  gtk_widget_show_all(*window_out);
  g_object_unref(manager);
  return view;
}

static void bridge_test() {
  GtkWidget *window;
  WebKitWebView *view = create_view(true, &window);
  webkit_web_view_load_html(view, R"HTML(
    <body><script>
      TestChannel.postMessage('inline');
      history.pushState(null, '', '/next?x=1#hash');
      TestChannel.postMessage('history');
      TestChannel.postMessage(JSON.stringify({sourceUrl:'https://forged.test',
        sourceOrigin:'https://forged.test',isMainFrame:false}));
      window.webkit.messageHandlers.TestChannel.postMessage('direct');
      TestChannel.postMessage(typeof window.webkit.messageHandlers['__webview_all.message_metadata'] === 'undefined' ? 'private' : 'exposed');
      const child = document.createElement('iframe');
      child.srcdoc = '<script>TestChannel.postMessage("child")<\/script>';
      document.body.appendChild(child);
      const opaque = document.createElement('iframe');
      opaque.sandbox = 'allow-scripts';
      opaque.srcdoc = '<script>TestChannel.postMessage("opaque")<\/script>';
      document.body.appendChild(opaque);
      Object.defineProperty(Document.prototype, 'URL', {
        get: function() { return 'https://forged.test'; }});
      Object.defineProperty(window, 'origin', {value:'https://forged.test'});
      TestChannel.postMessage('overridden');
    </script>
  )HTML", "http://sender.example/start");
  await_message("opaque");
  await_message("child");
  await_message("overridden");
  g_assert_true(message("inline").has_metadata);
  g_assert_cmpstr(message("inline").url.c_str(), ==,
                  "http://sender.example/start");
  g_assert_true(message("inline").main_frame);
  g_assert_cmpstr(message("history").url.c_str(), ==,
                  "http://sender.example/next?x=1#hash");
  g_assert_cmpstr(message("overridden").url.c_str(), ==,
                  "http://sender.example/next?x=1#hash");
  g_assert_cmpstr(message("overridden").origin.c_str(), ==,
                  "http://sender.example");
  g_assert_false(message("child").main_frame);
  g_assert_cmpstr(message("child").origin.c_str(), ==,
                  "http://sender.example");
  g_assert_false(message("opaque").main_frame);
  g_assert_cmpstr(message("opaque").origin.c_str(), ==, "null");
  g_assert_false(message("direct").has_metadata);
  g_assert_true(has_message("private"));
  g_assert_true(has_message("user-start"));
  g_print("Document-start metadata available: %s\n",
          message("user-start").has_metadata ? "yes" : "no (fallback)");
  // A page-provided metadata envelope remains an ordinary message body.
  const Message &forged = message("{\"sourceUrl\":\"https://forged.test\",\"sourceOrigin\":\"https://forged.test\",\"isMainFrame\":false}");
  g_assert_cmpstr(forged.origin.c_str(), ==, "http://sender.example");
  g_assert_true(forged.main_frame);
  gtk_widget_destroy(window);
}

static void fallback_test() {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(false, &window);
  webkit_web_view_load_html(view,
      "<script>TestChannel.postMessage('fallback')</script>",
      "http://sender.example/fallback");
  await_message("fallback");
  g_assert_false(message("fallback").has_metadata);
  g_assert_true(has_message("user-start"));
  gtk_widget_destroy(window);
}

static void channel_names_test(gconstpointer relay) {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(bool(relay), &window, true);
  webkit_web_view_load_html(view, R"HTML(
    <script>
      JSON.postMessage('json-channel');
      CustomEvent.postMessage('event-channel');
      dispatchEvent.postMessage('dispatch-channel');
      String.postMessage('string-channel');
      TestChannel.postMessage('still-working');
    </script>
  )HTML", "http://sender.example/names");
  await_message("still-working");
  for (const char *text : {"json-channel", "event-channel", "dispatch-channel",
                            "string-channel", "still-working"}) {
    g_assert_true(has_message(text));
    g_assert_cmpint(message(text).has_metadata, ==, bool(relay));
  }
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/messages/isolated-relay", bridge_test);
  g_test_add_func("/messages/fallback", fallback_test);
  g_test_add_data_func("/messages/channel-names-relay", GINT_TO_POINTER(1),
                       channel_names_test);
  g_test_add_data_func("/messages/channel-names-fallback", nullptr,
                       channel_names_test);
  return g_test_run();
}

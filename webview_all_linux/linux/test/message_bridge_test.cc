// Build with this directory's CMakeLists.txt and run ctest under xvfb-run.
#include <webkit2/webkit2.h>

#include <algorithm>
#include <string>
#include <vector>

#include "../src/webview/webview_message_bridge.h"
#include "javascript_test_helpers.h"

using webview_test::evaluate;
using webview_test::load_html;

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
  return std::any_of(messages.begin(), messages.end(),
                     [text](const Message &m) { return m.text == text; });
}

static void assert_single_message(const char *text) {
  g_test_message("Checking delivery count for %s", text);
  g_assert_cmpint(
      std::count_if(messages.begin(), messages.end(),
                    [text](const Message &m) { return m.text == text; }),
      ==, 1);
}

static const Message &message(const char *text) {
  auto found =
      std::find_if(messages.begin(), messages.end(),
                   [text](const Message &m) { return m.text == text; });
  g_assert_true(found != messages.end());
  return *found;
}

static void await_message(const char *text) {
  const gint64 deadline = g_get_monotonic_time() + 15 * G_TIME_SPAN_SECOND;
  while (!has_message(text) && g_get_monotonic_time() < deadline) {
    while (g_main_context_iteration(nullptr, FALSE)) {
    }
    g_usleep(1000);
  }
  g_assert_true(has_message(text));
}

static WebKitWebView *create_view(bool relay, GtkWidget **window_out,
                                  bool colliding_names = false,
                                  bool delayed_relay = false) {
  WebKitUserContentManager *manager = webkit_user_content_manager_new();
  GHashTable *channels = g_hash_table_new(g_str_hash, g_str_equal);
  const char *names[] = {
      "TestChannel", "JSON",     "CustomEvent", "dispatchEvent", "String",
      "FocusEvent",  "Document", "Node",        "WeakSet",       "EventTarget"};
  for (const char *name : names) {
    if (!colliding_names && std::string(name) != "TestChannel")
      continue;
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
        delayed_relay ? WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_END
                      : WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
        kMessageWorld, nullptr, nullptr);
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
  WebKitWebView *view =
      WEBKIT_WEB_VIEW(webkit_web_view_new_with_user_content_manager(manager));
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
      TestChannel.postMessage(typeof window.__webviewAllMessageRelayState === 'undefined' ? 'private-state' : 'exposed-state');
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
  )HTML",
                            "http://sender.example/start");
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
  g_assert_cmpstr(message("child").origin.c_str(), ==, "http://sender.example");
  g_assert_false(message("opaque").main_frame);
  g_assert_cmpstr(message("opaque").origin.c_str(), ==, "null");
  g_assert_false(message("direct").has_metadata);
  g_assert_true(has_message("private"));
  g_assert_true(has_message("private-state"));
  g_assert_true(has_message("user-start"));
  g_print("Document-start metadata available: %s\n",
          message("user-start").has_metadata ? "yes" : "no (fallback)");
  // A page-provided metadata envelope remains an ordinary message body.
  const Message &forged = message(
      "{\"sourceUrl\":\"https://forged.test\",\"sourceOrigin\":\"https://"
      "forged.test\",\"isMainFrame\":false}");
  g_assert_cmpstr(forged.origin.c_str(), ==, "http://sender.example");
  g_assert_true(forged.main_frame);
  gtk_widget_destroy(window);
}

static void fallback_test() {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(false, &window);
  webkit_web_view_load_html(
      view, "<script>"
            "dispatchEvent(new Event('__webview_all_channel_ready'));"
            "TestChannel.postMessage('fallback')</script>",
      "http://sender.example/fallback");
  await_message("fallback");
  assert_single_message("fallback");
  g_assert_false(message("fallback").has_metadata);
  g_assert_true(has_message("user-start"));
  gtk_widget_destroy(window);
}

static void active_handshake_test() {
  messages.clear();
  GtkWidget *window;
  // Make the initialization order deterministic: the public wrapper's first
  // connection fails, and the isolated world starts only at document end.
  WebKitWebView *view = create_view(true, &window, false, true);
  load_html(view, "<body>Delayed relay</body>",
            "http://sender.example/handshake");
  await_message("user-start");
  assert_single_message("user-start");
  g_assert_false(message("user-start").has_metadata);
  evaluate(view, R"JS(
    (() => {
      const channel = TestChannel;
      const root = document.documentElement;
      // No message has retried the connection since the isolated world
      // started. Only its ready notification could have connected the target.
      document.open();
      channel.postMessage('first-after-ready');
      document.appendChild(root);
      channel.postMessage('reinsert-after-ready');
      Promise.resolve().then(() => channel.postMessage('ready-microtask'));
      setTimeout(() => channel.postMessage('ready-timer'), 100);
      return null;
    })();
  )JS");
  await_message("ready-timer");
  for (const char *text : {"first-after-ready", "reinsert-after-ready",
                            "ready-microtask", "ready-timer"}) {
    assert_single_message(text);
    const Message &received = message(text);
    g_assert_true(received.has_metadata);
    g_assert_true(received.main_frame);
    g_assert_cmpstr(received.url.c_str(), ==,
                    "http://sender.example/handshake");
    g_assert_cmpstr(received.origin.c_str(), ==, "http://sender.example");
  }
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
      FocusEvent.postMessage('focus-event-channel');
      Document.postMessage('document-channel');
      Node.postMessage('node-channel');
      WeakSet.postMessage('weak-set-channel');
      EventTarget.postMessage('event-target-channel');
      TestChannel.postMessage('still-working');
    </script>
  )HTML",
                            "http://sender.example/names");
  await_message("still-working");
  for (const char *text :
       {"json-channel", "event-channel", "dispatch-channel", "string-channel",
        "focus-event-channel", "document-channel", "node-channel",
        "weak-set-channel", "event-target-channel", "still-working"}) {
    g_assert_true(has_message(text));
    g_assert_cmpint(message(text).has_metadata, ==, bool(relay));
  }
  gtk_widget_destroy(window);
}

static void document_open_test(gconstpointer relay) {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(bool(relay), &window);
  load_html(view, "<body>Before rewrite</body>",
            "http://sender.example/rewrite");
  evaluate(view, R"JS(
    (() => {
      window.retainedChannel = TestChannel;
      TestChannel.postMessage('before-open');
      history.pushState(null, '', '/rewritten?x=1#hash');
      Object.defineProperty(Document.prototype, 'URL', {
        get: () => 'https://forged.invalid/'});
      Object.defineProperty(window, 'origin', {value: 'https://forged.invalid'});
      const root = document.documentElement;
      for (let i = 1; i <= 3; ++i) {
        document.open();
        retainedChannel.postMessage('open-' + i);
        document.appendChild(root);
        TestChannel.postMessage('reinsert-' + i);
      }
      Promise.resolve().then(() => retainedChannel.postMessage('microtask'));
      setTimeout(() => retainedChannel.postMessage('timer'), 100);
      return null;
    })();
  )JS");
  await_message("timer");
  evaluate(view, R"JS(
    document.close();
    retainedChannel.postMessage('closed');
    document.open();
    retainedChannel.postMessage('before-write');
    document.write('<!doctype html><body><script>' +
      'TestChannel.postMessage("written-script")<\/script>After rewrite</body>');
    document.close();
    retainedChannel.postMessage('after-write');
    TestChannel.postMessage('new-after-write');
    null;
  )JS");
  await_message("new-after-write");
  for (const char *text :
       {"open-1", "reinsert-1", "open-2", "reinsert-2", "open-3", "reinsert-3",
        "closed", "microtask", "timer", "before-write", "written-script",
        "after-write", "new-after-write"}) {
    assert_single_message(text);
    g_assert_cmpint(message(text).has_metadata, ==, bool(relay));
    if (relay) {
      g_assert_cmpstr(message(text).url.c_str(), ==,
                      "http://sender.example/rewritten?x=1#hash");
      g_assert_cmpstr(message(text).origin.c_str(), ==,
                      "http://sender.example");
      g_assert_true(message(text).main_frame);
    }
  }
  // A new navigation gets a fresh target and relay, with no old delivery.
  load_html(view, "<script>TestChannel.postMessage('next-document')</script>",
            "http://sender.example/next-document");
  await_message("next-document");
  assert_single_message("next-document");
  g_assert_cmpint(message("next-document").has_metadata, ==, bool(relay));
  if (relay) {
    g_assert_cmpstr(message("next-document").url.c_str(), ==,
                    "http://sender.example/next-document");
  }
  gtk_widget_destroy(window);
}

static void iframe_document_open_test() {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(true, &window);
  load_html(view, "<body>Frames</body>", "http://sender.example/frames");
  evaluate(view, R"JS(
    for (const kind of ['child', 'opaque']) {
      const frame = document.createElement('iframe');
      if (kind === 'opaque') frame.sandbox = 'allow-scripts';
      const code = "addEventListener('load',()=>setTimeout(()=>{" +
        "const channel=TestChannel;" +
        "const send=(part)=>channel.postMessage('" + kind + "-'+part);" +
        "send('before');" +
        "const root=document.documentElement;" +
        "for(let i=1;i<=2;++i){document.open();send('open-'+i);" +
        "document.appendChild(root);send('reinsert-'+i);}" +
        "document.close();send('closed');" +
        "Promise.resolve().then(()=>send('microtask'));" +
        "setTimeout(()=>send('timer'),100);},0),{once:true});";
      frame.srcdoc = '<body><script>' + code + '</script></body>';
      document.body.appendChild(frame);
    }
    null;
  )JS");
  await_message("child-timer");
  await_message("opaque-timer");
  for (const char *kind : {"child", "opaque"}) {
    for (const char *part : {"before", "open-1", "reinsert-1", "open-2", "reinsert-2",
                             "closed", "microtask", "timer"}) {
      std::string text = std::string(kind) + "-" + part;
      assert_single_message(text.c_str());
      const Message &received = message(text.c_str());
      g_assert_true(received.has_metadata);
      g_assert_false(received.main_frame);
      g_assert_cmpstr(received.url.c_str(), ==, "about:srcdoc");
      g_assert_cmpstr(received.origin.c_str(), ==,
                      std::string(kind) == "opaque" ? "null"
                                                    : "http://sender.example");
    }
  }
  gtk_widget_destroy(window);
}

static void relay_target_validation_test() {
  messages.clear();
  GtkWidget *window;
  WebKitWebView *view = create_view(true, &window);
  load_html(view, "<body>Relay validation</body>",
            "http://sender.example/validation");
  evaluate(view, R"JS(
    (() => {
      const other = document.implementation.createHTMLDocument();
      const target = other.createElement('span');
      Object.defineProperty(target, 'ownerDocument', {value: document});
      const connect = () => {
        const event = new FocusEvent('__webview_all_channel_connect', {
          relatedTarget: target, cancelable: true
        });
        window.dispatchEvent(event);
        return event.defaultPrevented;
      };
      if (connect()) throw new Error('Foreign target accepted');
      const fake = new Event('__webview_all_channel_connect', {cancelable: true});
      Object.defineProperty(fake, 'relatedTarget', {get: () => {
        throw new Error('Page getter invoked');
      }});
      window.dispatchEvent(fake);
      if (fake.defaultPrevented) throw new Error('Forged reference accepted');
      document.adoptNode(target);
      if (!connect() || !connect()) throw new Error('Local target rejected');
      const send = message => target.dispatchEvent(new CustomEvent(
        '__webview_all_channel_message', {
          detail: JSON.stringify({channelName: 'TestChannel', message}),
          cancelable: true
        }));
      send('connected-once');
      other.adoptNode(target);
      send('adopted-target');
      TestChannel.postMessage('validation-done');
      return null;
    })();
  )JS");
  await_message("validation-done");
  assert_single_message("connected-once");
  g_assert_true(message("connected-once").has_metadata);
  g_assert_false(has_message("adopted-target"));
  evaluate(view, R"JS(
    (() => {
      const root = document.documentElement;
      document.open();
      document.appendChild(root);
      document.close();
      Promise.resolve().then(() => {
        const target = document.createElement('span');
        window.dispatchEvent(new FocusEvent('__webview_all_channel_connect', {
          relatedTarget: target, cancelable: true
        }));
        target.dispatchEvent(new CustomEvent('__webview_all_channel_message', {
          detail: JSON.stringify({channelName: 'TestChannel',
                                  message: 'reconnected-after-open'}),
          cancelable: true
        }));
      });
      return null;
    })();
  )JS");
  await_message("reconnected-after-open");
  assert_single_message("reconnected-after-open");
  g_assert_true(message("reconnected-after-open").has_metadata);
  gtk_widget_destroy(window);
}

int main(int argc, char **argv) {
  gtk_test_init(&argc, &argv, nullptr);
  g_test_add_func("/messages/isolated-relay", bridge_test);
  g_test_add_func("/messages/fallback", fallback_test);
  g_test_add_func("/messages/active-handshake", active_handshake_test);
  g_test_add_data_func("/messages/channel-names-relay", GINT_TO_POINTER(1),
                       channel_names_test);
  g_test_add_data_func("/messages/channel-names-fallback", nullptr,
                       channel_names_test);
  g_test_add_data_func("/messages/document-open-relay", GINT_TO_POINTER(1),
                       document_open_test);
  g_test_add_data_func("/messages/document-open-fallback", nullptr,
                       document_open_test);
  g_test_add_func("/messages/iframe-document-open", iframe_document_open_test);
  g_test_add_func("/messages/relay-target-validation",
                  relay_target_validation_test);
  return g_test_run();
}

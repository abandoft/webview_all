#include "common/method_channel_utils.h"
#include "webview/webview_internal.h"

#include <cstring>

static FlValue *serialize_js_result(JSCValue *value) {
  if (value == nullptr || jsc_value_is_null(value) ||
      jsc_value_is_undefined(value)) {
    return fl_value_new_null();
  }
  if (jsc_value_is_boolean(value)) {
    return fl_value_new_bool(jsc_value_to_boolean(value));
  }
  if (jsc_value_is_number(value)) {
    return fl_value_new_float(jsc_value_to_double(value));
  }
  if (jsc_value_is_string(value)) {
    gchar *text = jsc_value_to_string(value);
    FlValue *result = fl_value_new_string(text);
    g_free(text);
    return result;
  }

  gchar *json = jsc_value_to_json(value, 0);
  if (json == nullptr) {
    return fl_value_new_null();
  }
  FlValue *wrapper = fl_value_new_map();
  fl_value_set_string_take(wrapper, "__json__", fl_value_new_string(json));
  g_free(json);
  return wrapper;
}

void update_history(LinuxWebView *webview) {
  FlValue *event = make_event("historyChanged");
  fl_value_set_string_take(
      event, "canGoBack",
      fl_value_new_bool(webkit_web_view_can_go_back(webview->web_view)));
  fl_value_set_string_take(
      event, "canGoForward",
      fl_value_new_bool(webkit_web_view_can_go_forward(webview->web_view)));
  send_event(webview, event);
}

void emit_url_change(LinuxWebView *webview) {
  const gchar *uri = webkit_web_view_get_uri(webview->web_view);
  if (uri == nullptr) {
    return;
  }
  FlValue *event = make_event("urlChanged");
  fl_value_set_string_take(event, "url", fl_value_new_string(uri));
  send_event(webview, event);
}

void emit_title_change(LinuxWebView *webview) {
  const gchar *title = webkit_web_view_get_title(webview->web_view);
  if (title == nullptr) {
    return;
  }
  FlValue *event = make_event("titleChanged");
  fl_value_set_string_take(event, "title", fl_value_new_string(title));
  send_event(webview, event);
}

static const gchar *error_type_name_from_error(GError *error) {
  if (error == nullptr) {
    return "unknown";
  }
  switch (error->code) {
  case WEBKIT_NETWORK_ERROR_CANCELLED:
    return "unknown";
  case WEBKIT_NETWORK_ERROR_FILE_DOES_NOT_EXIST:
    return "fileNotFound";
  case WEBKIT_NETWORK_ERROR_UNKNOWN_PROTOCOL:
    return "unsupportedScheme";
  case WEBKIT_NETWORK_ERROR_FAILED:
    return "connect";
  case WEBKIT_POLICY_ERROR_CANNOT_SHOW_URI:
    return "unsupportedScheme";
  case WEBKIT_POLICY_ERROR_CANNOT_SHOW_MIME_TYPE:
    return "file";
  case WEBKIT_DOWNLOAD_ERROR_NETWORK:
    return "connect";
  default:
    return "unknown";
  }
}

void emit_load_error(LinuxWebView *webview, GError *error,
                     const gchar *failing_url) {
  FlValue *event = make_event("webResourceError");
  fl_value_set_string_take(event, "description",
                           fl_value_new_string(error != nullptr
                                                   ? error->message
                                                   : "Navigation failed"));
  fl_value_set_string_take(
      event, "errorCode",
      fl_value_new_int(error != nullptr ? error->code : -1));
  fl_value_set_string_take(
      event, "errorType",
      fl_value_new_string(error_type_name_from_error(error)));
  fl_value_set_string_take(event, "isForMainFrame", fl_value_new_bool(true));
  if (failing_url != nullptr) {
    fl_value_set_string_take(event, "url", fl_value_new_string(failing_url));
  }
  send_event(webview, event);
}

static void script_finished_cb(GObject *object, GAsyncResult *result,
                               gpointer user_data) {
  FlMethodCall *method_call = FL_METHOD_CALL(user_data);
  GError *error = nullptr;
  JSCValue *value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), result, &error);
  if (error != nullptr) {
    respond(method_call, error_response("javascript_error", error->message));
    g_clear_error(&error);
    g_object_unref(method_call);
    return;
  }

  FlValue *payload = fl_value_new_null();
  if (value != nullptr) {
    payload = serialize_js_result(value);
    g_object_unref(value);
  }

  respond(method_call, success_response(payload));
  g_object_unref(method_call);
}

void console_message_received_cb(WebKitUserContentManager *manager,
                                 WebKitJavascriptResult *result,
                                 gpointer user_data) {
  LinuxWebView *webview = static_cast<LinuxWebView *>(user_data);
  if (!webview->console_enabled) {
    return;
  }

  JSCValue *js_value = webkit_javascript_result_get_js_value(result);
  gchar *text = jsc_value_to_string(js_value);
  if (text == nullptr) {
    return;
  }

  FlValue *event = make_event("consoleMessage");
  fl_value_set_string_take(event, "level", fl_value_new_string("log"));
  fl_value_set_string_take(event, "message", fl_value_new_string(text));
  send_event(webview, event);
  g_free(text);
}

void scroll_message_received_cb(WebKitUserContentManager *manager,
                                WebKitJavascriptResult *result,
                                gpointer user_data) {
  LinuxWebView *webview = static_cast<LinuxWebView *>(user_data);
  if (!webview->scroll_enabled) {
    return;
  }

  JSCValue *js_value = webkit_javascript_result_get_js_value(result);
  gchar *text = jsc_value_to_string(js_value);
  if (text == nullptr) {
    return;
  }

  gchar **parts = g_strsplit(text, ",", 2);
  if (parts[0] != nullptr) {
    webview->last_scroll_x = g_ascii_strtod(parts[0], nullptr);
  }
  if (parts[1] != nullptr) {
    webview->last_scroll_y = g_ascii_strtod(parts[1], nullptr);
  }

  FlValue *event = make_event("scrollPositionChange");
  fl_value_set_string_take(event, "x",
                           fl_value_new_float(webview->last_scroll_x));
  fl_value_set_string_take(event, "y",
                           fl_value_new_float(webview->last_scroll_y));
  send_event(webview, event);

  g_strfreev(parts);
  g_free(text);
}

void async_javascript_message_received_cb(WebKitUserContentManager *manager,
                                          WebKitJavascriptResult *result,
                                          gpointer user_data) {
  LinuxWebView *webview = static_cast<LinuxWebView *>(user_data);
  JSCValue *js_value = webkit_javascript_result_get_js_value(result);
  gchar *text = jsc_value_to_string(js_value);
  if (text == nullptr) {
    return;
  }

  FlValue *event = make_event("asyncJavaScriptResult");
  fl_value_set_string_take(event, "message", fl_value_new_string(text));
  send_event(webview, event);
  g_free(text);
}

void javascript_channel_message_received_cb(WebKitUserContentManager *manager,
                                            WebKitJavascriptResult *result,
                                            gpointer user_data) {
  JavaScriptChannelHandlerData *data =
      static_cast<JavaScriptChannelHandlerData *>(user_data);
  LinuxWebView *webview = data->webview;
  JSCValue *js_value = webkit_javascript_result_get_js_value(result);
  gchar *text = jsc_value_to_string(js_value);
  FlValue *event = make_event("javaScriptChannelMessage");
  fl_value_set_string_take(
      event, "channelName",
      fl_value_new_string(data->name != nullptr ? data->name : ""));
  fl_value_set_string_take(event, "message",
                           fl_value_new_string(text != nullptr ? text : ""));
  send_event(webview, event);
  g_free(text);
}

void destroy_js_channel_handler_data(gpointer data, GClosure *closure) {
  JavaScriptChannelHandlerData *handler_data =
      static_cast<JavaScriptChannelHandlerData *>(data);
  if (handler_data == nullptr) {
    return;
  }
  g_free(handler_data->name);
  g_free(handler_data);
}

void evaluate_javascript(WebKitWebView *web_view, const gchar *script,
                         FlMethodCall *method_call) {
  g_object_ref(method_call);
  webkit_web_view_evaluate_javascript(web_view, script, -1, nullptr, nullptr,
                                      nullptr, script_finished_cb, method_call);
}

static void add_user_script(WebKitUserContentManager *manager,
                            const gchar *source) {
  WebKitUserScript *script = webkit_user_script_new(
      source, WEBKIT_USER_CONTENT_INJECT_ALL_FRAMES,
      WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START, nullptr, nullptr);
  webkit_user_content_manager_add_script(manager, script);
  webkit_user_script_unref(script);
}

gchar *build_scrollbar_style_script(LinuxWebView *webview) {
  GString *css = g_string_new("");
  if (!webview->vertical_scrollbar_enabled) {
    g_string_append(css,
                    "*::-webkit-scrollbar:vertical { width: 0 !important; }\n");
  }
  if (!webview->horizontal_scrollbar_enabled) {
    g_string_append(
        css, "*::-webkit-scrollbar:horizontal { height: 0 !important; }\n");
  }

  gchar *escaped_css = g_strescape(css->str, nullptr);
  gchar *script = g_strdup_printf(R"(
    (function() {
      const styleId = '__webview_all_scrollbars';
      const css = "%s";
      let style = document.getElementById(styleId);
      if (!css) {
        if (style) {
          style.remove();
        }
        return;
      }
      if (!style) {
        style = document.createElement('style');
        style.id = styleId;
        (document.head || document.documentElement).appendChild(style);
      }
      style.textContent = css;
    })();
  )",
                                  escaped_css);
  g_free(escaped_css);
  g_string_free(css, TRUE);
  return script;
}

gchar *build_overscroll_style_script(LinuxWebView *webview) {
  const gchar *behavior = webview->over_scroll_behavior != nullptr
                              ? webview->over_scroll_behavior
                              : "";
  gchar *escaped_behavior = g_strescape(behavior, nullptr);
  gchar *script = g_strdup_printf(R"(
    (function() {
      const styleId = '__webview_all_overscroll';
      const value = "%s";
      let style = document.getElementById(styleId);
      if (!value) {
        if (style) {
          style.remove();
        }
        return;
      }
      if (!style) {
        style = document.createElement('style');
        style.id = styleId;
        (document.head || document.documentElement).appendChild(style);
      }
      style.textContent =
          'html, body { overscroll-behavior: ' + value + ' !important; }';
    })();
  )",
                                  escaped_behavior);
  g_free(escaped_behavior);
  return script;
}

void rebuild_user_scripts(LinuxWebView *webview) {
  webkit_user_content_manager_remove_all_scripts(webview->content_manager);

  gchar *scrollbar_script = build_scrollbar_style_script(webview);
  add_user_script(webview->content_manager, scrollbar_script);
  g_free(scrollbar_script);

  gchar *overscroll_script = build_overscroll_style_script(webview);
  add_user_script(webview->content_manager, overscroll_script);
  g_free(overscroll_script);

  add_user_script(webview->content_manager, R"(
    (function() {
      if (window.__webviewAllConsoleHookInstalled) return;
      window.__webviewAllConsoleHookInstalled = true;
      function stringifyArg(arg) {
        if (typeof arg === 'string') {
          return arg;
        }
        try {
          const json = JSON.stringify(arg);
          return json === undefined ? String(arg) : json;
        } catch (_) {
          return String(arg);
        }
      }
      ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
        const original = console[level];
        console[level] = function() {
          try {
            window.webkit.messageHandlers.__webview_all_console.postMessage(
              Array.from(arguments).map(stringifyArg).join(' ')
            );
          } catch (_) {}
          if (original) original.apply(console, arguments);
        };
      });
    })();
  )");

  add_user_script(webview->content_manager, R"(
    (function() {
      if (window.__webviewAllScrollHookInstalled) return;
      window.__webviewAllScrollHookInstalled = true;
      window.addEventListener('scroll', function() {
        try {
          window.webkit.messageHandlers.__webview_all_scroll.postMessage(
            [window.scrollX || 0, window.scrollY || 0].join(',')
          );
        } catch (_) {}
      }, { passive: true });
    })();
  )");

  GHashTableIter iter;
  gpointer key = nullptr;
  g_hash_table_iter_init(&iter, webview->js_channels);
  while (g_hash_table_iter_next(&iter, &key, nullptr)) {
    const gchar *name = static_cast<const gchar *>(key);
    gchar *source = g_strdup_printf(
        "window.%s = { postMessage: function(message) { "
        "window.webkit.messageHandlers.%s.postMessage(String(message)); } };",
        name, name);
    add_user_script(webview->content_manager, source);
    g_free(source);
  }

  for (guint index = 0; index < webview->user_script_order->len; ++index) {
    const gchar *identifier = static_cast<const gchar *>(
        g_ptr_array_index(webview->user_script_order, index));
    WebKitUserScript *script = static_cast<WebKitUserScript *>(
        g_hash_table_lookup(webview->user_scripts, identifier));
    if (script != nullptr) {
      webkit_user_content_manager_add_script(webview->content_manager, script);
    }
  }
}

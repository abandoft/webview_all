#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_MESSAGE_BRIDGE_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_MESSAGE_BRIDGE_H_

#include <glib.h>

// The page world has no access to this world's native message handler. DOM
// events carry message contents only; the receiving world supplies metadata.
constexpr const char *kMessageWorld = "com.abandoft.webview_all.messages";
// A dot prevents collisions with public channels, which must be JS identifiers.
constexpr const char *kMessageHandler = "__webview_all.message_metadata";
constexpr const char *kMessageRelayScript = R"JS(
(function() {
  const post = window.webkit.messageHandlers['__webview_all.message_metadata']
      .postMessage.bind(window.webkit.messageHandlers['__webview_all.message_metadata']);
  const detail = Object.getOwnPropertyDescriptor(CustomEvent.prototype, 'detail').get;
  const parse = JSON.parse;
  const preventDefault = Event.prototype.preventDefault;
  window.addEventListener('__webview_all_channel_message', function(event) {
    // Read from this world's DOM wrappers before inspecting page-owned data.
    const sourceUrl = document.URL;
    const sourceOrigin = window.origin;
    const isMainFrame = window === window.top;
    let data;
    try {
      const text = detail.call(event);
      if (typeof text !== 'string') return;
      data = parse(text);
    } catch (_) { return; }
    if (!data || typeof data.channelName !== 'string' ||
        typeof data.message !== 'string') return;
    post({channelName: data.channelName, message: data.message,
          sourceUrl: sourceUrl, sourceOrigin: sourceOrigin,
          isMainFrame: isMainFrame});
    preventDefault.call(event);
  }, true);
})();
)JS";

// Capture intrinsics before installing any channel: names such as JSON and
// CustomEvent are valid channel names and can shadow these globals.
inline gchar *build_javascript_channels_script(GHashTable *channels) {
  GString *source = g_string_new(R"JS(
    (function() {
      const dispatch = window.dispatchEvent.bind(window);
      const Event = window.CustomEvent;
      const stringify = JSON.stringify;
      const toString = String;
      const handlers = window.webkit.messageHandlers;
      function install(name) {
        const fallback = handlers[name];
        window[name] = {postMessage: function(value) {
          const message = toString(value);
          const event = new Event('__webview_all_channel_message', {
            detail: stringify({channelName: name, message: message}),
            cancelable: true
          });
          // World initialization order is unspecified. Preserve delivery
          // without claiming a sender if the isolated listener is not ready.
          if (dispatch(event)) fallback.postMessage(message);
        }};
      }
  )JS");
  GHashTableIter iter;
  gpointer key = nullptr;
  g_hash_table_iter_init(&iter, channels);
  while (g_hash_table_iter_next(&iter, &key, nullptr)) {
    // Names have already passed the JavaScript identifier check.
    g_string_append_printf(source, "install('%s');\n",
                           static_cast<const gchar *>(key));
  }
  g_string_append(source, "})();");
  return g_string_free(source, FALSE);
}

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_MESSAGE_BRIDGE_H_

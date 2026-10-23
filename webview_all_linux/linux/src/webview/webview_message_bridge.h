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
  // WebKit may reinject document-start scripts on document.write/close while
  // retaining this Window and Document. Reuse the isolated-world state so old
  // and new channel objects never acquire multiple metadata listeners.
  const previous = window.__webviewAllMessageRelayState;
  if (previous && previous.document === document) {
    previous.install();
    return;
  }
  const post = window.webkit.messageHandlers['__webview_all.message_metadata']
      .postMessage.bind(window.webkit.messageHandlers['__webview_all.message_metadata']);
  const detail = Object.getOwnPropertyDescriptor(CustomEvent.prototype, 'detail').get;
  const relatedTarget = Object.getOwnPropertyDescriptor(FocusEvent.prototype, 'relatedTarget').get;
  const ownerDocument = Object.getOwnPropertyDescriptor(Node.prototype, 'ownerDocument').get;
  const add = EventTarget.prototype.addEventListener;
  const dispatch = EventTarget.prototype.dispatchEvent;
  const ReadyEvent = window.Event;
  const parse = JSON.parse;
  const preventDefault = Event.prototype.preventDefault;
  const connected = new WeakSet();
  function receive(event) {
    // A page can observe the handshake and later adopt its target into another
    // document. Never attribute messages from that target to this document.
    if (ownerDocument.call(this) !== document) return;
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
  }
  function connect(event) {
    let target;
    try {
      // A DOM reference crosses worlds through a native event property, never
      // through page-defined getters or a page-provided metadata envelope.
      target = relatedTarget.call(event);
      if (!target || ownerDocument.call(target) !== document) return;
    } catch (_) { return; }
    if (!connected.has(target)) {
      add.call(target, '__webview_all_channel_message', receive, true);
      connected.add(target);
    }
    preventDefault.call(event);
  }
  function install() {
    add.call(window, '__webview_all_channel_connect', connect, true);
    // The page world's initial connection may have run before this world.
    // Connect waiting targets now, before a rewrite can remove Window listeners.
    dispatch.call(window, new ReadyEvent('__webview_all_channel_ready'));
  }
  window.__webviewAllMessageRelayState = { document: document, install: install };
  install();
  // If a rewrite happened before the first successful handshake, later sends
  // can reconnect once its mutation checkpoint has restored this listener.
  // Already connected targets do not depend on this asynchronous recovery.
  new MutationObserver(install).observe(document, { childList: true });
})();
)JS";

// Capture intrinsics before installing any channel: names such as JSON and
// CustomEvent are valid channel names and can shadow these globals.
inline gchar *build_javascript_channels_script(GHashTable *channels) {
  GString *source = g_string_new(R"JS(
    (function() {
      const add = EventTarget.prototype.addEventListener;
      const remove = EventTarget.prototype.removeEventListener;
      const dispatch = EventTarget.prototype.dispatchEvent;
      const Event = window.CustomEvent;
      const ConnectEvent = window.FocusEvent;
      const stringify = JSON.stringify;
      const toString = String;
      const handlers = window.webkit.messageHandlers;
      // document.open() removes Window and document-tree listeners, but leaves
      // this detached node and its isolated-world listener intact. Retained
      // channel objects can therefore keep sending synchronously during a
      // rewrite, before any observer or timer could restore a Window listener.
      const target = document.createElement('span');
      let connected = false;
      function connect() {
        if (connected) return;
        connected = !dispatch.call(window,
          new ConnectEvent('__webview_all_channel_connect', {
            relatedTarget: target, cancelable: true
          }));
        if (connected) {
          remove.call(window, '__webview_all_channel_ready', connect, true);
        }
      }
      add.call(window, '__webview_all_channel_ready', connect, true);
      connect();
      function install(name) {
        const fallback = handlers[name];
        window[name] = {postMessage: function(value) {
          const message = toString(value);
          if (!connected) connect();
          const event = new Event('__webview_all_channel_message', {
            detail: stringify({channelName: name, message: message}),
            cancelable: true
          });
          // World initialization order is unspecified. Preserve delivery
          // without claiming a sender if the isolated listener is not ready.
          if (!connected || dispatch.call(target, event)) {
            fallback.postMessage(message);
          }
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

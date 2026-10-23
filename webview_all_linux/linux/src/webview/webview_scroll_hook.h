#ifndef WEBVIEW_ALL_LINUX_WEBVIEW_SCROLL_HOOK_H_
#define WEBVIEW_ALL_LINUX_WEBVIEW_SCROLL_HOOK_H_

constexpr const char *kScrollHookScript = R"JS(
  (function() {
    if (window.__webviewAllScrollHookInstalled) return;
    window.__webviewAllScrollHookInstalled = true;
    const add = EventTarget.prototype.addEventListener;
    let lastX = window.scrollX || 0;
    let lastY = window.scrollY || 0;
    function notify() {
      lastX = window.scrollX || 0;
      lastY = window.scrollY || 0;
      try {
        window.webkit.messageHandlers.__webview_all_scroll.postMessage(
          [lastX, lastY].join(',')
        );
      } catch (_) {}
    }
    function install() {
      // Reusing the same listener makes reattachment idempotent.
      add.call(window, 'scroll', notify, { passive: true });
    }
    install();
    // document.open() removes Window listeners without clearing its globals.
    // The Document and its observer survive, including when the same root is
    // removed and appended again. Only root changes need a recovery attempt.
    new MutationObserver(function() {
      install();
      // A rewrite may reset the position while the scroll listener is absent.
      if (lastX !== (window.scrollX || 0) ||
          lastY !== (window.scrollY || 0)) notify();
    }).observe(document, { childList: true });
  })();
)JS";

#endif  // WEBVIEW_ALL_LINUX_WEBVIEW_SCROLL_HOOK_H_

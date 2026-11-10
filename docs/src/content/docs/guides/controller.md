---
title: Controller
description: Load content, navigate, run JavaScript, control scroll, and tune WebView state.
---

`WebViewController` is the central object. A controller can be attached to one `WebViewWidget` at a time and delegates all work to the active platform implementation. On platforms with offscreen support, loading, navigation callbacks, JavaScript, and channels can also run before or without attaching a widget.

## Construction

Use the default constructor for common behavior:

```dart
final controller = WebViewController();
```

Use `fromPlatformCreationParams` when the platform needs creation-time options:

```dart
PlatformWebViewControllerCreationParams params =
    const PlatformWebViewControllerCreationParams();

if (WebViewPlatform.instance is LinuxWebViewPlatform) {
  params = const LinuxWebViewControllerCreationParams(
    developerExtrasEnabled: true,
    pageCacheEnabled: true,
  );
}

final controller = WebViewController.fromPlatformCreationParams(params);
```

Use `fromPlatform` only when you already constructed a platform controller yourself:

```dart
final platformController = WindowsWebViewController(
  const WindowsWebViewControllerCreationParams(
    popupWindowPolicy: WindowsPopupWindowPolicy.sameWindow,
  ),
);

final controller = WebViewController.fromPlatform(platformController);
```

## Offscreen Native Use

Use an owning session when no visible WebView is needed:

```dart
import 'dart:async';

final session = await OffscreenWebViewSession.create();
final controller = session.controller;
final loaded = Completer<void>();

try {
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.setNavigationDelegate(
    NavigationDelegate(onPageFinished: (_) => loaded.complete()),
  );
  await controller.loadHtmlString('<script>window.price = 42;</script>');
  await loaded.future;

  final price = await controller.callAsyncJavaScript('return window.price;');
} finally {
  await session.close();
}
```

`OffscreenWebViewSession.create` throws `UnsupportedError` on OHOS and Web. Android, iOS, macOS, Windows, and Linux can operate without a widget; the owned controller may still be displayed before the session is closed. `close()` is idempotent and permanently releases the session resources without adding `dispose()` to the common controller API.

Offscreen execution still belongs to the application's Flutter engine, platform thread, window, and process lifecycle. It is not a background service or a separate isolate, and operating-system background restrictions still apply. Do not retain or use the owned controller after `close()` starts.

## Loading Content

| Method | Purpose | Notes |
| --- | --- | --- |
| `loadRequest(Uri uri, {method, headers, body})` | Load a URL or submit a request. | `uri` must have a scheme. See platform limits below. |
| `loadFile(String absoluteFilePath)` | Load a local file from the device. | Unsupported on web. |
| `loadFlutterAsset(String key)` | Load an asset declared in `pubspec.yaml`. | Web resolves to `assets/<key>`. |
| `loadHtmlString(String html, {String? baseUrl})` | Load an in-memory HTML document. | `baseUrl` is used for relative URLs. |

### Request Limits

| Platform | `GET` headers | `POST` body | `POST` custom headers |
| --- | --- | --- | --- |
| Android | Supported | Supported | Not supported by Android `postUrl`; throws. |
| iOS | Supported | Supported | Supported by `URLRequest`. |
| macOS | Supported | Supported | Supported by `URLRequest`. |
| Windows | Supported | Supported | Supported by WebView2 request bridge. |
| Linux | Supported | Supported | Supported by WebKitGTK bridge. |
| OHOS | Supported for `GET` | Supported | Not supported by ArkWeb `postUrl`; throws `UnsupportedError`. |
| Web | Supported through `fetch` path | Supported through `fetch` path | Subject to CORS preflight and response policies. |

## Navigation State

```dart
final current = await controller.currentUrl();
final title = await controller.getTitle();

if (await controller.canGoBack()) {
  await controller.goBack();
}

await controller.reload();
```

`canGoBack` and `canGoForward` reflect the platform history state. On web, `webview_all_web` maintains a logical history for loads initiated through the controller.

## JavaScript

```dart
await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
await controller.runJavaScript('document.body.dataset.ready = "true";');

final result = await controller.runJavaScriptReturningResult('1 + 2');
```

`runJavaScriptReturningResult` rejects `null` and `undefined` results, matching the platform interface contract. Complex JavaScript values must be serializable by the engine. The web implementation serializes through `JSON.stringify`.

## JavaScript Channels

```dart
await controller.addJavaScriptChannel(
  'Host',
  onMessageReceived: (JavaScriptMessage message) {
    debugPrint(message.message);
  },
);

await controller.runJavaScript('Host.postMessage("ping")');
```

Channel names must be valid JavaScript identifiers on native implementations that inject named objects. Avoid user-provided channel names unless you validate them.

## Scrolling

```dart
await controller.scrollTo(0, 0);
await controller.scrollBy(0, 300);

final position = await controller.getScrollPosition();

await controller.setOnScrollPositionChange((ScrollPositionChange change) {
  debugPrint('${change.x}, ${change.y}');
});
```

Scrollbar visibility is guarded by `supportsSetScrollBarsEnabled()`:

```dart
if (await controller.supportsSetScrollBarsEnabled()) {
  await controller.setVerticalScrollBarEnabled(false);
  await controller.setHorizontalScrollBarEnabled(false);
}
```

Since `webview_all 1.3.2`, scrollbar rendering remains engine-specific. macOS
reports this capability as unsupported because public `WKWebView` does not
expose its internal scroll view. Web and Windows implement visibility with
injected CSS.

## Appearance and Interaction

| Method | Behavior |
| --- | --- |
| `setBackgroundColor(Color color)` | Applies an engine background color where available. macOS uses a native API on 12+ and logs/no-ops on earlier versions. |
| `enableZoom(bool enabled)` | Toggles platform zoom behavior. macOS uses native magnification. |
| `setUserAgent(String? userAgent)` | Overrides the user agent where the engine allows it. Web logs once and ignores non-null overrides. |
| `getUserAgent()` | Returns the effective or platform-reported user agent when available. |
| `setOverScrollMode(WebViewOverScrollMode mode)` | Maps to native overscroll where possible or CSS `overscroll-behavior` on CSS-backed implementations. macOS logs/no-ops because no public API is available. |

## Platform Controller Access

The `platform` field is the escape hatch for engine-specific APIs:

```dart
switch (controller.platform) {
  case WindowsWebViewController windows:
    await windows.openDevTools();
  case LinuxWebViewController linux:
    await linux.setDeveloperExtrasEnabled(true);
  case OhosWebViewController ohos:
    await ohos.setTextZoom(110);
  case WebWebViewController web:
    await web.setIFrameReferrerPolicy('no-referrer');
}
```

Always guard casts by platform type. Flutter tests, desktop runners, and web builds can register different platform implementations.


## Private sessions (1.4.9)

Use `WebViewSession` to choose the website-data store before creating a page and own its lifecycle:

```dart
final capabilities = await WebViewSession.getCapabilities();
final session = await WebViewSession.create(
  mode: WebViewSessionMode.incognito,
);
if (session == null) return; // A diagnostic explains the limitation or failure.

final controller = session.controller;
await session.cookieManager.setCookie(
  const WebViewCookie(name: 'account', value: 'temporary', domain: 'example.com'),
);
// Display controller with WebViewWidget if needed. Remove the widget before closing.
await session.close();
```

`shared` selects the ordinary shared store; `incognito` (the default) selects platform private browsing handling;
`incognitoSupport` distinguishes limited handling from a native private store.
`isolatedIncognito` requires an independent native nonpersistent store.
Choose the mode at creation; it cannot be changed later. Unsupported modes and creation
failures print a diagnostic and return `null`, so the app can continue. They never fall
back to ordinary browsing or clear shared cookies to simulate private browsing.

| Platform | Private sessions |
| --- | --- |
| iOS / macOS, Linux | Independent nonpersistent stores. |
| Windows | Requires WebView2 Runtime support for InPrivate controller options; each session uses its own profile. |
| OHOS | Supports `incognito`. Native private views share one private store; `isolatedIncognito` is unavailable. |
| Android | Limited: disables cache use and available form saving and clears this view’s history. Cookies and website storage remain shared and may persist. |
| Web | Browsers do not expose independent private stores to iframes. |

`session.cookieManager` and `session.dataManager` address the selected store. Default
global managers address ordinary data, although OHOS cache clearing is global.
Android limited-incognito managers also address ordinary shared data; opening and
closing a limited session never automatically clear shared cookies. On OHOS, private clearing also
affects other native private views; ordinary data remains separate. Session cache
clearing is unsupported because ArkWeb only exposes a global cache operation. Inspect
`WebViewDataClearingResult` for individual data categories. Unsupported Web session data
operations print diagnostics and return empty results or unsupported categories.

Remove `WebViewWidget` before calling `close()`. Closing is idempotent; the controller
and session managers cannot be reused afterward. `OffscreenWebViewSession` manages
an offscreen controller's lifetime and uses ordinary storage by default.
Private mode does not promise zero OS temporary files, hide network identity, or remove
data saved separately by the app.

## Loading controls, history, and text search

```dart
await controller.stopLoading();
final capabilities = await controller.getBrowserCapabilities();
final history = await controller.getNavigationHistory();
if (history != null && history.currentIndex > 0) {
  await controller.goToHistoryIndex(history.currentIndex - 1);
}

if (capabilities.findText) {
  final result = await controller.findText('keyword');
  debugPrint('Found: ${result?.matchFound}, count: ${result?.matchCount}');
  await controller.findText('keyword'); // The same query advances to the next match.
  await controller.findText('keyword', forward: false);
  await controller.clearFindMatches();
}
```

History is a snapshot of this view's back/forward list, with zero-based indices;
query it again after navigation. Native platforms navigate through engine history.
Web includes controller-managed loads and cannot enumerate arbitrary iframe or
in-page history. `goToHistoryIndex` reports acceptance, not page completion.

Apple and Web do not report match counts; unavailable counts and positions are
`null`. Android and OHOS searches are case-insensitive and wrap around. Windows
requires a Runtime with the Find API and also requires wrapping. Query
`findCaseSensitive` and `findWithoutWrapping` before using those options.
Web search and stopping the iframe itself require same-origin or plugin-controlled
HTML. Plugin-managed fetch loads can be cancelled; the browser controls arbitrary
cross-origin iframe loads.

Unsupported new operations print a diagnostic and return `null`, `false`, or no-op
without interrupting the application.


## Page screenshots and PDF

```dart
final capabilities = await controller.getBrowserCapabilities();
if (capabilities.viewportScreenshot) {
  final png = await controller.takeScreenshot();
  // Save or display the PNG bytes in your app.
}
if (capabilities.pdfExport) {
  final pdf = await controller.createPdf();
  // Save the PDF bytes in your app.
}
```

Screenshots capture the native page viewport after layout has settled, excluding
Flutter overlays. Protected video may be omitted. Android, iOS, macOS, Windows,
Linux and OHOS support screenshots; iOS, macOS, Windows, Linux and OHOS support PDF.
Use `WebViewScreenshotOptions` for pixel-region/scale and `WebViewPdfOptions` for paper size, orientation and margins; engine pagination may differ.
Linux requires GTK's Print to File backend. Android's system print flow cannot
return PDF bytes directly. Web provides neither export API.
Unsupported or failed exports, including closed pages, log a diagnostic and
return `null`. Captures are serialized and have an output size limit.

## Native child windows

```dart
await controller.setNewWindowDelegate((request) async {
  final child = await request.createController();
  if (child == null) return;
  var attached = false;
  try {
    await child.setJavaScriptMode(JavaScriptMode.unrestricted);
    await child.setNavigationDelegate(NavigationDelegate());
    attached = await request.attach(child);
    if (attached) {
      // Display WebViewWidget(controller: child) in a new tab or route.
    }
  } finally {
    if (!attached) await child.platform.closeWebViewSession();
  }
});
```

Shared and private sessions on Android, iOS, macOS, Windows and Linux support native child
windows, preserving form POST requests and `window.opener`. Use
`request.createController()` to obtain a matching child. Configure settings,
callbacks and scripts without loading a page before attachment. Apple and Linux
require this factory because an
independent controller lacks the native request's related configuration.
Repeated factory calls return the same controller.

Your app owns the child's UI and lifetime. Handle `setOnWindowCloseRequested`,
remove the widget, then call `child.platform.closeWebViewSession()`. The app also
owns a returned controller when the request expires or attachment fails.

Android does not expose `request.url`; POST loads may bypass navigation-policy
callbacks. Enable delegation only for trusted openers. An opener can write to
the child's initial blank document before Dart receives the event.

Complete the delegate within 20 seconds. Returning without attachment rejects
the request. The `deny` policy takes priority; a null delegate restores the
configured popup policy. OHOS and Web currently log a limitation and retain their existing popup behavior.
Android's limited incognito mode still shares ordinary website data. `sameView`
only loads a URL in the current page and cannot guarantee opener or POST semantics.

## Fullscreen and renderer failures

```dart
await controller.setFullscreenDelegate(WebViewFullscreenDelegate(
  onEnter: (request) {
    // Display request.content when provided; otherwise resize the current view.
    // Keep the request and call await request.exit() to leave fullscreen.
  },
  onExit: () {
    // Remove fullscreen content and restore your application's layout.
  },
));
await controller.setOnProcessFailed((failure) {
  // Use failure.recovery to choose reloading, rebuilding, or waiting.
});
```

Query `fullscreenEvents`, `fullscreenCustomContent` and `processFailureEvents`
using `getBrowserCapabilities()`. The app owns routes, system bars and orientation;
the plugin does not change them while a delegate is installed. Android can supply
a separate fullscreen widget. Other backends retain the current view or system
media presentation. Apple notifications require iOS 16 / macOS 13; system video UI
remains system-managed and may have no DOM exit API. Web observes only this iframe's
browser fullscreen state, retains browser gesture and iframe permissions, and
never exits another element's fullscreen. Replacing or removing a delegate requests
exit and finishes the old presentation callbacks.

`true` from `exitFullscreen()` or `request.exit()` means an exit was requested.
`onExit` ends this presentation when the native view exits, the delegate changes
or is removed, or the controller is released. Without a delegate, existing platform
behavior remains.

Android 8+, Apple, Windows, Linux and OHOS can report renderer process failures.
Browsers do not expose these events to the Web backend. Android requires a new
controller after renderer loss. Apple, Linux, OHOS and a failed Windows main renderer
can recover by reloading; a failed Windows browser process requires recreation.
The plugin cancels invalid script calls and fullscreen presentations without
reloading or resubmitting POST requests. Auxiliary process failures may leave the
main page working; `recovery: none` does not require a reload.
Unsupported operations log a diagnostic and retain existing behavior.

See [Profiles and Page Tools](/webview_all/guides/profiles-and-tools/) for named stores, navigation state, printing, archives and scoped data, and [Network Control](/webview_all/guides/network/) for request delegates and custom schemes.

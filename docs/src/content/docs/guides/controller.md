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

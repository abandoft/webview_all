---
title: Controller
description: Load content, navigate, run JavaScript, control scroll, and tune WebView state.
---

`WebViewController` is the central object. A controller can be attached to one `WebViewWidget` at a time and delegates all work to the active platform implementation.

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

In `webview_all 1.2.1`, Android, iOS, macOS, Windows, Linux, OHOS, and web all expose scrollbar APIs, but the actual rendering remains engine-specific. Web and Windows implement visibility with injected CSS.

## Appearance and Interaction

| Method | Behavior |
| --- | --- |
| `setBackgroundColor(Color color)` | Applies an engine background color where available. Calls are ignored on macOS and logged to the terminal. |
| `enableZoom(bool enabled)` | Toggles platform zoom behavior. |
| `setUserAgent(String? userAgent)` | Overrides the user agent where the engine allows it. Web rejects non-null overrides. |
| `getUserAgent()` | Returns the effective or platform-reported user agent when available. |
| `setOverScrollMode(WebViewOverScrollMode mode)` | Maps to native overscroll where possible or CSS `overscroll-behavior` on CSS-backed implementations. |

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

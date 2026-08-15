---
title: Windows
description: WebView2 implementation, runtime setup, APIs, and limits.
---

Windows is provided by `webview_all_windows 1.3.6` and uses Microsoft Edge WebView2.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_windows` |
| Main platform class | `WindowsWebViewPlatform` |
| Controller | `WindowsWebViewController` |
| Widget | `WindowsWebViewWidget` |
| Navigation delegate | `WindowsNavigationDelegate` |
| Cookie manager | `WindowsWebViewCookieManager` |
| Engine | WebView2 |
| Minimum OS | Windows 10 1809+ |

## Environment

Initialize WebView2 before constructing controllers when you need custom paths or arguments:

```dart
await WindowsWebViewController.initializeEnvironment(
  userDataPath: 'C:\\AppData\\MyApp\\WebView2',
  browserExePath: null,
  additionalArguments: '--disable-features=msSmartScreenProtection',
);
```

Check runtime version:

```dart
final version = await WindowsWebViewController.getWebViewVersion();
```

If controller initialization fails, the widget displays the error in its
center with two actions:

- **Install Webview2** opens Microsoft's official WebView2 download page in the
  default browser.
- **Refresh** retries initialization on the same controller after partial
  native state and subscriptions have been cleaned up.

## Creation Params

```dart
final params = const WindowsWebViewControllerCreationParams(
  popupWindowPolicy: WindowsPopupWindowPolicy.sameWindow,
);

final controller = WebViewController.fromPlatformCreationParams(params);
```

`WindowsPopupWindowPolicy`:

| Value | Behavior |
| --- | --- |
| `allow` | Allows popup windows. |
| `deny` | Suppresses popup windows. |
| `sameWindow` | Opens popup content in the current WebView. |

## Widget Params

```dart
final widget = WebViewWidget.fromPlatformCreationParams(
  params: WindowsWebViewWidgetCreationParams(
    controller: controller.platform,
    scaleFactor: 1.0,
    filterQuality: FilterQuality.none,
  ),
);
```

`scaleFactor` controls texture rasterization scale. `filterQuality` controls Flutter texture filtering.

## Controller API

| API | Purpose |
| --- | --- |
| `openDevTools()` | Opens WebView2 DevTools. |
| `suspend()` / `resume()` | Suspends or resumes the WebView. |
| `setPopupWindowPolicy(policy)` | Changes popup handling after creation. |
| `setZoomFactor(double zoomFactor)` | Sets WebView2 zoom factor. |
| `setCacheDisabled(bool disabled)` | Toggles cache bypass behavior. |

Common APIs implemented on Windows include request loading with method, headers, and body; JavaScript execution; JavaScript channels; console messages; JavaScript dialogs; permission requests; HTTP errors; HTTP auth; SSL auth; scroll position; scrollbars; background color; user agent override; and overscroll styling.

`onNavigationRequest` covers controller loads and WebView2 main-frame navigations initiated by page content, including redirects and popups opened with `sameWindow`. Controller loads are approved before native dispatch so custom methods, headers, and bodies are preserved. Page-initiated navigations wait for the asynchronous Dart policy through cancel-and-replay, and the intentional cancellation is suppressed from `onWebResourceError`.

Local files and Flutter assets use private randomized HTTPS hosts per controller. Paths are canonicalized, asset traversal and symlink escapes are rejected, cross-origin access is denied, and mappings are cleared before unrelated remote or inline navigation.

## Cookies

Windows exposes extended WebView2 cookie metadata:

```dart
final manager = WebViewCookieManager().platform
    as WindowsWebViewCookieManager;

await manager.setWindowsCookie(
  WindowsWebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
    expires: DateTime.now().add(const Duration(days: 1)),
    isHttpOnly: true,
    isSecure: true,
    sameSite: WindowsWebViewCookieSameSite.lax,
  ),
);
```

Deletion APIs:

| API | Purpose |
| --- | --- |
| `deleteWindowsCookie(cookie)` | Deletes by full WebView2 cookie identity. |
| `deleteCookiesWithNameAndUrl(name, url)` | Deletes cookies matching a name and URL. |
| `deleteCookiesWithNameDomainAndPath(name, domain, path)` | Deletes cookies by exact identity fields. |

## Request and Error Detail

Windows-specific response classes add request and response detail:

| Type | Extra fields |
| --- | --- |
| `WindowsWebResourceRequest` | `method`, `headers`. |
| `WindowsWebResourceResponse` | `reasonPhrase`, `mimeType`. |
| `WindowsWebResourceError` | WebView2 `WebErrorStatus` index and mapped `WebResourceErrorType`. |
| `WindowsPlatformSslAuthError` | `description`, `proceed()`, `cancel()`. |

## Known Limits

- Scrollbars and overscroll are implemented with injected CSS because WebView2 does not expose stable direct APIs for every scrollbar behavior.
- The app must ensure that the WebView2 Runtime is available on target machines.
- Runtime initialization should happen once and before creating controllers.
- WebView2 environment, composition texture, and frame-capture startup failures
  are returned as `PlatformException`s instead of terminating the process
  through native assertions.
- Initialization is retryable and idempotent. Native channels, event
  subscriptions, streams, and delegates are released exactly once when the
  internal controller is finalized; no public common `dispose()` API is added.
- Surface resize updates are generation-checked after asynchronous
  initialization, so stale or post-disposal size work cannot overwrite the
  current texture size.

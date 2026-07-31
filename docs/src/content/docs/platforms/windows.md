---
title: Windows
description: WebView2 implementation, runtime setup, APIs, and limits.
---

Windows is provided by `webview_all_windows 1.3.0` and uses Microsoft Edge WebView2.

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

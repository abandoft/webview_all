---
title: Common API
description: Complete app-facing API reference for webview_all.
---

Import:

```dart
import 'package:webview_all/webview_all.dart';
```

## `WebViewController`

Constructors:

| Constructor | Use |
| --- | --- |
| `WebViewController({onPermissionRequest})` | Creates a controller using generic platform params. |
| `WebViewController.fromPlatformCreationParams(params, {onPermissionRequest})` | Creates a controller with platform-specific creation params. |
| `WebViewController.fromPlatform(platform, {onPermissionRequest})` | Wraps an existing `PlatformWebViewController`. |

Properties:

| Property | Type | Use |
| --- | --- | --- |
| `platform` | `PlatformWebViewController` | Underlying platform controller. Cast to platform-specific classes after checking type. |

Loading:

| Method | Return | Use |
| --- | --- | --- |
| `loadRequest(Uri uri, {LoadRequestMethod method, Map<String, String> headers, Uint8List? body})` | `Future<void>` | Loads a URL or HTTP request. |
| `loadFile(String absoluteFilePath)` | `Future<void>` | Loads a device file. |
| `loadFlutterAsset(String key)` | `Future<void>` | Loads a Flutter asset. |
| `loadHtmlString(String html, {String? baseUrl})` | `Future<void>` | Loads in-memory HTML. |

Navigation:

| Method | Return |
| --- | --- |
| `currentUrl()` | `Future<String?>` |
| `canGoBack()` | `Future<bool>` |
| `canGoForward()` | `Future<bool>` |
| `goBack()` | `Future<void>` |
| `goForward()` | `Future<void>` |
| `reload()` | `Future<void>` |
| `setNavigationDelegate(NavigationDelegate delegate)` | `Future<void>` |

Storage:

| Method | Return |
| --- | --- |
| `clearCache()` | `Future<void>` |
| `clearLocalStorage()` | `Future<void>` |

JavaScript:

| Method | Return |
| --- | --- |
| `setJavaScriptMode(JavaScriptMode javaScriptMode)` | `Future<void>` |
| `runJavaScript(String javaScript)` | `Future<void>` |
| `runJavaScriptReturningResult(String javaScript)` | `Future<Object>` |
| `addJavaScriptChannel(String name, {required void Function(JavaScriptMessage) onMessageReceived})` | `Future<void>` |
| `removeJavaScriptChannel(String name)` | `Future<void>` |
| `setOnConsoleMessage(callback)` | `Future<void>` |
| `setOnJavaScriptAlertDialog(callback)` | `Future<void>` |
| `setOnJavaScriptConfirmDialog(callback)` | `Future<void>` |
| `setOnJavaScriptTextInputDialog(callback)` | `Future<void>` |

View state:

| Method | Return |
| --- | --- |
| `getTitle()` | `Future<String?>` |
| `scrollTo(int x, int y)` | `Future<void>` |
| `scrollBy(int x, int y)` | `Future<void>` |
| `getScrollPosition()` | `Future<Offset>` |
| `setOnScrollPositionChange(callback?)` | `Future<void>` |
| `setVerticalScrollBarEnabled(bool enabled)` | `Future<void>` |
| `setHorizontalScrollBarEnabled(bool enabled)` | `Future<void>` |
| `supportsSetScrollBarsEnabled()` | `Future<bool>` |
| `enableZoom(bool enabled)` | `Future<void>` |
| `setBackgroundColor(Color color)` | `Future<void>` |
| `setUserAgent(String? userAgent)` | `Future<void>` |
| `getUserAgent()` | `Future<String?>` |
| `setOverScrollMode(WebViewOverScrollMode mode)` | `Future<void>` |

## `NavigationDelegate`

Constructors:

| Constructor | Use |
| --- | --- |
| `NavigationDelegate({...callbacks})` | Creates a delegate with common params. |
| `NavigationDelegate.fromPlatformCreationParams(params, {...callbacks})` | Uses platform-specific delegate params. |
| `NavigationDelegate.fromPlatform(platform, {...callbacks})` | Wraps an existing platform delegate. |

Callbacks:

| Callback | Signature | Use |
| --- | --- | --- |
| `onNavigationRequest` | `FutureOr<NavigationDecision> Function(NavigationRequest)` | Allow or block navigation. |
| `onPageStarted` | `void Function(String url)` | Main-frame load started. |
| `onPageFinished` | `void Function(String url)` | Main-frame load finished. |
| `onProgress` | `void Function(int progress)` | Load progress. |
| `onWebResourceError` | `void Function(WebResourceError error)` | Resource load error. |
| `onUrlChange` | `void Function(UrlChange change)` | URL changed. |
| `onHttpAuthRequest` | `void Function(HttpAuthRequest request)` | HTTP auth challenge. |
| `onHttpError` | `void Function(HttpResponseError error)` | HTTP status error. |
| `onSslAuthError` | `void Function(SslAuthError request)` | Recoverable SSL certificate error. |

## `SslAuthError`

| Member | Use |
| --- | --- |
| `platform` | Underlying `PlatformSslAuthError`. |
| `certificate` | Certificate where the engine provides one. |
| `cancel()` | Cancels the request. Use this by default in production. |
| `proceed()` | Continues despite the TLS error. Use only in controlled test environments. |

## `WebViewWidget`

Constructors:

| Constructor | Use |
| --- | --- |
| `WebViewWidget({controller, layoutDirection, gestureRecognizers})` | Builds the current platform WebView. |
| `WebViewWidget.fromPlatformCreationParams({params})` | Builds with platform-specific widget params. |
| `WebViewWidget.fromPlatform({platform})` | Wraps an existing platform widget. |

The widget delegates `build` to the active platform implementation.

## `WebViewCookieManager`

Constructors:

| Constructor | Use |
| --- | --- |
| `WebViewCookieManager()` | Creates a common cookie manager. |
| `WebViewCookieManager.fromPlatformCreationParams(params)` | Uses platform cookie params. |
| `WebViewCookieManager.fromPlatform(platform)` | Wraps an existing platform cookie manager. |

Methods:

| Method | Return | Use |
| --- | --- | --- |
| `clearCookies()` | `Future<bool>` | Clears cookies. |
| `setCookie(WebViewCookie cookie)` | `Future<void>` | Sets a common cookie. |
| `getCookies({required Uri domain})` | `Future<List<WebViewCookie>>` | Gets cookies visible for a domain. |

## Exported Platform Interface Types

`webview_all.dart` exports the platform interface types needed by app code, including:

- `LoadRequestMethod`
- `NavigationDecision`
- `NavigationRequest`
- `WebResourceError`
- `HttpResponseError`
- `HttpAuthRequest`
- `WebViewCredential`
- `JavaScriptMode`
- `JavaScriptMessage`
- `JavaScriptConsoleMessage`
- `JavaScriptAlertDialogRequest`
- `JavaScriptConfirmDialogRequest`
- `JavaScriptTextInputDialogRequest`
- `ScrollPositionChange`
- `WebViewCookie`
- `WebViewOverScrollMode`
- `WebViewPermissionResourceType`
- `WebViewPlatform`
- platform creation params for controller, delegate, widget, and cookie manager

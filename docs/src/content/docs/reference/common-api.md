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
| `WebViewController({onPermissionRequest, mediaPlaybackPolicy})` | Creates a controller using generic platform params. |
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
| `isOffscreenWebViewSupported()` | `Future<bool>` | Whether controller operations can run without `WebViewWidget`. |

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
| `callAsyncJavaScript(String functionBody, {Map<String, Object?> arguments, Duration timeout})` | `Future<Object?>` |
| `isUserScriptInjectionSupported(WebViewUserScriptInjectionTime injectionTime)` | `Future<bool>` |
| `addUserScript(WebViewUserScript userScript)` | `Future<String>` opaque script identifier |
| `removeUserScript(String identifier)` | `Future<void>` |
| `removeAllUserScripts()` | `Future<void>` |
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

### Browser operations (1.5.0)

| Method | Returns | Purpose |
| --- | --- | --- |
| `getBrowserCapabilities()` | `Future<WebViewBrowserCapabilities>` | Query loading, history, search, picker, media, and popup support. |
| `stopLoading()` | `Future<void>` | Stop the current load. |
| `getNavigationHistory()` | `Future<WebViewNavigationHistory?>` | Snapshot this view's back/forward list. |
| `goToHistoryIndex(index)` | `Future<bool>` | Navigate to an index in the current list. |
| `findText(text, {forward, caseSensitive, wrapAround})` | `Future<WebViewFindResult?>` | Find and select text; repeating a query advances the match. |
| `clearFindMatches()` | `Future<void>` | Clear search state. |
| `setPopupPolicy(policy)` | `Future<void>` | Configure popup handling. |
| `setFileSelector(callback)` | `Future<void>` | Handle file selection; `null` restores defaults. |
| `setMediaPlaybackRequiresUserGesture(require)` | `Future<void>` | Change the gesture requirement dynamically; use creation parameters on Apple. |

See [Cookies](/webview_all/guides/cookies/) for attributes and individual deletion.

## `WebViewSession` (1.4.9)

| API | Use |
| --- | --- |
| `getCapabilities()` | Returns supported session modes, close support, and scoped data-management support. |
| `create({mode, mediaPlaybackPolicy, onPermissionRequest})` | Returns an owned session, or logs the reason and returns `null`. Defaults to `incognito`; inspect `incognitoSupport` for the support level. |
| `controller`, `cookieManager`, `dataManager` | The owned page and managers for its selected data store. |
| `mode`, `capabilities`, `isClosed` | Session mode, runtime support, and lifecycle state. |
| `close()` | Idempotently closes the session; remove its widget first. |

## `OffscreenWebViewSession`

| API | Use |
| --- | --- |
| `OffscreenWebViewSession.create({mediaPlaybackPolicy, onPermissionRequest})` | Creates and owns an offscreen controller with default params. |
| `OffscreenWebViewSession.fromPlatformCreationParams(params)` | Creates and owns a controller with platform params. |
| `OffscreenWebViewSession.fromController(controller)` | Transfers ownership of an existing controller. |
| `controller` | Returns the owned controller until closing starts. |
| `close()` | Idempotently and permanently releases the session resources. |

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
| `onTitleChange` | `void Function(String title)` | Main document title changed; empty titles follow engine defaults. |
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
| `getCapabilities()` | `Future<WebViewCookieCapabilities>` | Readable attributes and individual deletion support. |
| `deleteCookie({name, domain, path})` | `Future<bool>` | Delete a known cookie identity. |

## `WebViewDataManager`

Constructors:

| Constructor | Use |
| --- | --- |
| `WebViewDataManager()` | Uses the current platform's default persistent website-data store. |
| `WebViewDataManager.fromPlatformCreationParams(params)` | Uses platform-specific data-manager params. |
| `WebViewDataManager.fromPlatform(platform)` | Wraps an existing `PlatformWebViewDataManager`. |

Methods:

| Method | Return | Use |
| --- | --- | --- |
| `clearAllWebsiteData()` | `Future<WebViewDataClearingResult>` | Clears controller-independent website data and reports cleared, unsupported, and failed categories. |

## Exported Types

`webview_all.dart` exports the public types needed by app code, including:

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
- `JavaScriptExecutionException`
- `JavaScriptInvocationParams`
- `JavaScriptAlertDialogRequest`
- `JavaScriptConfirmDialogRequest`
- `JavaScriptTextInputDialogRequest`
- `ScrollPositionChange`
- `WebViewCookie`
- `WebViewDataClearingResult`
- `WebViewDataType`
- `WebViewOverScrollMode`
- `WebViewPermissionResourceType`
- `WebViewPlatform`
- `WebViewUserScript`
- `WebViewUserScriptInjectionTime`
- `WebViewSession`, `WebViewSessionMode`, `WebViewSessionCapabilities`, `WebViewIncognitoSupport`
- `OffscreenWebViewSession`
- platform creation params for controller, delegate, widget, cookie manager, and data manager

## JavaScript capabilities and handlers (1.5.x)

| API | Purpose |
| --- | --- |
| `getJavaScriptCapabilities(world: ...)` | Query timing, worlds, sender metadata and content restrictions. |
| `tryAddUserScript(...)` | Register an optional document-start/end script; warn and return null when unavailable. |
| `addJavaScriptHandler(...)` | Register a JSON-compatible asynchronous Dart callback with an explicit access policy. |
| `removeJavaScriptHandler(...)` / `removeAllJavaScriptHandlers()` | Remove callbacks and cancel pending calls. |
| `callAsyncJavaScript(..., world: ...)` | Execute in a supported page or isolated world. |

See [JavaScript](/webview_all/guides/javascript/) for usage and platform limits.


## Page exports and native child windows

`WebViewController`: `takeScreenshot`, `createPdf`, `setNewWindowDelegate`,
`setOnWindowCloseRequested`, `setFullscreenDelegate`, `exitFullscreen`,
`setOnProcessFailed`. `WebViewDataManager`: `getCapabilities`,
`clearWebsiteData(dataTypes: ...)`.

`WebViewNewWindowRequest.createController()` creates a child matched to its native request.

## 1.5.x — profiles, network and page tools

| API | Purpose |
| --- | --- |
| `WebViewProfile.create`, `createSession`, `close`, `whenReleased` | Own a named or private store shared by related sessions. |
| `WebViewProfileManager.getCapabilities`, `listProfiles`, `requestDeletion` | List and safely request deletion of plugin-owned named persistent profiles. |
| `saveNavigationState`, `restoreNavigationState`, `clearNavigationHistory` | Native, memory-only history state and clearing. |
| `takeScreenshot(options: WebViewScreenshotOptions(...))` | Source-pixel region and output scale; native full-document capture on Windows/Linux. |
| `createPdf(options: WebViewPdfOptions(...))` | Paper size/margins in points and orientation. |
| `createArchive(format: ...)` | Native MHTML or WebArchive bytes. |
| `printPage`, `WebViewPrintJob` | System print UI, available job states and cancellation. |
| `getWebsiteDataRecords`, `clearWebsiteDataFor` | Explicit origin/domain/site operations through data managers. |
| `getNetworkCapabilities`, `setContentRules` | Native rules, supported actions and conditions, and runtime capabilities. |
| `setRequestDelegate`, `setCustomSchemeDelegate` | HTTP decisions and creation-time custom schemes. |
| `setContextMenuEnabled`, `setAudioMuted`, `pauseMedia`, `setMediaPlaybackSuspended` | Available native menu and media controls. |

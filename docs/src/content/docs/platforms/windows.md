---
title: Windows
description: WebView2 implementation, runtime setup, APIs, and limits.
---

Windows is provided by `webview_all_windows 1.4.0` and uses Microsoft Edge WebView2.

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

Ensure WebView2 is configured before constructing controllers when you need custom paths or arguments:

```dart
await WindowsWebViewController.ensureEnvironment(
  userDataPath: 'C:\\AppData\\MyApp\\WebView2',
  browserExePath: null,
  additionalArguments: '--disable-features=msSmartScreenProtection',
);
```

Equivalent calls reuse the active environment, including concurrent calls made
while the environment is still being created. A call with conflicting options
fails with `environment_configuration_conflict`; it never silently switches
profiles. The older `initializeEnvironment` remains available for callers that
intentionally require a single strict initialization call.

Environment creation checks the WebView2 Runtime and profile only. Graphics
capture, Direct3D, and Windows Composition are initialized later when the first
controller is created, so `ensureEnvironment` is not rejected by an unrelated
rendering capability.

Website-data cleanup can carry its own environment configuration and does not
start graphics capture or allocate a Flutter texture:

```dart
final manager = WebViewDataManager.fromPlatformCreationParams(
  const WindowsWebViewDataManagerCreationParams(
    userDataPath: 'C:\\AppData\\MyApp\\WebView2',
    additionalArguments: '--disable-features=msSmartScreenProtection',
  ),
);
final result = await manager.clearAllWebsiteData();
```

Check runtime version:

```dart
final version = await WindowsWebViewController.getWebViewVersion();
```

If controller initialization fails, the widget displays the error in its
center with recovery actions:

- **Install Webview2** is shown only when the WebView2 Runtime is unavailable
  and opens Microsoft's official download page in the default browser.
- **Refresh** retries initialization on the same controller after partial
  native state and subscriptions have been cleaned up.

If rendering fails after initialization, the widget pauses automatic surface
updates and displays **Refresh**. The action retries surface attachment and
size synchronization on the existing controller.

The renderer reuses a `DispatcherQueue` already owned by the application and
creates one only when the UI thread has none. Frame capture and its callbacks
stay on that UI-thread queue, and Direct3D falls back to the WARP software
renderer if hardware device creation fails.

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
| `ensureEnvironment(...)` | Idempotently creates or reuses the matching shared WebView2 environment. |
| `openDevTools()` | Opens WebView2 DevTools. |
| `suspend()` / `resume()` | Suspends or resumes the WebView. |
| `setPopupWindowPolicy(policy)` | Changes popup handling after creation. |
| `setZoomFactor(double zoomFactor)` | Sets WebView2 zoom factor. |
| `setCacheDisabled(bool disabled)` | Toggles cache bypass behavior. |
| `dispose()` | Permanently releases this controller and its WebView2 resources. |

Common APIs implemented on Windows include request loading with method, headers, and body; JavaScript execution; JavaScript channels; console messages; JavaScript dialogs; permission requests; HTTP errors; HTTP auth; SSL auth; scroll position; scrollbars; background color; user agent override; and overscroll styling.

`onNavigationRequest` covers controller loads and WebView2 main-frame navigations initiated by page content, including redirects and popups opened with `sameWindow`. Controller loads are approved before native dispatch so custom methods, headers, and bodies are preserved. Page-initiated navigations wait for the asynchronous Dart policy through cancel-and-replay, and the intentional cancellation is suppressed from `onWebResourceError`.

Local files and Flutter assets use private randomized HTTPS hosts per controller. Paths are canonicalized, asset traversal and symlink escapes are rejected, cross-origin access is denied, and mappings are cleared before unrelated remote or inline navigation.

## Resource Lifecycle

Removing `WebViewWidget` from the widget tree hides and detaches its native
surface, but does not destroy the controller. This preserves the normal
controller behavior: the same instance can be mounted again without losing
the current page, history, or settings.

When the owner will never use a Windows controller again, explicitly dispose
it to deterministically release the plugin's WebView2 renderer and native
resource ownership:

```dart
import 'dart:async';

@override
void dispose() {
  final platform = controller.platform;
  if (platform is WindowsWebViewController) {
    unawaited(platform.dispose());
  }
  super.dispose();
}
```

`WindowsWebViewController.dispose()` is idempotent and remains safe while
initialization is in progress. The finalizer is retained as a fallback for
unreachable controllers, but it is not a deterministic resource-lifecycle
signal. A disposed controller cannot be mounted or used again. This API is
Windows-specific; no lifecycle method is added to the common controller.

## Web Authentication and Passkeys

WebView2 does not expose an Android-style WebAuthn support-level switch.
Web pages call the standard `navigator.credentials` APIs, and the installed
WebView2 Runtime, Windows, and the selected credential provider mediate the
request. `webview_all` does not disable or replace that path.

Use a secure HTTPS relying-party origin and keep passkey requests attached to
a valid user interaction. Test registration and sign-in on every supported
Windows deployment environment. In particular, Windows Server, VDI, RDP, and
credential-provider policies can differ from a normal Windows desktop. The
page must retain another sign-in method when the platform authenticator is not
available; the plugin cannot safely emulate Windows Hello or a security key.

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
- WebAuthn availability is owned by the WebView2 Runtime, Windows, and the
  credential provider. An [upstream WebView2 report](https://github.com/MicrosoftEdge/WebView2Feedback/issues/5663)
  tracks failures observed in Windows Server and virtualized environments.
- Configure custom environment options before creating controllers or pass the same options to `WindowsWebViewDataManagerCreationParams`.
- WebView2 environment, composition texture, and frame-capture startup failures
  are returned as `PlatformException`s instead of terminating the process
  through native assertions.
- Windows initialization exceptions include a stable failure stage, HRESULT,
  remote-session flag, and the detected WebView2 Runtime version when
  available. See [Errors and Limits](/reference/errors-and-limits/).
- Initialization is retryable and idempotent. Native channels, event
  subscriptions, streams, and delegates are released exactly once by explicit
  disposal or fallback finalization.
- Surface resize updates are generation-checked and follow runtime display/DPI
  changes, so stale work cannot overwrite the current texture size.

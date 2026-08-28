---
title: Linux
description: WebKitGTK implementation, automatic GtkOverlay integration, APIs, and limits.
---

Linux is provided by `webview_all_linux 1.4.0` and uses WebKitGTK.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_linux` |
| Main platform class | `LinuxWebViewPlatform` |
| Controller | `LinuxWebViewController` |
| Widget | `LinuxWebViewWidget` |
| Navigation delegate | `LinuxNavigationDelegate` |
| Cookie manager | `LinuxWebViewCookieManager` |
| Engine | WebKitGTK |
| Required system library | `webkit2gtk-4.1` |

## Runner Integration

The Linux implementation uses a native WebKitGTK widget. The plugin
automatically installs the required `GtkOverlay` before the standard Flutter
runner realizes `FlView`; applications do not need to modify their runner.

## Creation Params

```dart
final params = const LinuxWebViewControllerCreationParams(
  developerExtrasEnabled: true,
  javascriptCanOpenWindowsAutomatically: true,
  mediaPlaybackRequiresUserGesture: false,
  mediaPlaybackAllowsInline: true,
  pageCacheEnabled: true,
  allowFileAccessFromFileUrls: false,
  allowUniversalAccessFromFileUrls: false,
  zoomTextOnly: false,
  defaultFontSize: 16,
  defaultMonospaceFontSize: 13,
  minimumFontSize: 0,
  zoomFactor: 1.0,
);
```

Each field is nullable. `null` leaves the WebKitGTK default unchanged.

## Controller API

| API | Purpose |
| --- | --- |
| `setDeveloperExtrasEnabled(bool enabled)` | Enables WebKitGTK developer extras. |
| `openDevTools()` | Opens the Web Inspector. |
| `setJavaScriptCanOpenWindowsAutomatically(bool enabled)` | Controls JavaScript popups. |
| `setMediaPlaybackRequiresUserGesture(bool require)` | Controls media autoplay policy. |
| `setMediaPlaybackAllowsInline(bool allow)` | Controls inline media playback. |
| `setPageCacheEnabled(bool enabled)` | Enables WebKitGTK page cache. |
| `setAllowFileAccessFromFileUrls(bool allow)` | Allows file pages to read other file URLs. |
| `setAllowUniversalAccessFromFileUrls(bool allow)` | Allows file pages to access all origins. |
| `setZoomTextOnly(bool enabled)` | Limits zoom to text. |
| `setDefaultFontSize(int fontSize)` | Sets proportional font size. |
| `setDefaultMonospaceFontSize(int fontSize)` | Sets monospace font size. |
| `setMinimumFontSize(int fontSize)` | Sets minimum font size. |
| `setZoomFactor(double zoomFactor)` | Sets page zoom. |
| `dispose()` | Optional Linux-specific early release of the native WebView and event subscription. |

Normal cleanup is also automatic: the Linux controller owns a finalizer that
releases its native WebView if the controller becomes unreachable. The common
`WebViewController` API does not add `dispose()`, and removing a widget does not
invalidate a controller that may be reused elsewhere.

The common `enableZoom(false)` API disables plugin-controlled WebKitGTK zoom
gestures, including Ctrl+mouse-wheel and Ctrl+`+`/`-`/`0`. Ordinary scrolling
and keyboard input continue to work.

## Event Coverage

Linux reports these native events through an event channel:

- URL changes
- page start and finish
- progress
- history changes
- title changes
- web resource errors
- HTTP response errors
- JavaScript channel messages
- console messages
- scroll position changes
- navigation requests
- HTTP auth requests
- SSL auth errors
- permission requests for camera and microphone
- JavaScript `alert`, `confirm`, `beforeunload`, and `prompt`

Native requests that wait for a Dart decision have a 30-second deadline.
Navigation is denied, authentication/dialog/TLS requests are canceled, and
permissions are denied if the application never completes a request or the
event channel closes. Exceptions from application decision callbacks are
logged on one line and use the same safe defaults instead of leaving WebKitGTK
blocked.

## Web Authentication and Passkeys

WebKitGTK does not currently provide WebAuthn support for its GTK port; the
upstream work remains tracked in
[WebKit bug 205350](https://bugs.webkit.org/show_bug.cgi?id=205350). Therefore
`webview_all_linux` does not claim passkey support or expose a setting that the
engine cannot honor. Applications that require passkeys on Linux should open
the authentication flow in a supported external browser or offer another
authentication method. The plugin does not inject a JavaScript credential
shim because it cannot reproduce WebAuthn's origin and authenticator security.

## Request Detail

| Type | Extra fields |
| --- | --- |
| `LinuxWebResourceRequest` | `method`, `headers`, `isForMainFrame`. |
| `LinuxWebResourceResponse` | `mimeType`. |
| `LinuxWebResourceError` | Mapped `WebResourceErrorType`. |
| `LinuxPlatformSslAuthError` | `description`, `proceed()`, `cancel()`. |
| `LinuxPlatformWebViewPermissionRequest` | `grant()` and `deny()` callbacks. |

## Known Limits

- The WebView is a native GTK widget, not a Flutter texture. It follows
  Flutter's logical position and size and is clipped at the Flutter viewport,
  but arbitrary Flutter layer interleaving and clip shapes cannot be reproduced
  by `GtkOverlay`.
- Translation is supported. Scale, rotation, skew, perspective, and mirrored
  transforms cannot be represented faithfully by a native GTK child; the
  plugin hides the WebView and logs the limitation instead of leaving a
  visually misaligned interactive surface.
- Local files must use absolute paths and are canonicalized before loading. Flutter asset keys containing traversal, absolute paths, or symlink escapes outside the asset bundle are rejected.
- File URL universal access is powerful and should stay disabled for untrusted local content.
- Distribution WebKitGTK versions differ; test media, permissions, and dialog flows on your target Linux distribution.
- WebAuthn/passkeys are unavailable until the WebKitGTK port implements the
  required platform authenticator integration.
- Frame updates are asynchronous and failure-isolated; stale widget teardown
  work cannot surface as an unhandled exception.

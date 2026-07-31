---
title: Linux
description: WebKitGTK implementation, GtkOverlay setup, APIs, and limits.
---

Linux is provided by `webview_all_linux 1.2.1` and uses WebKitGTK.

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

## Runner Setup

The Linux implementation uses a native WebKitGTK widget. Your runner must attach Flutter's `FlView` inside a `GtkOverlay`. See [Platform Setup](/webview_all/1.2/getting-started/platform-setup/#linux) for the full patch.

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
| `dispose()` | Releases the native WebView and event subscription. |

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

## Request Detail

| Type | Extra fields |
| --- | --- |
| `LinuxWebResourceRequest` | `method`, `headers`, `isForMainFrame`. |
| `LinuxWebResourceResponse` | `mimeType`. |
| `LinuxWebResourceError` | Mapped `WebResourceErrorType`. |
| `LinuxPlatformSslAuthError` | `description`, `proceed()`, `cancel()`. |
| `LinuxPlatformWebViewPermissionRequest` | `grant()` and `deny()` callbacks. |

## Known Limits

- The WebView is a native GTK widget, not a Flutter texture. Layering and clipping follow GTK overlay behavior.
- File URL universal access is powerful and should stay disabled for untrusted local content.
- Distribution WebKitGTK versions differ; test media, permissions, and dialog flows on your target Linux distribution.

---
title: iOS and macOS
description: WKWebView implementation, WebKit APIs, and Apple platform differences.
---

iOS and macOS are provided by `webview_all_wkwebview ^1.3.1`. `webview_all` registers it as the default implementation for both Apple platforms.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_wkwebview` |
| Main platform class | `WebKitWebViewPlatform` |
| Controller | `WebKitWebViewController` |
| Widget | `WebKitWebViewWidget` |
| Navigation delegate | `WebKitNavigationDelegate` |
| Cookie manager | `WebKitWebViewCookieManager` |
| Engine | `WKWebView` |
| Minimum iOS | 13.0+ |
| Minimum macOS | 10.15+ |

## Creation Params

```dart
final params = WebKitWebViewControllerCreationParams(
  allowsInlineMediaPlayback: true,
  mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
  limitsNavigationsToAppBoundDomains: false,
  javaScriptCanOpenWindowsAutomatically: true,
);

final controller = WebViewController.fromPlatformCreationParams(params);
```

| Param | Meaning |
| --- | --- |
| `mediaTypesRequiringUserAction` | Set of `PlaybackMediaTypes.audio` and `PlaybackMediaTypes.video` that require user gesture. Empty set allows autoplay. |
| `allowsInlineMediaPlayback` | Allows inline HTML5 video playback instead of fullscreen-only playback. |
| `limitsNavigationsToAppBoundDomains` | Enables App-Bound Domains on iOS 14+ and macOS 11+. Earlier systems log the requirement and keep the native default. |
| `javaScriptCanOpenWindowsAutomatically` | Controls JavaScript popup permission. `null` uses the native default. |

## Controller API

| API | Purpose |
| --- | --- |
| `setAllowsBackForwardNavigationGestures(bool enabled)` | Enables swipe navigation gestures. |
| `setAllowsLinkPreview(bool allow)` | Enables or disables link previews where supported. |
| `setOnCanGoBackChange(callback)` | Receives `canGoBack` state changes. |
| `setInspectable(bool inspectable)` | Enables WebKit inspection on iOS 16.4+ and macOS 13.3+. Earlier systems log the requirement and safely ignore the call. |
| `loadFileWithParams(WebKitLoadFileParams params)` | Loads a local file with an explicit read access scope. |

## Local Files

```dart
await (controller.platform as WebKitWebViewController).loadFileWithParams(
  WebKitLoadFileParams(
    absoluteFilePath: '/Users/me/site/index.html',
    readAccessPath: '/Users/me/site',
  ),
);
```

`readAccessPath` must include any local resources referenced by the loaded page.

## JavaScript Channels

Use `WebKitJavaScriptChannelParams` when constructing platform-specific channel params directly:

```dart
await controller.platform.addJavaScriptChannel(
  WebKitJavaScriptChannelParams(
    name: 'Host',
    onMessageReceived: (JavaScriptMessage message) {},
  ),
);
```

The common `WebViewController.addJavaScriptChannel` automatically converts common params to WebKit params.

## Permissions

`WebKitWebViewPermissionRequest` supports:

| Method | Meaning |
| --- | --- |
| `grant()` | Approves the resource request. |
| `deny()` | Denies the resource request. |
| `prompt()` | Lets the system prompt the user where supported. |

Your app still needs the corresponding `Info.plist` privacy description keys.

## macOS Differences

The same Dart package targets iOS and macOS. macOS support uses public native
WebKit APIs with runtime availability checks; it does not inject JavaScript to
emulate missing view APIs.

| Area | macOS limit |
| --- | --- |
| Scroll position and callbacks | macOS `WKWebView` does not publicly expose its internal scroll view. Calls log the limitation and safely no-op; reads return `Offset.zero`. |
| Scrollbar visibility and overscroll | No public macOS `WKWebView` API is available. Calls log the limitation and safely no-op. |
| Background color | Uses native `underPageBackgroundColor` on macOS 12+. Earlier versions log the requirement and safely no-op. |
| Zoom | Uses native `allowsMagnification`; no JavaScript fallback is used. |
| Inspection | Requires macOS 13.3+. Earlier versions log the requirement and safely no-op. |
| Link preview | Availability depends on platform support. |

These compatibility decisions are handled by `webview_all_wkwebview`, not by
the main `webview_all` controller.

## Known Limits

- WebKit may reject JavaScript return values that cannot be bridged to Dart.
- App-Bound Domains require host app configuration and iOS 14+ or macOS 11+.
- Permission handling still depends on OS privacy entitlements and user decisions.

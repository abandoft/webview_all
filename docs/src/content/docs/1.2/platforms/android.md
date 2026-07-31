---
title: Android
description: Android WebView implementation, APIs, and platform limits.
---

Android is provided by `webview_flutter_android ^4.12.0`. `webview_all` registers it as the default Android implementation.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_flutter_android` |
| Main platform class | `AndroidWebViewPlatform` |
| Controller | `AndroidWebViewController` |
| Widget | `AndroidWebViewWidget` |
| Navigation delegate | `AndroidNavigationDelegate` |
| Cookie manager | `AndroidWebViewCookieManager` |
| Engine | Android `WebView` |
| Minimum supported by `webview_all` | API 24+ |

## Creation Params

```dart
final params = AndroidWebViewControllerCreationParams();
final controller = WebViewController.fromPlatformCreationParams(params);
```

`AndroidWebViewControllerCreationParams` mainly exposes test injection for Android `WebStorage`. Runtime settings are configured on the platform controller after construction.

## Controller API

| API | Purpose |
| --- | --- |
| `AndroidWebViewController.enableDebugging(bool enabled)` | Enables Android WebView debugging globally. |
| `setAllowFileAccess(bool allow)` | Allows or blocks file URL access. |
| `setMediaPlaybackRequiresUserGesture(bool require)` | Controls automatic media playback. |
| `setTextZoom(int textZoom)` | Sets text zoom percentage. |
| `setUseWideViewPort(bool use)` | Enables viewport meta tag and wide viewport behavior. |
| `setAllowContentAccess(bool enabled)` | Allows or blocks `content://` URL access. |
| `setGeolocationEnabled(bool enabled)` | Enables WebView geolocation support. |
| `setOnShowFileSelector(callback)` | Handles `<input type="file">`. |
| `setGeolocationPermissionsPromptCallbacks(...)` | Handles Geolocation API permission prompts. |
| `setCustomWidgetCallbacks(...)` | Handles fullscreen custom views, commonly video. |
| `setMixedContentMode(MixedContentMode mode)` | Controls HTTPS pages loading HTTP content. |
| `isWebViewFeatureSupported(WebViewFeatureType featureType)` | Queries AndroidX WebView feature support. |
| `setPaymentRequestEnabled(bool enabled)` | Enables Payment Request API when supported. |
| `setInsetsForWebContentToIgnore(List<AndroidWebViewInsets> insets)` | Prevents selected window insets from reaching web content. |

## File Loading with Headers

```dart
await (controller.platform as AndroidWebViewController).loadFileWithParams(
  AndroidLoadFileParams(
    absoluteFilePath: '/sdcard/Download/help.html',
    headers: const <String, String>{'X-App': 'example'},
  ),
);
```

## Mixed Content

```dart
await (controller.platform as AndroidWebViewController)
    .setMixedContentMode(MixedContentMode.neverAllow);
```

Values:

| Value | Behavior |
| --- | --- |
| `MixedContentMode.alwaysAllow` | Allows secure pages to load insecure content. |
| `MixedContentMode.compatibilityMode` | Uses Android WebView compatibility behavior. |
| `MixedContentMode.neverAllow` | Blocks insecure content from secure pages. |

## Payment Request

```dart
final android = controller.platform as AndroidWebViewController;

if (await android.isWebViewFeatureSupported(
  WebViewFeatureType.paymentRequest,
)) {
  await android.setPaymentRequestEnabled(true);
}
```

Payment apps may require Android manifest `queries` entries so WebView can discover installed payment handlers.

## Permission Resources

Android supports the common `camera` and `microphone` resource types, plus:

| Type | Meaning |
| --- | --- |
| `AndroidWebViewPermissionResourceType.midiSysex` | MIDI sysex. |
| `AndroidWebViewPermissionResourceType.protectedMediaId` | Protected media identifier. |

## File Selector

```dart
await (controller.platform as AndroidWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  return pickFiles(
    allowMultiple: params.mode == FileSelectorMode.openMultiple,
    acceptedTypes: params.acceptTypes,
  );
});
```

`FileSelectorMode` values are `open`, `openMultiple`, and `save`.

## Known Limits

- `loadRequest` cannot send custom headers with a POST body because Android WebView's `postUrl` API does not expose headers.
- WebView permission approval does not replace Android runtime permissions. Your app must request system permissions separately.
- Payment Request depends on AndroidX WebKit feature support and the installed WebView version.

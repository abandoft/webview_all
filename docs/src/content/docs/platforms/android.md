---
title: Android
description: Android WebView implementation, APIs, and platform limits.
---

Android is provided by `webview_all_android ^1.3.8`. `webview_all` registers it as the default Android implementation.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_android` |
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
| `setWebAuthenticationSupport(WebAuthenticationSupport support)` | Enables WebAuthn for an associated app or an eligible browser app. |
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

## Web Authentication and Passkeys

Android WebView disables WebAuthn by default. Check the installed WebView's
feature support before enabling it:

```dart
final android = controller.platform as AndroidWebViewController;

if (await android.isWebViewFeatureSupported(
  WebViewFeatureType.webAuthentication,
)) {
  await android.setWebAuthenticationSupport(
    WebAuthenticationSupport.forApp,
  );
}
```

`forApp` is the normal application mode. The relying-party domain must be
associated with the Android app through
[Digital Asset Links](https://developers.google.com/digital-asset-links).
`forBrowser` allows requests for arbitrary relying parties, but it is only for
privileged browser apps approved by the credential provider; it is not a way
for an ordinary application to bypass origin association. Use `none` to turn
the feature off. `none` is the AndroidX WebKit default.

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

## Cookies and Native Access

`getCookies` splits Android's cookie header at semicolons and each entry at its
first equals sign, so encoded values and values containing `=` are preserved.
Malformed percent escapes are returned literally instead of failing the whole
query. Returned entries use the requested host and `/`.

Native Android clients can retrieve a plugin-owned `WebView` from either a
`FlutterPluginBinding` or the deprecated `FlutterEngine` overload of
`WebViewFlutterAndroidExternalApi`. The binding overload remains compatible
with Flutter 3.35 by using its engine plugin registry.

## Known Limits

- `loadRequest` cannot send custom headers with a POST body because Android WebView's `postUrl` API does not expose headers.
- WebView permission approval does not replace Android runtime permissions. Your app must request system permissions separately.
- Payment Request depends on AndroidX WebKit feature support and the installed WebView version.
- WebAuthn depends on AndroidX WebKit feature support, the installed WebView,
  and correct app-to-site association. Calling its setter without a successful
  feature check can throw an unsupported-operation error.
- The Android plugin selects its Kotlin integration from the host project's
  Android Gradle Plugin: AGP 8 and earlier use the Kotlin Gradle Plugin, while
  AGP 9 and later use Built-in Kotlin. This keeps older Flutter projects
  compatible without conflicting with newer Android builds.

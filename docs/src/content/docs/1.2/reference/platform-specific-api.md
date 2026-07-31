---
title: Platform API
description: Platform-specific public APIs exposed by webview_all and its registered platform packages.
---

Access platform APIs through creation params and the `platform` field:

```dart
final controller = WebViewController();

if (controller.platform is WindowsWebViewController) {
  await (controller.platform as WindowsWebViewController).openDevTools();
}
```

## Android

Package: `webview_flutter_android`.

Main types: `AndroidWebViewController`, `AndroidWebViewWidget`, `AndroidNavigationDelegate`, `AndroidWebViewCookieManager`, `AndroidLoadFileParams`, `AndroidJavaScriptChannelParams`, `AndroidWebViewPermissionRequest`, `AndroidWebViewPermissionResourceType`, `AndroidSslAuthError`, `AndroidWebResourceError`, `AndroidUrlChange`, `FileSelectorParams`.

Important APIs: debugging, file/content access, media gesture, text zoom, wide viewport, geolocation, file selector, custom fullscreen widget, console, JS dialogs, scrollbars, overscroll, mixed content, Payment Request, window insets.

## iOS/macOS

Package: `webview_flutter_wkwebview`.

Main types: `WebKitWebViewController`, `WebKitWebViewWidget`, `WebKitNavigationDelegate`, `WebKitWebViewCookieManager`, `WebKitLoadFileParams`, `WebKitJavaScriptChannelParams`, `WebKitWebViewPermissionRequest`, `WebKitSslAuthError`, `WebKitWebResourceError`.

Important APIs: inline media, media gesture, App-Bound Domains, JavaScript popup policy, back/forward gestures, link preview, inspectable, WebKit local file read access, permission prompt.

## Windows

Package: `webview_all_windows`.

Main types: `WindowsWebViewController`, `WindowsWebViewWidget`, `WindowsNavigationDelegate`, `WindowsWebViewCookieManager`, `WindowsWebViewCookie`, `WindowsPlatformSslAuthError`, `WindowsWebResourceRequest`, `WindowsWebResourceResponse`, `WindowsWebResourceError`.

Important APIs: `initializeEnvironment`, `getWebViewVersion`, `openDevTools`, `suspend`, `resume`, `setPopupWindowPolicy`, `setZoomFactor`, `setCacheDisabled`, full cookie set/query/delete.

## Linux

Package: `webview_all_linux`.

Main types: `LinuxWebViewController`, `LinuxWebViewWidget`, `LinuxNavigationDelegate`, `LinuxWebViewCookieManager`, `LinuxWebResourceRequest`, `LinuxWebResourceResponse`, `LinuxWebResourceError`, `LinuxPlatformWebViewPermissionRequest`, `LinuxPlatformSslAuthError`.

Important APIs: WebKitGTK developer extras, Inspector, JS popup, media settings, page cache, file URL access, font size, zoom factor, dispose.

## OHOS

Package: `webview_all_ohos`.

Main types: `OhosWebViewController`, `OhosWebViewWidget`, `OhosNavigationDelegate`, `OhosWebViewCookieManager`, `OhosJavaScriptChannelParams`, `OhosWebViewPermissionRequest`, `OhosWebViewPermissionResourceType`, `OhosUrlChange`, `OhosWebResourceRequest`, `OhosWebResourceResponse`, `OhosWebResourceError`, `OhosPlatformSslAuthError`, `FileSelectorParams`.

Important APIs: ArkWeb debugging, native WebView ID, DOM storage, multiple windows, viewport, zoom, file access, media gesture, file selector, geolocation prompt, custom fullscreen widget, third-party cookies.

## Web

Package: `webview_all_web`.

Main types: `WebWebViewController`, `WebWebViewWidget`, `WebNavigationDelegate`, `WebWebViewCookieManager`, `WebWebResourceRequest`, `WebWebResourceResponse`, `WebWebViewPermissionRequest`, `WebPlatformSslAuthError`, `HttpRequestFactory`, `ContentType`.

Important APIs: `setIFrameAttribute`, `setIFrameAllow`, `setIFrameSandbox`, `setIFrameReferrerPolicy`, fetch-backed request.

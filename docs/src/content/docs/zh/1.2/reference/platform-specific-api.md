---
title: 平台专属接口
description: webview_all 及注册平台包暴露的专属 API。
---

平台 API 通过 creation params 和 `platform` 字段访问：

```dart
final controller = WebViewController();

if (controller.platform is WindowsWebViewController) {
  await (controller.platform as WindowsWebViewController).openDevTools();
}
```

## Android

包：`webview_flutter_android`。

主要类型：`AndroidWebViewController`、`AndroidWebViewWidget`、`AndroidNavigationDelegate`、`AndroidWebViewCookieManager`、`AndroidLoadFileParams`、`AndroidJavaScriptChannelParams`、`AndroidWebViewPermissionRequest`、`AndroidWebViewPermissionResourceType`、`AndroidSslAuthError`、`AndroidWebResourceError`、`AndroidUrlChange`、`FileSelectorParams`。

重要 API：debugging、file/content access、media gesture、text zoom、wide viewport、geolocation、file selector、custom fullscreen widget、console、JS dialogs、scrollbars、overscroll、mixed content、Payment Request、window insets。

## iOS/macOS

包：`webview_flutter_wkwebview`。

主要类型：`WebKitWebViewController`、`WebKitWebViewWidget`、`WebKitNavigationDelegate`、`WebKitWebViewCookieManager`、`WebKitLoadFileParams`、`WebKitJavaScriptChannelParams`、`WebKitWebViewPermissionRequest`、`WebKitSslAuthError`、`WebKitWebResourceError`。

重要 API：inline media、media gesture、App-Bound Domains、JavaScript popup policy、back/forward gestures、link preview、inspectable、WebKit 本地文件 read access、permission prompt。

## Windows

包：`webview_all_windows`。

主要类型：`WindowsWebViewController`、`WindowsWebViewWidget`、`WindowsNavigationDelegate`、`WindowsWebViewCookieManager`、`WindowsWebViewCookie`、`WindowsPlatformSslAuthError`、`WindowsWebResourceRequest`、`WindowsWebResourceResponse`、`WindowsWebResourceError`。

重要 API：`initializeEnvironment`、`getWebViewVersion`、`openDevTools`、`suspend`、`resume`、`setPopupWindowPolicy`、`setZoomFactor`、`setCacheDisabled`、完整 cookie 设置/查询/删除。

## Linux

包：`webview_all_linux`。

主要类型：`LinuxWebViewController`、`LinuxWebViewWidget`、`LinuxNavigationDelegate`、`LinuxWebViewCookieManager`、`LinuxWebResourceRequest`、`LinuxWebResourceResponse`、`LinuxWebResourceError`、`LinuxPlatformWebViewPermissionRequest`、`LinuxPlatformSslAuthError`。

重要 API：WebKitGTK developer extras、Inspector、JS popup、media settings、page cache、file URL access、font size、zoom factor、dispose。

## OHOS

包：`webview_all_ohos`。

主要类型：`OhosWebViewController`、`OhosWebViewWidget`、`OhosNavigationDelegate`、`OhosWebViewCookieManager`、`OhosJavaScriptChannelParams`、`OhosWebViewPermissionRequest`、`OhosWebViewPermissionResourceType`、`OhosUrlChange`、`OhosWebResourceRequest`、`OhosWebResourceResponse`、`OhosWebResourceError`、`OhosPlatformSslAuthError`、`FileSelectorParams`。

重要 API：ArkWeb debugging、native WebView ID、DOM storage、多窗口、viewport、zoom、file access、media gesture、file selector、geolocation prompt、custom fullscreen widget、第三方 cookie。

## Web

包：`webview_all_web`。

主要类型：`WebWebViewController`、`WebWebViewWidget`、`WebNavigationDelegate`、`WebWebViewCookieManager`、`WebWebResourceRequest`、`WebWebResourceResponse`、`WebWebViewPermissionRequest`、`WebPlatformSslAuthError`、`HttpRequestFactory`、`ContentType`。

重要 API：`setIFrameAttribute`、`setIFrameAllow`、`setIFrameSandbox`、`setIFrameReferrerPolicy`、fetch-backed request。

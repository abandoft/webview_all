---
title: Android
description: Android WebView 实现、API 和限制。
---

Android 由 `webview_flutter_android ^4.12.0` 提供，`webview_all` 将它注册为默认 Android 实现。

| 项 | 值 |
| --- | --- |
| 平台包 | `webview_flutter_android` |
| Controller | `AndroidWebViewController` |
| Widget | `AndroidWebViewWidget` |
| Delegate | `AndroidNavigationDelegate` |
| Cookie manager | `AndroidWebViewCookieManager` |
| 引擎 | Android `WebView` |
| 最低要求 | API 24+ |

## 主要 API

| API | 作用 |
| --- | --- |
| `AndroidWebViewController.enableDebugging` | 全局启用 WebView 调试。 |
| `setAllowFileAccess` | 控制 file URL 访问。 |
| `setMediaPlaybackRequiresUserGesture` | 控制媒体自动播放。 |
| `setTextZoom` | 设置文字缩放百分比。 |
| `setUseWideViewPort` | 启用 viewport meta/wide viewport。 |
| `setAllowContentAccess` | 控制 `content://` 访问。 |
| `setGeolocationEnabled` | 启用定位。 |
| `setOnShowFileSelector` | 处理 `<input type="file">`。 |
| `setGeolocationPermissionsPromptCallbacks` | 处理 Geolocation API 提示。 |
| `setCustomWidgetCallbacks` | 处理视频等全屏 custom view。 |
| `setMixedContentMode` | 控制 HTTPS 页面加载 HTTP 内容。 |
| `isWebViewFeatureSupported` | 查询 AndroidX WebView 功能。 |
| `setPaymentRequestEnabled` | 开启 Payment Request API。 |
| `setInsetsForWebContentToIgnore` | 控制传给网页的 window insets。 |

## Mixed Content

```dart
await (controller.platform as AndroidWebViewController)
    .setMixedContentMode(MixedContentMode.neverAllow);
```

`neverAllow` 是生产环境推荐值。

## 文件选择

```dart
await (controller.platform as AndroidWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  return <String>['/sdcard/Download/file.png'];
});
```

`FileSelectorMode` 包括 `open`、`openMultiple` 和 `save`。

## 平台限制

- Android WebView `postUrl` 不支持 POST 自定义 headers。
- `grant()` WebView 权限不等于系统运行时权限，宿主应用仍需自己请求。
- Payment Request 取决于 AndroidX WebKit、系统 WebView/Chrome 版本和 manifest queries。

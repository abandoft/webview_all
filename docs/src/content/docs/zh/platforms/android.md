---
title: Android
description: Android WebView 实现、API 和限制。
---

Android 由 `webview_all_android ^1.5.2` 提供，`webview_all` 将它注册为默认 Android 实现。

| 项 | 值 |
| --- | --- |
| 平台包 | `webview_all_android` |
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
| `setWebAuthenticationSupport` | 为已关联应用或具备资格的浏览器应用启用 WebAuthn。 |
| `setPaymentRequestEnabled` | 开启 Payment Request API。 |
| `setInsetsForWebContentToIgnore` | 控制传给网页的 window insets。 |

## Mixed Content

```dart
await (controller.platform as AndroidWebViewController)
    .setMixedContentMode(MixedContentMode.neverAllow);
```

`neverAllow` 是生产环境推荐值。

## WebAuthn 与 Passkey

Android WebView 默认关闭 WebAuthn。启用前必须先检查当前设备与
WebView 版本是否支持：

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

`forApp` 是普通应用应使用的模式，并且必须通过
[Digital Asset Links](https://developers.google.com/digital-asset-links)
关联应用与 relying-party 域名。`forBrowser` 只适用于经凭据提供方
批准、可代表第三方站点请求凭据的特权浏览器应用，普通应用不应使用它绕过
域名关联。`none` 用于关闭功能，也是 AndroidX WebKit 的默认值。

## 文件选择

```dart
await (controller.platform as AndroidWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  return <String>['/sdcard/Download/file.png'];
});
```

`FileSelectorMode` 包括 `open`、`openMultiple` 和 `save`。

## Cookie 与 native 访问

System WebView 支持 `GET_COOKIE_INFO` 时，`getCookies` 返回原生 domain/path、
过期时间及安全属性，缺失的 SameSite 保留为未知。旧版内核只返回名称和值，
domain/path 使用请求 URL 的 host 和 `/` 作为兼容占位；删除时不能用占位值推测实际身份。
值中的 `=` 会保留，非法百分号编码按原文返回。

Android native 代码可通过 `WebViewFlutterAndroidExternalApi` 的
`FlutterPluginBinding` 入口获取插件持有的 `WebView`；旧
`FlutterEngine` 重载保留但已弃用。binding 入口使用 engine plugin registry
实现，因此仍兼容 Flutter 3.35。

## 平台限制

- Android WebView `postUrl` 不支持 POST 自定义 headers。
- `grant()` WebView 权限不等于系统运行时权限，宿主应用仍需自己请求。
- Payment Request 取决于 AndroidX WebKit、系统 WebView/Chrome 版本和 manifest queries。
- WebAuthn 取决于 AndroidX WebKit、系统 WebView 版本和正确的应用-站点关联；
  未通过功能检查就调用设置接口可能产生不支持错误。
- Android 插件会根据宿主工程的 Android Gradle Plugin 选择 Kotlin 集成方式：
  AGP 8 及以下使用 Kotlin Gradle Plugin，AGP 9 及以上使用 Built-in Kotlin，
  从而兼容旧版 Flutter 工程并避免与新版 Android 构建冲突。

## 暗化、存储和缓存

以下 Android 扩展自 1.5.1 提供，返回值表示设置是否成功：

```dart
final android = controller.platform as AndroidWebViewController;
await android.setAlgorithmicDarkeningAllowed(true);
await android.setDomStorageEnabled(false);
await android.setCacheMode(AndroidWebViewCacheMode.noCache);
```

请在加载网页前设置。算法暗化取决于应用的原生主题和网页自身样式，不会强制
所有网页变暗或注入 CSS。不支持的内核或 target SDK 低于 33 时返回 `false`
并打印原因，不使用旧 `forceDark` 接口替代。

DOM 存储默认开启；关闭后不删除已有数据，也不隔离 Cookie，重新开启后仍可
访问之前保存的数据。

缓存模式包括 `defaultMode`（遵循 HTTP 缓存策略）、`cacheElseNetwork`
（优先已有缓存，包括过期内容）、`noCache`（不读缓存）和 `cacheOnly`
（仅缓存，未命中时失败）。Service Worker 自己维护的缓存不由此设置控制。
有限无痕视图只接受 `noCache`，其他模式返回 `false` 并保留原策略。
需要删除数据时使用网站数据管理接口。

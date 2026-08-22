---
title: 通用接口
description: webview_all 应用侧 API 参考。
---

导入：

```dart
import 'package:webview_all/webview_all.dart';
```

## `WebViewController`

构造函数：

| 构造函数 | 用途 |
| --- | --- |
| `WebViewController({onPermissionRequest})` | 使用通用参数创建 controller。 |
| `WebViewController.fromPlatformCreationParams(params, {onPermissionRequest})` | 使用平台创建参数。 |
| `WebViewController.fromPlatform(platform, {onPermissionRequest})` | 包装已有平台 controller。 |

加载：

| 方法 | 返回 | 说明 |
| --- | --- | --- |
| `loadRequest` | `Future<void>` | 加载 URL 或 HTTP 请求。 |
| `loadFile` | `Future<void>` | 加载设备文件。 |
| `loadFlutterAsset` | `Future<void>` | 加载 Flutter asset。 |
| `loadHtmlString` | `Future<void>` | 加载内存 HTML。 |
| `isOffscreenWebViewSupported` | `Future<bool>` | controller 是否可在没有 `WebViewWidget` 时运行。 |

## `OffscreenWebViewSession`

| API | 作用 |
| --- | --- |
| `create()` | 使用默认参数创建并持有离屏 controller。 |
| `fromPlatformCreationParams(params)` | 使用平台参数创建并持有 controller。 |
| `fromController(controller)` | 接管已有 controller 的所有权。 |
| `controller` | 在关闭开始前返回会话持有的 controller。 |
| `close()` | 可重复调用，并确定性永久释放会话资源。 |

导航：

| 方法 | 返回 |
| --- | --- |
| `currentUrl()` | `Future<String?>` |
| `canGoBack()` | `Future<bool>` |
| `canGoForward()` | `Future<bool>` |
| `goBack()` | `Future<void>` |
| `goForward()` | `Future<void>` |
| `reload()` | `Future<void>` |
| `setNavigationDelegate(delegate)` | `Future<void>` |

JavaScript：

| 方法 | 返回 |
| --- | --- |
| `setJavaScriptMode` | `Future<void>` |
| `runJavaScript` | `Future<void>` |
| `runJavaScriptReturningResult` | `Future<Object>` |
| `callAsyncJavaScript` | `Future<Object?>` |
| `isUserScriptInjectionSupported` | `Future<bool>` |
| `addUserScript` | `Future<String>`，返回不透明脚本标识 |
| `removeUserScript` / `removeAllUserScripts` | `Future<void>` |
| `addJavaScriptChannel(String name, {required void Function(JavaScriptMessage) onMessageReceived})` | `Future<void>` |
| `removeJavaScriptChannel` | `Future<void>` |
| `setOnConsoleMessage` | `Future<void>` |
| `setOnJavaScriptAlertDialog` | `Future<void>` |
| `setOnJavaScriptConfirmDialog` | `Future<void>` |
| `setOnJavaScriptTextInputDialog` | `Future<void>` |

视图状态：

| 方法 | 返回 |
| --- | --- |
| `getTitle()` | `Future<String?>` |
| `scrollTo` / `scrollBy` | `Future<void>` |
| `getScrollPosition()` | `Future<Offset>` |
| `setOnScrollPositionChange` | `Future<void>` |
| `setVerticalScrollBarEnabled` / `setHorizontalScrollBarEnabled` | `Future<void>` |
| `supportsSetScrollBarsEnabled()` | `Future<bool>` |
| `enableZoom` | `Future<void>` |
| `setBackgroundColor` | `Future<void>` |
| `setUserAgent` / `getUserAgent` | `Future<void>` / `Future<String?>` |
| `setOverScrollMode` | `Future<void>` |

## `NavigationDelegate`

| 回调 | 作用 |
| --- | --- |
| `onNavigationRequest` | 允许或阻止导航。 |
| `onPageStarted` | 页面开始加载。 |
| `onPageFinished` | 页面加载完成。 |
| `onProgress` | 加载进度。 |
| `onWebResourceError` | 资源错误。 |
| `onUrlChange` | URL 变化。 |
| `onHttpAuthRequest` | HTTP 鉴权。 |
| `onHttpError` | HTTP 状态错误。 |
| `onSslAuthError` | 可恢复 SSL 证书错误。 |

## `WebViewWidget`

`WebViewWidget` 接收 `WebViewController` 并委托当前平台实现构建 native/Web 视图。

## `WebViewCookieManager`

| 方法 | 返回 | 作用 |
| --- | --- | --- |
| `clearCookies()` | `Future<bool>` | 清空 cookie。 |
| `setCookie(WebViewCookie cookie)` | `Future<void>` | 设置通用 cookie。 |
| `getCookies({required Uri domain})` | `Future<List<WebViewCookie>>` | 获取指定域名可见 cookie。 |

## `WebViewDataManager`

| 方法 | 返回 | 作用 |
| --- | --- | --- |
| `clearAllWebsiteData()` | `Future<WebViewDataClearingResult>` | 无需 controller 即可清理网站数据，并返回已清理、不支持和失败的数据类型。 |

默认构造函数使用当前平台的默认持久化数据区；也可通过 `fromPlatformCreationParams` 或 `fromPlatform` 使用平台参数或已有平台实现。

## 导出的类型

`webview_all.dart` 导出 `OffscreenWebViewSession`、`LoadRequestMethod`、`NavigationDecision`、`NavigationRequest`、`WebResourceError`、`HttpResponseError`、`HttpAuthRequest`、`WebViewCredential`、`JavaScriptMode`、`JavaScriptMessage`、`JavaScriptConsoleMessage`、`JavaScriptExecutionException`、`JavaScriptInvocationParams`、JS dialog request、`ScrollPositionChange`、`WebViewCookie`、`WebViewDataClearingResult`、`WebViewDataType`、`WebViewUserScript`、`WebViewUserScriptInjectionTime`、`WebViewOverScrollMode`、`WebViewPermissionResourceType` 和 `WebViewPlatform` 等类型。

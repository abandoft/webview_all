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
| `WebViewController({onPermissionRequest, mediaPlaybackPolicy})` | 使用通用参数创建 controller。 |
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

### 浏览器操作（1.5.0）

| 方法 | 返回 | 用途 |
| --- | --- | --- |
| `getBrowserCapabilities()` | `Future<WebViewBrowserCapabilities>` | 查询加载、历史、查找、文件选择、媒体和新窗口策略。 |
| `stopLoading()` | `Future<void>` | 停止当前加载。 |
| `getNavigationHistory()` | `Future<WebViewNavigationHistory?>` | 当前前进／后退记录。 |
| `goToHistoryIndex(index)` | `Future<bool>` | 跳到当前历史列表中的索引。 |
| `findText(text, {forward, caseSensitive, wrapAround})` | `Future<WebViewFindResult?>` | 查找并选中匹配文本；重复同一关键词会继续查找。 |
| `clearFindMatches()` | `Future<void>` | 清除查找状态。 |
| `setPopupPolicy(policy)` | `Future<void>` | 设置新窗口策略。 |
| `setFileSelector(callback)` | `Future<void>` | 接管文件选择；传 `null` 恢复默认行为。 |
| `setMediaPlaybackRequiresUserGesture(require)` | `Future<void>` | 动态修改媒体手势要求；Apple 应使用创建参数。 |

Cookie 属性和定向删除见 [Cookie 指南](/webview_all/zh/guides/cookies/)。

## `WebViewSession`（1.4.9）

| API | 用途 |
| --- | --- |
| `getCapabilities()` | 查询会话模式、关闭能力及会话数据管理能力。 |
| `create({mode, mediaPlaybackPolicy, onPermissionRequest})` | 创建会话；不支持或失败时打印原因并返回 `null`，默认 `incognito`，通过 `incognitoSupport` 区分支持程度。 |
| `controller`、`cookieManager`、`dataManager` | 会话页面及所选存储的数据管理器。 |
| `mode`、`capabilities`、`isClosed` | 模式、能力和关闭状态。 |
| `close()` | 可重复关闭，关闭前先移除组件。 |

## `OffscreenWebViewSession`

| API | 作用 |
| --- | --- |
| `create()` | 使用默认参数创建并持有离屏 controller。 |
| `fromPlatformCreationParams(params)` | 使用平台参数创建并持有 controller。 |
| `fromController(controller)` | 接管已有 controller 的所有权。 |
| `controller` | 在关闭开始前返回会话持有的 controller。 |
| `close()` | 可重复调用，并确定性永久释放会话资源。 |

## `NavigationDelegate`

| 回调 | 作用 |
| --- | --- |
| `onNavigationRequest` | 允许或阻止导航。 |
| `onPageStarted` | 页面开始加载。 |
| `onPageFinished` | 页面加载完成。 |
| `onProgress` | 加载进度。 |
| `onWebResourceError` | 资源错误。 |
| `onUrlChange` | URL 变化。 |
| `onTitleChange` | 主文档标题变化；空标题遵循引擎默认行为。 |
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
| `getCapabilities()` | `Future<WebViewCookieCapabilities>` | 可读取的属性及单个 Cookie 删除能力。 |
| `deleteCookie({name, domain, path})` | `Future<bool>` | 按已知身份删除 Cookie。 |

## `WebViewDataManager`

| 方法 | 返回 | 作用 |
| --- | --- | --- |
| `clearAllWebsiteData()` | `Future<WebViewDataClearingResult>` | 无需 controller 即可清理网站数据，并返回已清理、不支持和失败的数据类型。 |

默认构造函数使用当前平台的默认持久化数据区；也可通过 `fromPlatformCreationParams` 或 `fromPlatform` 使用平台参数或已有平台实现。

## 导出的类型

`webview_all.dart` 导出 `WebViewSession`、`WebViewSessionMode`、`WebViewSessionCapabilities`、`WebViewIncognitoSupport`、`OffscreenWebViewSession`、`LoadRequestMethod`、`NavigationDecision`、`NavigationRequest`、`WebResourceError`、`HttpResponseError`、`HttpAuthRequest`、`WebViewCredential`、`JavaScriptMode`、`JavaScriptMessage`、`JavaScriptConsoleMessage`、`JavaScriptExecutionException`、`JavaScriptInvocationParams`、JS dialog request、`ScrollPositionChange`、`WebViewCookie`、`WebViewDataClearingResult`、`WebViewDataType`、`WebViewUserScript`、`WebViewUserScriptInjectionTime`、`WebViewOverScrollMode`、`WebViewPermissionResourceType` 和 `WebViewPlatform` 等类型。

## JavaScript 能力与处理器（1.5.x）

| API | 用途 |
| --- | --- |
| `getJavaScriptCapabilities(world: ...)` | 查询注入时机、执行环境、来源信息及内容限制。 |
| `tryAddUserScript(...)` | 注册可选的 document-start/end 脚本；不支持时打印说明并返回 null。 |
| `addJavaScriptHandler(...)` | 注册支持异步回值及显式来源策略的 Dart 回调。 |
| `removeJavaScriptHandler(...)` / `removeAllJavaScriptHandlers()` | 移除处理器并取消未完成调用。 |
| `callAsyncJavaScript(..., world: ...)` | 在支持的页面或独立环境中执行代码。 |

用法及平台限制见 [JavaScript](/webview_all/zh/guides/javascript/)。


## 网页导出和原生子窗口

`WebViewController`: `takeScreenshot`, `createPdf`, `setNewWindowDelegate`,
`setOnWindowCloseRequested`, `setFullscreenDelegate`, `exitFullscreen`,
`setOnProcessFailed`. `WebViewDataManager`: `getCapabilities`,
`clearWebsiteData(dataTypes: ...)`.

`WebViewNewWindowRequest.createController()` 创建与请求匹配的子 controller。

## 1.5.x：Profile、网络与页面工具

| API | 用途 |
| --- | --- |
| `WebViewProfile.create`, `createSession`, `close`, `whenReleased` | 管理关联会话共享的命名或私密存储。 |
| `WebViewProfileManager.getCapabilities`, `listProfiles`, `requestDeletion` | 列出插件创建的命名持久 Profile，并按原生占用状态请求删除。 |
| `saveNavigationState`, `restoreNavigationState`, `clearNavigationHistory` | 管理仅存在于内存的原生历史状态及清理。 |
| `takeScreenshot(options: WebViewScreenshotOptions(...))` | 原图像素区域、输出缩放及 Windows／Linux 原生整页截图。 |
| `createPdf(options: WebViewPdfOptions(...))` | 以点为单位的纸张、边距及方向。 |
| `createArchive(format: ...)` | 原生 MHTML 或 WebArchive 字节。 |
| `printPage`, `WebViewPrintJob` | 系统打印界面及可用的任务状态和取消。 |
| `getWebsiteDataRecords`, `clearWebsiteDataFor` | 通过数据管理器明确指定 origin、domain 或 site。 |
| `getNetworkCapabilities`, `setContentRules` | 原生内容规则、受支持的动作与条件及运行时能力。 |
| `setRequestDelegate`, `setCustomSchemeDelegate` | HTTP 决策及创建时声明的自定义协议。 |
| `setContextMenuEnabled`, `setAudioMuted`, `pauseMedia`, `setMediaPlaybackSuspended` | 可用的原生菜单和媒体控制。 |

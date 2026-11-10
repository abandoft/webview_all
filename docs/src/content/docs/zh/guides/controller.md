---
title: Controller
description: 加载内容、导航、执行 JavaScript、控制滚动和 WebView 状态。
---

`WebViewController` 是核心控制对象。一个 controller 同一时间只能绑定到一个 `WebViewWidget`，具体操作会委托给当前平台实现。在支持离屏运行的平台上，不创建组件也可以加载内容、接收导航回调、执行 JavaScript 和使用 channel。

## 创建

通用创建：

```dart
final controller = WebViewController();
```

需要平台创建参数时：

```dart
PlatformWebViewControllerCreationParams params =
    const PlatformWebViewControllerCreationParams();

if (WebViewPlatform.instance is LinuxWebViewPlatform) {
  params = const LinuxWebViewControllerCreationParams(
    developerExtrasEnabled: true,
    pageCacheEnabled: true,
  );
}

final controller = WebViewController.fromPlatformCreationParams(params);
```

已有平台 controller 时：

```dart
final platformController = WindowsWebViewController(
  const WindowsWebViewControllerCreationParams(
    popupWindowPolicy: WindowsPopupWindowPolicy.sameWindow,
  ),
);

final controller = WebViewController.fromPlatform(platformController);
```

## 原生离屏使用

不需要显示页面时，使用独立的所有权会话：

```dart
import 'dart:async';

final session = await OffscreenWebViewSession.create();
final controller = session.controller;
final loaded = Completer<void>();

try {
  await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
  await controller.setNavigationDelegate(
    NavigationDelegate(onPageFinished: (_) => loaded.complete()),
  );
  await controller.loadHtmlString('<script>window.price = 42;</script>');
  await loaded.future;

  final price = await controller.callAsyncJavaScript('return window.price;');
} finally {
  await session.close();
}
```

OHOS 和 Web 调用 `OffscreenWebViewSession.create` 会抛出 `UnsupportedError`。Android、iOS、macOS、Windows 和 Linux 可以不创建组件运行，会话关闭前仍可把其 controller 交给组件显示。`close()` 可重复调用，并会确定性释放会话资源，同时不向公共 controller 增加 `dispose()`。

离屏运行仍依赖当前应用的 Flutter engine、平台线程、窗口和进程生命周期，并不是后台服务或独立 isolate，也不能绕过系统后台限制。`close()` 开始后不得继续持有或使用其 controller。

## 加载内容

| 方法 | 用途 | 说明 |
| --- | --- | --- |
| `loadRequest` | 加载 URL 或提交请求 | URI 必须有 scheme。 |
| `loadFile` | 加载设备本地文件 | Web 平台不支持。 |
| `loadFlutterAsset` | 加载 Flutter asset | Web 会解析到 `assets/<key>`。 |
| `loadHtmlString` | 加载内存 HTML | `baseUrl` 用于相对路径。 |

## 请求限制

| 平台 | GET headers | POST body | POST 自定义 headers |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 不支持，Android `postUrl` 不接收 headers。 |
| iOS/macOS | 支持 | 支持 | 支持。 |
| Windows | 支持 | 支持 | 支持。 |
| Linux | 支持 | 支持 | 支持。 |
| OHOS | 支持 | 支持 | 不支持，ArkWeb `postUrl` 不接收 headers。 |
| Web | fetch 支持 | fetch 支持 | 受 CORS 预检和响应头限制。 |

## 导航状态

```dart
final url = await controller.currentUrl();
final title = await controller.getTitle();

if (await controller.canGoBack()) {
  await controller.goBack();
}

await controller.reload();
```

Web 平台会为 controller 发起的加载维护逻辑历史。

## JavaScript 和 Channel

```dart
await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
await controller.runJavaScript('document.body.dataset.ready = "true";');

final result = await controller.runJavaScriptReturningResult('1 + 2');

await controller.addJavaScriptChannel(
  'Host',
  onMessageReceived: (JavaScriptMessage message) {
    debugPrint(message.message);
  },
);
```

`runJavaScriptReturningResult` 会拒绝 `null` 和 `undefined`。Web 平台可直接
控制同源内容，并通过消息桥控制插件管理的隔离 HTML；直接跨域 iframe URL
仍不可访问。

## 滚动和外观

```dart
await controller.scrollTo(0, 0);
final position = await controller.getScrollPosition();

await controller.setOnScrollPositionChange((change) {
  debugPrint('${change.x}, ${change.y}');
});
```

滚动条可见性应先检查：

```dart
if (await controller.supportsSetScrollBarsEnabled()) {
  await controller.setVerticalScrollBarEnabled(false);
}
```

其他常用方法：

| 方法 | 作用 |
| --- | --- |
| `setBackgroundColor` | 设置背景色；macOS 12+ 使用原生 API，更早版本打印说明并安全忽略。 |
| `enableZoom` | 控制缩放能力；macOS 使用原生 magnification。 |
| `setUserAgent` / `getUserAgent` | 设置和读取 UA；Web 对非空 override 打印一次说明并忽略。 |
| `setOverScrollMode` | 控制 overscroll；macOS 因没有公开 API 而打印说明并安全忽略，部分平台通过 CSS 注入实现。 |

## 访问平台实现

```dart
switch (controller.platform) {
  case WindowsWebViewController windows:
    await windows.openDevTools();
  case LinuxWebViewController linux:
    await linux.setDeveloperExtrasEnabled(true);
  case OhosWebViewController ohos:
    await ohos.setTextZoom(110);
  case WebWebViewController web:
    await web.setIFrameReferrerPolicy('no-referrer');
}
```


## 无痕会话（1.4.9）

使用 `WebViewSession` 在创建页面前选择数据存储，并管理该页面的生命周期：

```dart
final capabilities = await WebViewSession.getCapabilities();
final session = await WebViewSession.create(
  mode: WebViewSessionMode.incognito,
);
if (session == null) return; // 已打印平台限制或创建失败的原因。

final controller = session.controller;
await session.cookieManager.setCookie(
  const WebViewCookie(name: 'account', value: 'temporary', domain: 'example.com'),
);
// 可把 controller 交给 WebViewWidget。移除组件后关闭会话。
await session.close();
```

`shared` 使用普通共享存储；`incognito`（默认）使用平台提供的无痕处理，能力等级由 `incognitoSupport` 区分；
`isolatedIncognito` 要求独立的原生临时存储。模式在创建时确定，不能动态切换。
`create()` 不支持所请求的模式或创建失败时会打印具体原因并返回 `null`，应用可以继续运行。
它不会自动降级为普通会话，也不会通过清空共享 Cookie 模拟无痕。

| 平台 | 无痕能力 |
| --- | --- |
| iOS / macOS、Linux | 支持独立的临时数据存储。 |
| Windows | WebView2 Runtime 支持 InPrivate 创建选项时可用，每个会话使用独立 Profile。 |
| OHOS | 支持 `incognito`；原生无痕页面共享一组临时数据，不支持 `isolatedIncognito`。 |
| Android | 有限无痕：禁用缓存使用和可用的表单保存，清理当前页面的历史。Cookie、网站存储仍共享且可能持久化。 |
| Web | 浏览器未向 iframe 开放独立无痕存储。 |

`session.cookieManager` 和 `session.dataManager` 操作该会话所选的存储。
Android 的有限无痕管理器也操作普通共享数据，开启和关闭时不会自动清空共享 Cookie。
默认管理器操作普通数据，但 OHOS 的缓存清理仍是全局操作；OHOS 无痕数据清理会影响其他原生无痕页面，
不会清理普通页面。OHOS 会话管理器的缓存清理因只有全局接口而报告不支持。各数据类别的结果以
`WebViewDataClearingResult` 为准。Web 不支持会话数据管理时会打印提示并返回空结果或不支持的类别。

关闭会话前先从组件树移除其 `WebViewWidget`；`close()` 可重复调用，关闭后不能复用 controller 或会话管理器。
`WebViewSession` 与 `OffscreenWebViewSession` 的职责不同：后者管理离屏 controller 的释放，默认使用普通存储。
无痕模式也不保证不产生任何系统临时文件，不会隐藏网络身份或清除应用自行保存的数据。

## 加载控制、历史记录和查找

```dart
await controller.stopLoading();
final capabilities = await controller.getBrowserCapabilities();
final history = await controller.getNavigationHistory();
if (history != null && history.currentIndex > 0) {
  await controller.goToHistoryIndex(history.currentIndex - 1);
}

if (capabilities.findText) {
  final result = await controller.findText('关键词');
  debugPrint('找到：${result?.matchFound}，数量：${result?.matchCount}');
  await controller.findText('关键词'); // 同一关键词再次查找会跳到下一项。
  await controller.findText('关键词', forward: false);
  await controller.clearFindMatches();
}
```

历史列表是当前 WebView 的前进／后退记录，索引从零开始；导航后应重新查询。
原生端使用引擎历史跳转，Web 只包含 controller 管理的加载，无法完整读取跨域
iframe 或网页内部的历史。`goToHistoryIndex` 返回是否接受跳转，不代表页面已加载完成。

Apple 和 Web 不提供匹配总数，缺失的数量或位置为 `null`。Android、OHOS 的查找
仅支持忽略大小写并循环；Windows 查找需运行时支持，也仅支持循环。
`findCaseSensitive`、`findWithoutWrapping` 可用于查询这些选项。
Web 查找及停止 iframe 本身的加载需要同源或插件可控制的 HTML；插件发起的
fetch 加载可取消。跨域 iframe 的加载仍由浏览器控制。

不支持的新增操作会打印说明并返回 `null`、`false` 或直接忽略，不中断应用。


## 网页截图与 PDF

```dart
final capabilities = await controller.getBrowserCapabilities();
if (capabilities.viewportScreenshot) {
  final png = await controller.takeScreenshot();
  // 由应用保存或显示 PNG 字节。
}
if (capabilities.pdfExport) {
  final pdf = await controller.createPdf();
  // 由应用保存 PDF 字节。
}
```

截图捕获布局稳定后的网页可见区域，不包含 Flutter 覆盖组件；受保护的视频等内容
可能无法捕获。Android、iOS、macOS、Windows、Linux、OHOS 支持截图；iOS、macOS、
Windows、Linux、OHOS 支持 PDF。可通过选项配置截图区域与缩放、PDF 纸张与边距，分页仍受引擎限制。
Linux 需要 GTK 的“打印到文件”后端。Android 的系统打印流程不能用于直接返回
PDF 字节；Web 暂不提供这两项导出能力。不支持、导出失败或页面关闭时，
接口打印说明并返回 `null`。导出会串行执行，并限制单次输出大小。

## 原生子窗口接管

```dart
await controller.setNewWindowDelegate((request) async {
  final child = await request.createController();
  if (child == null) return;
  var attached = false;
  try {
    await child.setJavaScriptMode(JavaScriptMode.unrestricted);
    await child.setNavigationDelegate(NavigationDelegate());
    attached = await request.attach(child);
    if (attached) {
      // 在新标签页或路由中显示 WebViewWidget(controller: child)。
    }
  } finally {
    if (!attached) await child.platform.closeWebViewSession();
  }
});
```

Android、iOS、macOS、Windows、Linux 的普通和私密会话可接管原生子窗口，保留表单
POST 和 `window.opener`。统一使用 `request.createController()` 创建匹配的
子页面，接管前只配置设置、回调和用户脚本，不主动加载页面。Apple、Linux
必须使用这个工厂；普通新建的
controller 不具备原生请求要求的关联配置。重复调用工厂返回同一 controller。

应用负责子窗口界面和释放。可用 `setOnWindowCloseRequested` 接收网页的关闭
请求，移除组件后调用 `child.platform.closeWebViewSession()`；请求超时或接管
失败时，应用也仍拥有工厂返回的 controller。

Android 不提供 `request.url`，POST 导航也可能不经过导航决策回调。只应对可信
opener 启用委托；opener 可能在 Dart 收到通知前写入子窗口的初始空白文档。

委托须在 20 秒内完成，返回时没有接管则拒绝请求。`deny` 策略始终优先；传入
`null` 移除委托后恢复已有策略。OHOS、Web 暂不支持原生子窗口接管，会打印说明并保留既有策略。Android 的有限无痕模式
仍共享普通网站数据。`sameView` 仅在当前页面加载 URL，不保证 opener 或 POST。

## 全屏与渲染进程异常

```dart
await controller.setFullscreenDelegate(WebViewFullscreenDelegate(
  onEnter: (request) {
    // request.content 非空时显示该组件；否则调整当前 WebView 的布局。
    // 保存 request，需要退出时调用 await request.exit()。
  },
  onExit: () {
    // 移除全屏组件并恢复应用布局。
  },
));
await controller.setOnProcessFailed((failure) {
  // 按 failure.recovery 选择重新加载、重建 controller，或保留页面等待。
});
```

用 `getBrowserCapabilities()` 查询 `fullscreenEvents`、
`fullscreenCustomContent` 和 `processFailureEvents`。应用负责路由、系统栏和
屏幕方向；插件不在委托中更改这些应用设置。Android 全屏可能提供单独的组件，
其他平台继续使用原 WebView 或系统媒体界面。Apple 全屏通知需要 iOS 16 / macOS 13；
系统视频界面仍由系统管理，DOM 退出接口可能不适用。Web 只能观察当前 iframe 的
浏览器全屏状态，仍受 iframe 权限和用户手势限制，不会退出其他元素的全屏。
替换或移除委托时会先请求退出原展示，并结束原回调。

`exitFullscreen()` 和 `request.exit()` 的 `true` 表示已发出退出请求。
`onExit` 用于清理本次展示，原生退出、委托替换/移除或 controller 释放时都会通知。
没有安装委托时保留原有平台行为。

Android 8 及以上、Apple、Windows、Linux、OHOS 可通知渲染进程异常；Web 不暴露
对应事件。Android 渲染进程退出后必须重建 controller；Apple、Linux、OHOS 和
Windows 主渲染进程退出后可重新加载，Windows 浏览器进程退出则需重建。
插件取消失效的脚本调用和全屏展示，不会自动重载或重发 POST。其他辅助进程的
异常不一定影响主页面，`recovery: none` 表示插件未要求重载。
不支持的平台打印说明并保留原有行为。

命名存储、导航状态、打印、归档和精细清理见 [Profile 与页面工具](/webview_all/zh/guides/profiles-and-tools/)，请求代理和自定义协议见 [网络控制](/webview_all/zh/guides/network/)。

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

---
title: Controller
description: 加载内容、导航、执行 JavaScript、控制滚动和 WebView 状态。
---

`WebViewController` 是核心控制对象。一个 controller 同一时间只能绑定到一个 `WebViewWidget`，具体操作会委托给当前平台实现。

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

`runJavaScriptReturningResult` 会拒绝 `null` 和 `undefined`。Web 平台要求同源 iframe 内容。

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
| `setBackgroundColor` | 设置背景色；macOS 上会被忽略并在终端打印日志。 |
| `enableZoom` | 控制缩放能力。 |
| `setUserAgent` / `getUserAgent` | 设置和读取 UA；Web 不支持非空 UA override。 |
| `setOverScrollMode` | 控制 overscroll；部分平台通过 CSS 注入实现。 |

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

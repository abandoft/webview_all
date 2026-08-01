---
title: JavaScript
description: 执行 JavaScript、接收消息、处理对话框和 console。
---

JavaScript 能力包括执行脚本、返回值、channel、console 和浏览器对话框。

## 开关 JavaScript

```dart
await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
await controller.setJavaScriptMode(JavaScriptMode.disabled);
```

Web 平台禁用 JavaScript 时会应用更严格的 iframe sandbox。

## 执行脚本

```dart
await controller.runJavaScript('document.body.classList.add("ready")');

final value = await controller.runJavaScriptReturningResult('1 + 2');
```

返回值说明：

| 平台 | 行为 |
| --- | --- |
| Android | 使用 Android WebView evaluate。 |
| iOS/macOS | 使用 WebKit evaluate，不能桥接的值会失败。 |
| Windows | 使用 WebView2 script execution。 |
| Linux | 使用 WebKitGTK，并按需要解码 JSON。 |
| OHOS | 使用 ArkWeb `evaluateJavascript`。 |
| Web | 同源内容直接 `eval`，插件管理的隔离 HTML 走来源校验消息桥；结果需可 JSON 序列化。 |

## JavaScript Channel

```dart
await controller.addJavaScriptChannel(
  'Checkout',
  onMessageReceived: (JavaScriptMessage message) {
    debugPrint('Checkout event: ${message.message}');
  },
);
```

页面侧：

```js
Checkout.postMessage(JSON.stringify({ type: 'loaded' }));
```

不再需要时移除：

```dart
await controller.removeJavaScriptChannel('Checkout');
```

## Console

```dart
await controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
  debugPrint('[${message.level.name}] ${message.message}');
});
```

所有 native 平台都支持 console 回调；Web 的同源内容和插件管理的隔离 HTML
均可安装 hook。

## JavaScript 对话框

```dart
await controller.setOnJavaScriptAlertDialog((request) async {});

await controller.setOnJavaScriptConfirmDialog((request) async {
  return true;
});

await controller.setOnJavaScriptTextInputDialog((request) async {
  return request.defaultText ?? '';
});
```

| 平台 | `alert` | `confirm` | `prompt` |
| --- | --- | --- | --- |
| Android | 支持 | 支持 | 支持 |
| iOS/macOS | 支持 | 支持 | 支持 |
| Windows | 支持 | 支持 | 支持 |
| Linux | 支持 | 支持 | 支持 |
| OHOS | 支持 | 支持 | 支持 |
| Web | 同源或插件管理的隔离 HTML | 同源回调；隔离 HTML 保留浏览器对话框 | 同源回调；隔离 HTML 保留浏览器对话框 |

Web 的 `confirm` 和 `prompt` 是浏览器同步 API；同源内容如需确定结果，回调应
返回 `SynchronousFuture`：

```dart
await controller.setOnJavaScriptConfirmDialog((request) {
  return SynchronousFuture<bool>(true);
});
```

直接跨域 iframe URL 仍不可控制。隔离 HTML 无法通过异步跨 frame 通信返回同步
对话框结果，因此保留浏览器原生 `confirm` 和 `prompt`。

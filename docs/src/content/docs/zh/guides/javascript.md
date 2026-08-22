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

## 等待 Promise

脚本会返回 Promise，或需要传递结构化命名参数时，使用 `callAsyncJavaScript`：

```dart
final result = await controller.callAsyncJavaScript(
  '''
  const response = await fetch(endpoint);
  return {status: response.status, body: await response.text()};
  ''',
  arguments: <String, Object?>{
    'endpoint': 'https://example.com/api',
  },
  timeout: const Duration(seconds: 15),
);
```

参数名必须是合法且非保留的 JavaScript identifier；参数值会被复制，只接受有限数值、字符串、布尔值、null、list 和字符串 key 的 map。Promise 的成功结果必须能转换为 JSON；脚本抛错或 Promise reject 会产生 `JavaScriptExecutionException`，超时会产生 `TimeoutException`。

Android、iOS、macOS、Windows、Linux 和 OHOS 支持该接口。Web 支持同源内容和插件管理的隔离 HTML，直接跨域 iframe 仍不可访问。

## Document-start 用户脚本

需要在页面脚本之前提供 provider 或兼容层时，应先注册脚本再加载页面：

```dart
if (await controller.isUserScriptInjectionSupported(
  WebViewUserScriptInjectionTime.documentStart,
)) {
  final scriptId = await controller.addUserScript(
    const WebViewUserScript(
      source: 'globalThis.appProvider = Object.freeze({version: 1});',
      forMainFrameOnly: true,
    ),
  );

  await controller.loadRequest(Uri.parse('https://example.com'));
  // 后续可调用：await controller.removeUserScript(scriptId);
}
```

必须等待 `addUserScript` 完成后再开始导航。所有受支持平台都在一致的私有函数作用域内执行脚本；需要让页面或其他用户脚本访问的值，必须显式写入 `globalThis`。该词法作用域并不是浏览器单独的 content world。脚本会应用于后续文档和 reload，不会补注入当前文档。`removeAllUserScripts` 只移除通过该接口注册的脚本，不会破坏插件内部的 channel 和 hook。

| 平台 | Document-start 支持情况 |
| --- | --- |
| Android | 取决于系统 Android WebView 是否提供 `DOCUMENT_START_SCRIPT`，必须在运行时检查。 |
| iOS/macOS | 通过 `WKUserScript` 支持。 |
| Windows | 通过 WebView2 支持。 |
| Linux | 通过 WebKitGTK 支持。 |
| OHOS | 当前 ArkWeb bridge 未提供，能力检查返回 false。 |
| Web | iframe API 无法保证早于页面脚本执行，能力检查返回 false。 |

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

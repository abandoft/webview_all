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
| OHOS | 通过 ArkWeb 支持；按注册顺序执行，可在组件挂载前注册。 |
| Web | iframe API 无法保证早于页面脚本执行，能力检查返回 false。 |

## Document-end 与独立执行环境

使用 `tryAddUserScript` 注册可选脚本；不支持时打印说明并返回 `null`：

```dart
const world = WebViewJavaScriptWorld.isolated('app');
final scriptId = await controller.tryAddUserScript(
  const WebViewUserScript(
    source: 'globalThis.appReady = document.body != null;',
    injectionTime: WebViewUserScriptInjectionTime.documentEnd,
    world: world,
  ),
);
```

`documentEnd` 在 DOM 就绪阶段执行，无须等待图片等资源加载完成；相对于网页 `DOMContentLoaded` 监听器的先后顺序可能因内核而异。Windows 和部分旧 Android WebView 通过提前注册 DOM 就绪监听实现。Web 仅支持插件加载的 HTML，普通 URL 加载无法保证这一注入时机。

Android（取决于实际 WebView 内核）、iOS、macOS 和 Linux 支持命名的独立执行环境。不同环境的 JavaScript 全局变量分离，仍共享 DOM、Cookie 和网站存储。Windows、OHOS、Web 的独立环境操作会打印说明并跳过。Android 需要在加载文档前注册独立环境。

向 `callAsyncJavaScript` 传入相同的 `world` 可在该环境中执行代码。不支持时打印说明并返回 `null`，不会改为在页面环境执行。现有 `addUserScript` 保留严格的失败行为，可选能力使用 `tryAddUserScript`。

## 支持返回值的 JavaScript 调用

在用户脚本和页面加载之前注册处理器：

```dart
final registered = await controller.addJavaScriptHandler(
  'appInfo',
  accessPolicy: WebViewJavaScriptAccessPolicy.origins(
    {'https://app.example.com'},
    mainFrameOnly: true,
  ),
  onCall: (call) async => {'name': 'Example', 'arguments': call.arguments},
);
```

页面侧可以等待 Dart 的异步返回值：

```js
async function callApp() {
  await window.webviewAll.ready;
  return await window.webviewAll.callHandler('appInfo', {language: 'zh'});
}
if (window.webviewAll) {
  callApp().catch(console.warn);
} else {
  window.addEventListener('webviewAllReady', () => callApp().catch(console.warn), {once: true});
}
```

参数和结果只接受 JSON 兼容值。请求和返回值的 UTF-8 JSON 大小上限为 1 MiB，每个 controller 最多有 128 个未完成调用。

处理器异常、结果无法序列化、移除处理器或超时，会使 Promise reject，并提供 `handler_error`、`serialization_error`、`aborted`、`timeout` 等错误码。默认超时 30 秒，最多可设为 5 分钟；不会向网页暴露 Dart 异常的内部细节。

来源策略按原生提供的安全 origin 匹配 HTTP(S) 的协议、主机和端口，拒绝未知或不透明 origin。Windows、OHOS 无法执行这类来源策略；Linux 独立环境的处理器也缺少可靠的来源与帧信息。无法执行策略时，注册返回 `false` 并打印原因。对于自行控制的内容，可显式使用 `const WebViewJavaScriptAccessPolicy.unrestricted()`；插件不会自动放宽受限策略。

Promise 处理器目前只在主文档中运行。Web 支持同源页面和插件可控制的 HTML，任意跨域 URL 无法注入。使用 `getJavaScriptCapabilities(world: world)` 查询时机、独立环境、来源信息及内容限制；处理器通过可选 `world` 参数选择执行环境。

使用 `removeJavaScriptHandler(name, world: world)` 或 `removeAllJavaScriptHandlers()` 移除处理器。页面跳转和销毁会取消未完成调用，迟到结果不会进入新文档；`pushState` 等同文档地址变化不影响调用。回调可等待 `call.cancelled` 停止自己的工作，已经发生的 Dart 副作用不会自动撤销。清空用户脚本会保留内部 Promise 桥及现有字符串通道。

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

`JavaScriptMessage` 将发送文档 URL（`sourceUrl`）、浏览器安全 origin（`sourceOrigin`）与主框架标记（`isMainFrame`）分开提供。各字段独立可空，表示平台无法可靠确定；`sourceOrigin` 的字符串 `"null"` 表示不透明 origin，与 Dart `null` 不同。

| 平台 | sourceUrl | sourceOrigin | isMainFrame |
| --- | --- | --- | --- |
| Android | — | 支持时提供 | 支持时提供 |
| iOS / macOS | 提供 | 提供 | 提供 |
| Windows | 提供 | — | true（仅主文档） |
| Linux | 提供 | 提供 | 提供 |
| OHOS | 提供 | — | — |
| Web | — | 提供 | true（仅 WebView 内的主文档） |

Android 根据 WebView 的消息监听和文档开始脚本能力选择实现；旧 WebView 保持消息可用，来源字段为空。Linux 使用隔离脚本读取发送文档的信息，`pushState` 后的消息会反映新 URL；隔离桥尚未就绪或直接调用底层消息处理器时，消息仍会送达，但来源字段为空。OHOS 在原生代理调用入口捕获文档 URL，无法可靠确定安全 origin 或框架归属。

敏感操作应拒绝来源未知的消息。不要用 `controller.currentUrl()` 补齐缺失字段，也不要从 `sourceUrl` 推导安全 origin：sandbox 文档即使有 HTTPS URL，也可能具有不透明 origin。以下示例只接受指定安全 origin 的主文档消息；缺少可靠来源的平台会拒绝这些消息：

```dart
await controller.addJavaScriptChannel(
  'Checkout',
  onMessageReceived: (JavaScriptMessage message) {
    if (message.isMainFrame != true ||
        message.sourceOrigin != 'https://shop.example.com') {
      return;
    }
    debugPrint('Accepted checkout event: ${message.message}');
  },
);
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

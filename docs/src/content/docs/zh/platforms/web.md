---
title: Web
description: 浏览器 iframe 实现、iframe 属性、fetch 请求和安全限制。
---

Web 由 `webview_all_web 1.3.1` 提供，底层是 HTML `iframe`。

| 项 | 值 |
| --- | --- |
| Controller | `WebWebViewController` |
| Widget | `WebWebViewWidget` |
| Delegate | `WebNavigationDelegate` |
| Cookie manager | `WebWebViewCookieManager` |
| 引擎 | 浏览器 iframe + Dart JS interop |

## 创建参数

```dart
final params = WebWebViewControllerCreationParams(
  iFrameAllow: 'camera; microphone; fullscreen',
  iFrameSandbox: 'allow-scripts allow-forms',
  iFrameReferrerPolicy: 'strict-origin-when-cross-origin',
  iFrameAttributes: const <String, String?>{
    'loading': 'lazy',
  },
);
```

## 主要 API

| API | 作用 |
| --- | --- |
| `setIFrameAttribute` | 设置或移除任意 iframe 属性。 |
| `setIFrameAllow` | 设置 `allow`。 |
| `setIFrameSandbox` | 设置 `sandbox`。 |
| `setIFrameReferrerPolicy` | 设置 `referrerpolicy`。 |

## 加载模型

简单 GET 会直接设置 iframe `src`：

```dart
await controller.loadRequest(Uri.parse('https://example.com'));
```

带 method、headers 或 body 的请求会使用浏览器 `fetch`，再把响应渲染为 `data:` URL：

```dart
await controller.loadRequest(
  Uri.parse('https://api.example.com/page'),
  headers: const <String, String>{'X-App': 'demo'},
);
```

跨域 fetch 需要服务端 CORS 允许。
响应会按 `Content-Type` 声明的 charset 解码，支持带引号和扩展参数的
header；实现还会注入 `<base>` 来保持相对 URL 的解析语义。

## 可控制内容

以下能力可通过直接同源访问或插件注入到隔离 HTML 中的消息桥实现：

- `runJavaScript`
- `runJavaScriptReturningResult`
- JavaScript channel
- console hook
- JavaScript dialog hook
- 滚动读写
- 读取标题

这覆盖同源 URL、普通 `loadHtmlString`、fetch-backed HTML，以及使用严格
sandbox（包含 `allow-scripts`、不包含 `allow-same-origin`）的
`loadHtmlString`。fetch-backed HTML 始终保留在不透明 `data:` origin 中，
不会获得宿主应用的 origin。

直接加载的跨域 URL 仍由浏览器接管，控制器不能绕过同源策略。fetch-backed
非 HTML 内容也不会注入 JavaScript bridge。

## 不支持或受限

| API | 行为 |
| --- | --- |
| `loadFile` | 抛 `UnsupportedError`。 |
| `setUserAgent(nonNull)` | 打印一次说明并忽略；浏览器不允许 iframe 覆盖网络 UA。 |
| SSL auth | 浏览器不暴露可恢复证书决策。 |
| HTTP auth | iframe 没有 WebView 风格回调。 |
| 跨域 JS | 浏览器同源策略禁止。 |

可控制 HTML 的 camera/microphone 请求可以转发到
`onPermissionRequest`，但最终系统提示仍由浏览器决定。自定义 `confirm`
和 `prompt` 回调只适用于可同步访问的同源内容；隔离 HTML 会保留浏览器原生
对话框，避免用异步跨 frame 通信伪造同步结果。

---
title: Web
description: 浏览器 iframe 实现、iframe 属性、fetch 请求和安全限制。
---

Web 由 `webview_all_web 1.2.1` 提供，底层是 HTML `iframe`。

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
  iFrameSandbox: 'allow-same-origin allow-scripts allow-forms',
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

## 同源限制

以下能力需要同源 iframe：

- `runJavaScript`
- `runJavaScriptReturningResult`
- JavaScript channel
- console hook
- JavaScript dialog hook
- 滚动读写
- 读取标题

## 不支持或受限

| API | 行为 |
| --- | --- |
| `loadFile` | 抛 `UnsupportedError`。 |
| `setUserAgent(nonNull)` | 抛 `UnsupportedError`。 |
| SSL auth | 浏览器不暴露可恢复证书决策。 |
| HTTP auth | iframe 没有 WebView 风格回调。 |
| 跨域 JS | 浏览器同源策略禁止。 |

---
title: 导航
description: 处理页面事件、URL 变化、HTTP 错误、鉴权和证书错误。
---

`NavigationDelegate` 通过 `WebViewController.setNavigationDelegate` 安装到平台实现。

```dart
await controller.setNavigationDelegate(
  NavigationDelegate(
    onNavigationRequest: (request) {
      if (request.url.startsWith('myapp://')) {
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    },
    onPageStarted: (url) {},
    onProgress: (progress) {},
    onPageFinished: (url) {},
    onUrlChange: (change) {},
    onWebResourceError: (error) {},
    onHttpError: (error) {},
    onHttpAuthRequest: (request) {},
    onSslAuthError: (error) {},
  ),
);
```

## 拦截导航

```dart
onNavigationRequest: (NavigationRequest request) {
  final uri = Uri.tryParse(request.url);
  if (uri == null) return NavigationDecision.prevent;
  return uri.host.endsWith('example.com')
      ? NavigationDecision.navigate
      : NavigationDecision.prevent;
}
```

部分平台也会对 controller 主动发起的加载触发该回调，因此可以把它作为统一导航策略。

## 页面生命周期

| 回调 | 含义 |
| --- | --- |
| `onPageStarted` | 主 frame 开始加载。 |
| `onProgress` | 加载进度，通常为 0 到 100。 |
| `onPageFinished` | 主 frame 完成加载。 |
| `onUrlChange` | 可见 URL 或逻辑 URL 变化。 |

Web 平台对 `loadHtmlString` 和 fetch-backed 请求报告逻辑 URL，因为内部可能使用 `srcdoc` 或 `data:` URL。

## 错误和 HTTP 状态

`onWebResourceError` 用于网络、文件、TLS、策略和引擎错误：

```dart
onWebResourceError: (WebResourceError error) {
  debugPrint('${error.errorType}: ${error.description}');
}
```

`onHttpError` 用于 HTTP 状态码大于等于 400 的响应：

```dart
onHttpError: (HttpResponseError error) {
  final status = error.response?.statusCode;
  final headers = error.response?.headers;
}
```

Web 平台只有 fetch-backed 加载能拿到 HTTP 响应信息；普通跨域 iframe 导航由浏览器接管。

## HTTP 鉴权

```dart
onHttpAuthRequest: (HttpAuthRequest request) {
  request.onProceed(
    const WebViewCredential(user: 'demo', password: 'secret'),
  );
}
```

不继续时调用 `request.onCancel()`。不要重复响应同一个请求。

## SSL 证书错误

```dart
onSslAuthError: (SslAuthError error) async {
  debugPrint(error.platform.description);
  await error.cancel();
}
```

生产环境默认应取消。`proceed()` 只适合受控测试环境。

Web 平台无法暴露可恢复 TLS 决策，浏览器 iframe API 不允许嵌入页面接管证书错误。

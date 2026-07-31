---
title: 安全
description: 生产环境中的导航策略、JavaScript、Cookie、TLS 和权限建议。
---

WebView 会在应用内执行远程内容，应作为高风险集成点处理。

## 导航策略

```dart
NavigationDelegate(
  onNavigationRequest: (NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;

    const allowedHosts = {'example.com', 'accounts.example.com'};
    return allowedHosts.contains(uri.host)
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  },
);
```

对 `myapp://` 这类自定义 scheme，应交给应用路由处理并阻止 WebView 继续导航。

## JavaScript Channel

JavaScript channel 是页面到应用的桥。所有消息都要验证：

```dart
await controller.addJavaScriptChannel(
  'AppBridge',
  onMessageReceived: (JavaScriptMessage message) {
    final decoded = jsonDecode(message.message);
    if (decoded is! Map<String, Object?>) return;
    if (decoded['type'] != 'expected-event') return;
  },
);
```

不要直接向页面暴露 token、文件路径或高权限命令。

## TLS

生产环境默认取消证书错误：

```dart
onSslAuthError: (SslAuthError error) async {
  await error.cancel();
}
```

`proceed()` 只应在受控测试环境使用。

## Cookie

认证 cookie 优先由服务端设置 `Secure`、`HttpOnly`、`SameSite`。客户端 `WebViewCookieManager` 并不能在所有平台设置所有属性。Windows 虽有 `WindowsWebViewCookie` 扩展元数据，但服务端 cookie 仍是更稳妥的来源。

## Mixed Content

Android 上建议显式禁止 mixed content：

```dart
await (controller.platform as AndroidWebViewController)
    .setMixedContentMode(MixedContentMode.neverAllow);
```

其他平台应优先只加载 HTTPS，并通过 `onNavigationRequest` 限制未知 host。

## 文件访问

不需要时关闭 file access：

```dart
await (controller.platform as AndroidWebViewController)
    .setAllowFileAccess(false);

await (controller.platform as OhosWebViewController)
    .setAllowFileAccess(false);
```

Linux 上不要对不可信本地文件启用 `setAllowUniversalAccessFromFileUrls(true)`。

## Web iframe

Web 平台应谨慎配置 iframe sandbox：

```dart
final params = WebWebViewControllerCreationParams(
  iFrameSandbox: 'allow-same-origin allow-scripts allow-forms',
  iFrameReferrerPolicy: 'no-referrer',
);
```

除非产品明确需要，不要随意添加 `allow-top-navigation` 等高权限 sandbox 能力。

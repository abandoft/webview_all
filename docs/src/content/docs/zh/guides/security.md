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

## WebAuthn 与 Passkey

WebAuthn 必须保留平台引擎的 origin 和 authenticator 安全模型。只有 AndroidX
WebKit 需要显式开关，因此 `webview_all` 只在 Android 平台提供该 API；不会模拟
凭据，也不会向公共 Controller 增加其他引擎无法执行的开关。

| 平台 | 生产环境要求 |
| --- | --- |
| Android | 先检查 `WebViewFeatureType.webAuthentication`；普通应用使用 `forApp` 并配置 Digital Asset Links。`forBrowser` 只适用于具备资格的特权浏览器应用。 |
| iOS/macOS | 由 `WKWebView` 处理，并在 Associated Domains 中配置 relying party。 |
| Windows | 由 WebView2 与 Windows 处理，需要验证实际的桌面、Server 或虚拟化部署环境。 |
| Linux | WebKitGTK 目前不支持 WebAuthn，使用支持该能力的外部浏览器或其他登录方式。 |
| OHOS | ArkWeb 没有文档化的宿主集成，未经目标设备验证不应假定 Passkey 可用。 |
| Web | 跨域 iframe 通过 `iFrameAllow` 授予 `publickey-credentials-get`；只在需要注册时再授予 `publickey-credentials-create`。 |

当 authenticator 能力检测失败时，必须保留非 Passkey 登录方式。不要使用接收原始
凭据或绕过 relying-party 校验的 JavaScript bridge 替代 WebAuthn。

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
  iFrameSandbox: 'allow-scripts allow-forms',
  iFrameReferrerPolicy: 'no-referrer',
);
```

对不可信的同源或 `srcdoc` 内容，不要同时加入 `allow-scripts` 和
`allow-same-origin`，否则页面可能移除自身 sandbox。严格 sandbox 下的
`loadHtmlString` 与 fetch-backed HTML 会通过插件的隔离消息桥提供受支持的
控制器能力。

除非产品明确需要，不要随意添加 `allow-top-navigation` 等高权限 sandbox 能力。

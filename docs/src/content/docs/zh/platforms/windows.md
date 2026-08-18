---
title: Windows
description: WebView2 实现、运行时设置、API 和限制。
---

Windows 由 `webview_all_windows 1.3.7` 提供，底层使用 Microsoft Edge WebView2。

| 项 | 值 |
| --- | --- |
| Controller | `WindowsWebViewController` |
| Widget | `WindowsWebViewWidget` |
| Delegate | `WindowsNavigationDelegate` |
| Cookie manager | `WindowsWebViewCookieManager` |
| 引擎 | WebView2 |
| 最低 OS | Windows 10 1809+ |

## 环境初始化

```dart
await WindowsWebViewController.initializeEnvironment(
  userDataPath: 'C:\\AppData\\MyApp\\WebView2',
);

final version = await WindowsWebViewController.getWebViewVersion();
```

需要自定义用户数据目录、浏览器路径或启动参数时，应在创建 controller 前调用。

controller 初始化失败时，组件中心会显示错误和两个操作：

- **Install Webview2**：用默认浏览器打开 Microsoft 官方 WebView2 下载页。
- **Refresh**：清理失败过程中创建的 native 状态和订阅后，使用同一个
  controller 重试初始化。

## Popup 策略

```dart
final params = const WindowsWebViewControllerCreationParams(
  popupWindowPolicy: WindowsPopupWindowPolicy.sameWindow,
);
```

| 值 | 行为 |
| --- | --- |
| `allow` | 允许 popup 新窗口。 |
| `deny` | 拦截 popup。 |
| `sameWindow` | 在当前 WebView 打开 popup 内容。 |

## 主要 API

| API | 作用 |
| --- | --- |
| `openDevTools` | 打开 WebView2 DevTools。 |
| `suspend` / `resume` | 暂停/恢复 WebView。 |
| `setPopupWindowPolicy` | 运行时修改 popup 策略。 |
| `setZoomFactor` | 设置 WebView2 缩放因子。 |
| `setCacheDisabled` | 控制请求是否绕过 cache。 |
| `dispose` | 永久释放此 controller 及其 WebView2 资源。 |

`onNavigationRequest` 会覆盖 controller 加载以及页面内容触发的 WebView2 主 frame 导航，包括 redirect 和 `sameWindow` popup。controller 请求在原生分发前完成判断，因此会保留自定义 method、headers 和 body；页面导航通过取消后等待异步 Dart 决策、放行后重放来实现，策略性取消不会触发 `onWebResourceError`。

本地文件和 Flutter asset 会使用每个 controller 独立的随机 HTTPS host。路径会先规范化，asset 路径穿越和逃出 bundle 的符号链接会被拒绝，跨 origin 访问默认禁止，切换到无关的远程或 inline 内容前会清理映射。

## 资源生命周期

从组件树中移除 `WebViewWidget` 只会隐藏并分离原生画面，不会销毁
controller。这样同一个 controller 再次挂载时，当前页面、历史记录和设置不会
丢失。

确认不再使用某个 Windows controller 时，应主动调用 `dispose()`，以确定性
释放插件持有的 WebView2 renderer 和原生资源：

```dart
import 'dart:async';

@override
void dispose() {
  final platform = controller.platform;
  if (platform is WindowsWebViewController) {
    unawaited(platform.dispose());
  }
  super.dispose();
}
```

`WindowsWebViewController.dispose()` 可重复调用，在初始化尚未完成时调用也能
安全收尾。finalizer 仍作为 controller 不可达后的兜底，但不能代替明确的资源
生命周期。已释放的 controller 不能再次挂载或调用。该接口仅属于 Windows
平台，不会给公共 controller 增加生命周期 API。

## WebAuthn 与 Passkey

WebView2 没有 Android 式的 WebAuthn 支持级别开关。网页直接调用标准
`navigator.credentials` API，再由已安装的 WebView2 Runtime、Windows 和
凭据提供方处理；`webview_all` 不会关闭或替换这条通路。

需要使用安全的 HTTPS relying-party origin，并由有效用户操作发起 Passkey
请求。每种目标 Windows 部署环境都应验证注册和登录，尤其是 Windows
Server、VDI、RDP 和受策略管理的凭据提供方。当平台 authenticator
不可用时，网页必须保留其他登录方式；插件不会用 JS 模拟 Windows Hello
或安全密钥。

## 完整 Cookie

```dart
final manager = WebViewCookieManager().platform
    as WindowsWebViewCookieManager;

await manager.setWindowsCookie(
  WindowsWebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
    isHttpOnly: true,
    isSecure: true,
    sameSite: WindowsWebViewCookieSameSite.lax,
  ),
);
```

还支持按完整 cookie、name+url、name+domain+path 删除。

## 限制

- 目标机器必须有 WebView2 Runtime。
- WebAuthn 可用性由 WebView2 Runtime、Windows 和凭据提供方决定；
  [WebView2 上游问题](https://github.com/MicrosoftEdge/WebView2Feedback/issues/5663)
  记录了 Windows Server 和虚拟化环境中的失败反馈。
- 滚动条和 overscroll 通过 CSS 注入实现。
- 环境初始化应只做一次，并尽量早于 controller 创建。
- WebView2 environment、composition texture 或帧捕获启动失败时会返回
  `PlatformException`，不再因原生断言终止进程。
- 初始化支持幂等重试；显式释放或 finalizer 兜底时，native channel、event
  subscription、stream 和 delegate 都只清理一次。
- surface resize 使用代际校验并跟随运行中的显示器和 DPI 变化，旧任务不会
  覆盖当前 texture 尺寸。

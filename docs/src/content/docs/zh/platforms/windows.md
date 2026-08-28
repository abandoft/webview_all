---
title: Windows
description: WebView2 实现、运行时设置、API 和限制。
---

Windows 由 `webview_all_windows 1.4.0` 提供，底层使用 Microsoft Edge WebView2。

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
await WindowsWebViewController.ensureEnvironment(
  userDataPath: 'C:\\AppData\\MyApp\\WebView2',
);

final version = await WindowsWebViewController.getWebViewVersion();
```

需要自定义用户数据目录、浏览器路径或启动参数时，应在创建 controller 前调用。
参数相同的多次调用（包括环境仍在创建时发起的并发调用）会合并并复用共享环境；参数冲突时会返回
`environment_configuration_conflict`，不会静默切换数据区。旧的
`initializeEnvironment` 保留给明确要求只能初始化一次的调用方。

环境初始化只检查 WebView2 Runtime 和 profile。图形捕获、Direct3D 与
Windows Composition 会推迟到首个 controller 创建时初始化，
`ensureEnvironment` 不会再被无关的渲染能力拦截。

网站数据清理也可以直接携带环境参数，不会启动图形捕获或创建 Flutter 纹理：

```dart
final manager = WebViewDataManager.fromPlatformCreationParams(
  const WindowsWebViewDataManagerCreationParams(
    userDataPath: 'C:\\AppData\\MyApp\\WebView2',
  ),
);
final result = await manager.clearAllWebsiteData();
```

controller 初始化失败时，组件中心会显示错误和恢复操作：

- **Install Webview2**：仅在缺少 WebView2 Runtime 时显示，并用默认浏览器打开
  Microsoft 官方下载页。
- **Refresh**：清理失败过程中创建的 native 状态和订阅后，使用同一个
  controller 重试初始化。

如果初始化完成后发生渲染失败，组件会暂停自动画面更新并显示 **Refresh**，
点击后会在现有 controller 上重新挂载画面并同步尺寸。

渲染器会优先复用应用已有的 `DispatcherQueue`，仅在 UI 线程没有队列时创建；
帧捕获及其回调统一使用该 UI 线程队列，Direct3D 硬件设备创建失败时会回退到
WARP 软件渲染器。

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
| `ensureEnvironment` | 幂等创建或复用配置一致的共享 WebView2 环境。 |
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
- 自定义环境参数应早于 controller 创建，或通过 `WindowsWebViewDataManagerCreationParams` 将相同参数传给数据清理操作。
- WebView2 environment、composition texture 或帧捕获启动失败时会返回
  `PlatformException`，不再因原生断言终止进程。
- Windows 初始化异常包含稳定的失败阶段、HRESULT、远程会话标记，并在可用时
  包含检测到的 WebView2 Runtime 版本，详见[错误与限制](/zh/reference/errors-and-limits/)。
- 初始化支持幂等重试；显式释放或 finalizer 兜底时，native channel、event
  subscription、stream 和 delegate 都只清理一次。
- surface resize 使用代际校验并跟随运行中的显示器和 DPI 变化，旧任务不会
  覆盖当前 texture 尺寸。

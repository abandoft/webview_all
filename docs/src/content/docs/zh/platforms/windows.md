---
title: Windows
description: WebView2 实现、运行时设置、API 和限制。
---

Windows 由 `webview_all_windows 1.3.6` 提供，底层使用 Microsoft Edge WebView2。

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

`onNavigationRequest` 会覆盖 controller 加载以及页面内容触发的 WebView2 主 frame 导航，包括 redirect 和 `sameWindow` popup。controller 请求在原生分发前完成判断，因此会保留自定义 method、headers 和 body；页面导航通过取消后等待异步 Dart 决策、放行后重放来实现，策略性取消不会触发 `onWebResourceError`。

本地文件和 Flutter asset 会使用每个 controller 独立的随机 HTTPS host。路径会先规范化，asset 路径穿越和逃出 bundle 的符号链接会被拒绝，跨 origin 访问默认禁止，切换到无关的远程或 inline 内容前会清理映射。

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
- 滚动条和 overscroll 通过 CSS 注入实现。
- 环境初始化应只做一次，并尽量早于 controller 创建。
- WebView2 environment、composition texture 或帧捕获启动失败时会返回
  `PlatformException`，不再因原生断言终止进程。
- 初始化支持幂等重试；内部 controller 最终释放时，native channel、event
  subscription、stream 和 delegate 都只清理一次，不增加公共 controller
  `dispose()` API。
- 异步初始化后的 surface resize 使用代际校验，旧尺寸和组件销毁后的任务不会
  覆盖当前 texture 尺寸。

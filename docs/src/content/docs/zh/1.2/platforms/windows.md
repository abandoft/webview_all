---
title: Windows
description: WebView2 实现、运行时设置、API 和限制。
---

Windows 由 `webview_all_windows 1.2.1` 提供，底层使用 Microsoft Edge WebView2。

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

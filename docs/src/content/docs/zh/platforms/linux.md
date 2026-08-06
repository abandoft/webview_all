---
title: Linux
description: WebKitGTK 实现、自动 GtkOverlay 集成、API 和限制。
---

Linux 由 `webview_all_linux 1.3.3` 提供，底层使用 WebKitGTK。

| 项 | 值 |
| --- | --- |
| Controller | `LinuxWebViewController` |
| Widget | `LinuxWebViewWidget` |
| Delegate | `LinuxNavigationDelegate` |
| Cookie manager | `LinuxWebViewCookieManager` |
| 引擎 | WebKitGTK |
| 系统依赖 | `webkit2gtk-4.1` |

## Runner 集成

Linux WebView 是 native GTK widget。插件会在标准 Flutter runner realize
`FlView` 前自动安装所需的 `GtkOverlay`，应用无需修改 runner。

## 创建参数

```dart
final params = const LinuxWebViewControllerCreationParams(
  developerExtrasEnabled: true,
  mediaPlaybackRequiresUserGesture: false,
  pageCacheEnabled: true,
  allowFileAccessFromFileUrls: false,
  allowUniversalAccessFromFileUrls: false,
  zoomFactor: 1.0,
);
```

所有字段都可为 `null`，表示保留 WebKitGTK 默认值。

## 主要 API

| API | 作用 |
| --- | --- |
| `setDeveloperExtrasEnabled` | 启用开发者功能。 |
| `openDevTools` | 打开 Web Inspector。 |
| `setJavaScriptCanOpenWindowsAutomatically` | 控制 JS popup。 |
| `setMediaPlaybackRequiresUserGesture` | 控制媒体自动播放。 |
| `setMediaPlaybackAllowsInline` | 控制内联媒体播放。 |
| `setPageCacheEnabled` | 控制 page cache。 |
| `setAllowFileAccessFromFileUrls` | 允许 file 页面读其他 file URL。 |
| `setAllowUniversalAccessFromFileUrls` | 允许 file 页面访问所有 origin。 |
| `setDefaultFontSize` / `setMinimumFontSize` | 字号设置。 |
| `setZoomFactor` | 页面缩放。 |
| `dispose` | 可选的 Linux 平台专用提前释放入口。 |

常规清理也是自动的：Linux controller 不再可达时，finalizer 会释放 native
WebView。公共 `WebViewController` 没有增加 `dispose()`，组件移出树也不会让仍
可能复用的 controller 失效。

通用 `enableZoom(false)` 会禁用插件可控制的 WebKitGTK 缩放手势，包括
Ctrl+鼠标滚轮和 Ctrl+`+`/`-`/`0`；普通滚动与键盘输入不受影响。

## 事件覆盖

Linux 通过 event channel 上报 URL、页面生命周期、进度、history、title、资源错误、HTTP 错误、JS channel、console、scroll、导航请求、HTTP auth、SSL auth、权限请求和 JS dialog。

所有等待 Dart 决策的 native request 都有 30 秒期限。如果应用没有完成请求或
event channel 关闭，导航会拒绝，认证/dialog/TLS 会取消，权限会拒绝。应用回调
抛异常时会打印单行信息并使用相同的安全默认值，不会让 WebKitGTK 一直阻塞。

## 限制

- WebView 是 GTK 原生 widget，层叠和裁剪遵循 GTK overlay 行为。
- 本地文件必须使用绝对路径，并会在加载前规范化；Flutter asset 中的路径穿越、绝对路径和逃出 asset bundle 的符号链接会被拒绝。
- 不可信本地文件不要启用 universal file URL access。
- 不同发行版 WebKitGTK 版本差异明显，媒体、权限和 dialog 需要在目标发行版验证。
- frame 更新是异步且错误隔离的，组件销毁阶段不会泄漏未处理异常。

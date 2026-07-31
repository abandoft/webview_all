---
title: Linux
description: WebKitGTK 实现、GtkOverlay 设置、API 和限制。
---

Linux 由 `webview_all_linux 1.2.1` 提供，底层使用 WebKitGTK。

| 项 | 值 |
| --- | --- |
| Controller | `LinuxWebViewController` |
| Widget | `LinuxWebViewWidget` |
| Delegate | `LinuxNavigationDelegate` |
| Cookie manager | `LinuxWebViewCookieManager` |
| 引擎 | WebKitGTK |
| 系统依赖 | `webkit2gtk-4.1` |

## Runner 设置

Linux WebView 是 native GTK widget，需要 `GtkOverlay` 与 Flutter view 共享窗口。完整代码见[平台设置](/webview_all/zh/1.2/getting-started/platform-setup/#linux)。

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
| `dispose` | 释放 native WebView。 |

## 事件覆盖

Linux 通过 event channel 上报 URL、页面生命周期、进度、history、title、资源错误、HTTP 错误、JS channel、console、scroll、导航请求、HTTP auth、SSL auth、权限请求和 JS dialog。

## 限制

- WebView 是 GTK 原生 widget，层叠和裁剪遵循 GTK overlay 行为。
- 不可信本地文件不要启用 universal file URL access。
- 不同发行版 WebKitGTK 版本差异明显，媒体、权限和 dialog 需要在目标发行版验证。

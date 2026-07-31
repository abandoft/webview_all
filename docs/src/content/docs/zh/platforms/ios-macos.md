---
title: iOS 和 macOS
description: WKWebView 实现、WebKit API 和 Apple 平台差异。
---

iOS 和 macOS 由 `webview_all_wkwebview ^1.3.0` 提供。

| 项 | 值 |
| --- | --- |
| 平台包 | `webview_all_wkwebview` |
| Controller | `WebKitWebViewController` |
| Widget | `WebKitWebViewWidget` |
| Delegate | `WebKitNavigationDelegate` |
| Cookie manager | `WebKitWebViewCookieManager` |
| 引擎 | `WKWebView` |
| 最低 iOS | 13.0+ |
| 最低 macOS | 10.15+ |

## 创建参数

```dart
final params = WebKitWebViewControllerCreationParams(
  allowsInlineMediaPlayback: true,
  mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
  limitsNavigationsToAppBoundDomains: false,
  javaScriptCanOpenWindowsAutomatically: true,
);
```

| 参数 | 作用 |
| --- | --- |
| `mediaTypesRequiringUserAction` | 哪些媒体类型需要用户手势。 |
| `allowsInlineMediaPlayback` | 允许 HTML5 视频内联播放。 |
| `limitsNavigationsToAppBoundDomains` | 启用 App-Bound Domains。 |
| `javaScriptCanOpenWindowsAutomatically` | 控制 JS 自动打开窗口。 |

## 主要 API

| API | 作用 |
| --- | --- |
| `setAllowsBackForwardNavigationGestures` | 启用滑动前进/后退。 |
| `setAllowsLinkPreview` | 控制 link preview。 |
| `setOnCanGoBackChange` | 监听 `canGoBack` 变化。 |
| `setInspectable` | 启用 WebKit inspect。 |
| `loadFileWithParams(WebKitLoadFileParams)` | 加载本地文件并设置可读范围。 |

## 本地文件

```dart
await (controller.platform as WebKitWebViewController).loadFileWithParams(
  WebKitLoadFileParams(
    absoluteFilePath: '/Users/me/site/index.html',
    readAccessPath: '/Users/me/site',
  ),
);
```

`readAccessPath` 必须覆盖 HTML 引用的本地资源。

## macOS 差异

macOS 与 iOS 共用 Dart 包，但部分 UIKit 风格属性在 macOS 没有 bridge：

| 区域 | 限制 |
| --- | --- |
| scroll view | 部分 scroll view 方法未实现。 |
| background/opaque | macOS 上 `setBackgroundColor` 会由主 wrapper 忽略，并在终端打印日志。 |
| link preview | 取决于系统支持。 |

其他 Apple 平台专用调用仍应做好平台判断和 `UnimplementedError` 处理。

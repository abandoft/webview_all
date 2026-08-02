---
title: iOS 和 macOS
description: WKWebView 实现、WebKit API 和 Apple 平台差异。
---

iOS 和 macOS 由 `webview_all_wkwebview ^1.3.2` 提供。

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
| `limitsNavigationsToAppBoundDomains` | 在 iOS 14+、macOS 11+ 启用 App-Bound Domains；更早系统打印版本要求并保留默认值。 |
| `javaScriptCanOpenWindowsAutomatically` | 控制 JS 自动打开窗口。 |

## 主要 API

| API | 作用 |
| --- | --- |
| `setAllowsBackForwardNavigationGestures` | 启用滑动前进/后退。 |
| `setAllowsLinkPreview` | 控制 link preview。 |
| `setOnCanGoBackChange` | 监听 `canGoBack` 变化。 |
| `setInspectable` | 在 iOS 16.4+、macOS 13.3+ 启用 WebKit inspect；更早系统打印版本要求并安全忽略。 |
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

macOS 与 iOS 共用 Dart 包。macOS 端只使用公开原生 WebKit API，并在运行时判断系统版本；不会通过注入 JavaScript 模拟缺失的视图 API。

| 区域 | 限制 |
| --- | --- |
| 滚动位置与回调 | macOS `WKWebView` 没有公开内部 scroll view；调用会打印说明并安全忽略，读取返回 `Offset.zero`。 |
| 滚动条与 overscroll | macOS 没有对应公开 API；调用会打印说明并安全忽略。 |
| 背景色 | macOS 12+ 使用原生 `underPageBackgroundColor`；更早系统打印版本要求并安全忽略。 |
| 缩放 | 使用原生 `allowsMagnification`，不使用 JavaScript 兜底。 |
| inspect | 需要 macOS 13.3+；更早系统打印版本要求并安全忽略。 |
| link preview | 取决于系统支持。 |

这些兼容逻辑由 `webview_all_wkwebview` 子插件负责，主 `webview_all` Controller 不再包含 macOS 特判。

## Engine 关闭

子插件会在 iOS application termination、受支持的 scene disconnect 或 Flutter
engine detach 时进行幂等清理：停止向 Dart 发消息，并移除 Pigeon handler 和
instance；生命周期回调重复到达也不会出错。macOS 继续使用 Flutter 的 engine
detach 回调。

当 Flutter engine 提供公开 scene 协议时，插件会自动注册 scene 生命周期。
iOS 原生 `WKWebView` 访问入口也支持传入 `FlutterPluginRegistrar`：可用时使用
Flutter 官方 registrar 查询，较早的受支持 Flutter 版本使用按 engine 隔离的兼容
查询，无需修改宿主应用。

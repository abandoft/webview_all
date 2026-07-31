---
title: OHOS
description: ArkWeb 实现、API 和 HarmonyOS/OpenHarmony 限制。
---

OHOS 由 `webview_all_ohos 1.3.0` 提供，底层使用 ArkWeb。

| 项 | 值 |
| --- | --- |
| Controller | `OhosWebViewController` |
| Widget | `OhosWebViewWidget` |
| Delegate | `OhosNavigationDelegate` |
| Cookie manager | `OhosWebViewCookieManager` |
| 引擎 | ArkWeb |
| 最低目标 | OHOS API 12+ |

## 创建参数

```dart
final params = OhosWebViewControllerCreationParams(
  domStorageEnabled: true,
  javaScriptCanOpenWindowsAutomatically: true,
  supportMultipleWindows: true,
  loadWithOverviewMode: true,
  useWideViewPort: true,
  allowFileAccess: true,
  mediaPlaybackRequiresUserGesture: false,
  supportZoom: true,
  textZoom: 100,
);
```

## 主要 API

| API | 作用 |
| --- | --- |
| `OhosWebViewController.enableDebugging` | 全局启用 ArkWeb 调试。 |
| `webViewIdentifier` | 原生 WebView 实例 ID。 |
| `setAllowFullScreenRotate` | 控制全屏旋转。 |
| `setDomStorageEnabled` | 控制 DOM storage。 |
| `setSupportMultipleWindows` | 控制多窗口。 |
| `setLoadWithOverviewMode` / `setUseWideViewPort` | 视口相关设置。 |
| `setDisplayZoomControls` / `setBuiltInZoomControls` | 缩放控件。 |
| `setAllowFileAccess` | file access。 |
| `setOnShowFileSelector` | 文件选择。 |
| `setGeolocationPermissionsPromptCallbacks` | 定位提示。 |
| `setCustomWidgetCallbacks` | 全屏 custom view。 |

## `loadRequest`

| 请求 | 支持 |
| --- | --- |
| GET 无 headers | 支持。 |
| GET 自定义 headers | 支持。 |
| POST 无自定义 headers | 支持。 |
| POST 自定义 headers | 不支持，抛 `UnsupportedError`。 |

ArkWeb `postUrl` 只接收 URL 和 body，不接收 headers，因此库明确失败。

## 权限和 Cookie

OHOS 支持 camera、microphone，并扩展 `midiSysex`、`protectedMediaId`。

```dart
await (WebViewCookieManager().platform as OhosWebViewCookieManager)
    .setAcceptThirdPartyCookies(
  controller.platform as OhosWebViewController,
  true,
);
```

## 限制

- WebView 权限批准不等于系统权限，宿主应用仍需声明并获取权限。
- ArkWeb 行为可能随 HarmonyOS/OpenHarmony 版本变化，尤其是媒体、文件选择和权限。

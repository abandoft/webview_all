---
title: WebView All
description: webview_all 文档，全平台的 Flutter WebView。
---

`webview_all` 是一个 Flutter WebView 库，支持 Android、iOS、macOS、Windows、
Linux、OpenHarmony 和 Web 等平台，使用从 Flutter 官方接口 fork 的
[`webview_platform_interface`](https://pub.dev/packages/webview_platform_interface)。

当前无版本号路由对应 latest，文档版本为 `1.3.3`。

## 平台兼容性

| 平台 | 最低要求 | 引擎 |
| --- | --- | --- |
| Android | API 24+ | `WebView` |
| iOS | 13.0+ | `WKWebView` |
| macOS | 10.15+ | `WKWebView` |
| Windows | Windows 10 1809+ | `WebView2` |
| Linux | `webkit2gtk-4.1` | `WebKitGTK` |
| OHOS | API 12+ | `ArkWeb` |
| Web | 无 | `JS interop` |

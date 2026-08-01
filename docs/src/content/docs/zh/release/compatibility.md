---
title: 兼容性
description: 版本基线、依赖基线和维护规则。
---

## 当前基线

| 包 | 版本 |
| --- | --- |
| `webview_all` | `1.3.1` |
| `webview_all_windows` | `1.3.1` |
| `webview_all_linux` | `1.3.1` |
| `webview_all_ohos` | `1.3.1` |
| `webview_all_web` | `1.3.1` |
| `webview_platform_interface` | `1.3.1` |
| `webview_all_android` | `1.3.1` |
| `webview_all_wkwebview` | `1.3.1` |
| Flutter SDK | `>=3.35.0` |
| Dart SDK | `^3.9.0` |

## 平台基线

|     系统     | **支持情况** | **技术实现** |
|-------------|--------------|--------------|
|Android|API 24+|[WebView](https://developer.android.com/reference/android/webkit/WebView)|
|iOS|13.0+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|macOS|10.15+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|Windows|Win10 1809+|[WebView2](https://developer.microsoft.com/microsoft-edge/webview2)|
|Linux|webkit2gtk-4.1|[WebKitGTK](https://webkitgtk.org)|
|OHOS|API 12+|[ArkWeb](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-basic-components-web-V5)|
|Web|Any|[js-interop](https://dart.dev/interop/js-interop)|

## 维护规则

升级 `webview_platform_interface` 时：

1. 比对 controller、delegate、widget、cookie manager 和 platform factory 的新增方法。
2. 所有平台包都要显式实现。
3. 引擎支持时优先做真实 native 实现。
4. 做不到时用 `UnsupportedError` 明确失败。
5. 只有能力检查保护下的注册型 API 才使用 no-op。
6. 同步更新能力矩阵和平台 API 文档。
7. 发布前跑 format、analyze、tests 和 publish dry-run。

## 发布顺序

先发布各平台的子包，pub.dev 能解析后再发布主包：

1. `webview_platform_interface`
2. `webview_all_android`
3. `webview_all_wkwebview`
4. `webview_all_windows`
5. `webview_all_linux`
6. `webview_all_web`
7. `webview_all_ohos`
8. `webview_all`

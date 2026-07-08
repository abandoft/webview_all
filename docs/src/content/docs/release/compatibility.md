---
title: Compatibility
description: Version alignment, dependency baseline, and maintenance rules.
---

## Current Baseline

| Package | Version |
| --- | --- |
| `webview_all` | `1.2.1` |
| `webview_all_windows` | `1.2.1` |
| `webview_all_linux` | `1.2.1` |
| `webview_all_ohos` | `1.2.1` |
| `webview_all_web` | `1.2.1` |
| `webview_flutter_platform_interface` | `^2.15.1` |
| `webview_flutter_android` | `^4.12.0` |
| `webview_flutter_wkwebview` | `^3.25.0` |
| Flutter SDK | `>=3.35.0` |
| Dart SDK | `^3.9.0` |

## Platform Baseline

| Platform | Support | Implementation |
|-------------|--------------|--------------|
|Android|API 24+|[WebView](https://developer.android.com/reference/android/webkit/WebView)|
|iOS|13.0+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|macOS|10.15+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|Windows|Win10 1809+|[WebView2](https://developer.microsoft.com/microsoft-edge/webview2)|
|Linux|webkit2gtk-4.1|[WebKitGTK](https://webkitgtk.org)|
|OHOS|API 12+|[ArkWeb](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/ts-basic-components-web-V5)|
|Web|Any|[js-interop](https://dart.dev/interop/js-interop)|

## Maintenance Rules

When upgrading `webview_flutter_platform_interface`:

1. Compare new methods on the controller, delegate, widget, cookie manager, and platform factory.
2. Every platform package must implement them explicitly.
3. Prefer a real native implementation when the engine exposes one.
4. Use `UnsupportedError` when a feature cannot be provided.
5. Use no-op only for registration-style APIs protected by capability checks.
6. Update the capability matrix and platform API documentation.
7. Run format, analyze, tests, and publish dry-run before release.

## Release Order

Publish child platform packages first, then publish the main package after pub.dev can resolve them:

1. `webview_all_windows`
2. `webview_all_linux`
3. `webview_all_web`
4. `webview_all_ohos`
5. `webview_all`

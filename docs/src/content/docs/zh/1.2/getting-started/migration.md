---
title: 迁移
description: 从 webview_flutter 或旧版 webview_all 迁移。
---

`webview_all` 的顶层 API 与 `webview_flutter` 的接口兼容。多数代码可以先替换 import，再按需处理平台差异。

## 从 webview_flutter 迁移

替换：

```dart
import 'package:webview_flutter/webview_flutter.dart';
```

为：

```dart
import 'package:webview_all/webview_all.dart';
```

通常可继续使用：

- `WebViewController`
- `WebViewWidget`
- `NavigationDelegate`
- `WebViewCookieManager`
- `NavigationDecision`
- `JavaScriptMode`
- `WebViewCookie`

随后对照[能力矩阵](/webview_all/zh/1.2/platforms/capability-matrix/)检查差异。Web 和 OHOS 差异最明显，原因分别是浏览器 iframe 安全限制和 ArkWeb 请求 API 限制。

## 平台 import

Android/iOS/macOS 的平台包仍然是官方实现；已有平台特性代码可以继续使用：

```dart
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
```

新增桌面、OHOS、Web 平台特性时：

```dart
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
```

## 1.2.0 更新内容

- Windows 扩展了 WebView2 环境、DevTools、popup 策略、暂停恢复、zoom、cache、HTTP/SSL auth、JS dialog、权限、console、scroll、完整 cookie 元数据。
- Linux 扩展了 WebKitGTK 设置、Inspector、HTTP/SSL auth、权限、JS dialog、console、scroll。
- OHOS 扩展了 ArkWeb 设置、文件选择、定位提示、全屏 custom view、权限、JS dialog、HTTP/SSL 错误、第三方 cookie。
- Web 扩展了 iframe 属性、fetch-backed 请求、同源 JS channel、console/dialog hook 和媒体权限中介。

## 迁移时重点检查

| 区域 | 需要确认 |
| --- | --- |
| `loadRequest` | Android/OHOS 不支持 POST + 自定义 headers。Web 受 CORS 限制。 |
| JavaScript | Web 只能控制同源 iframe 内容。 |
| Cookie | Web cookie 只来自宿主页 `document.cookie`。 |
| TLS | Web 无法暴露可恢复证书错误决策。 |
| macOS | 部分 UIKit 风格 WebKit 属性没有 macOS bridge。 |
| Linux | runner 需要 `GtkOverlay`。 |

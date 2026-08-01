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

随后对照[能力矩阵](/webview_all/zh/platforms/capability-matrix/)检查差异。Web 和 OHOS 差异最明显，原因分别是浏览器 iframe 安全限制和 ArkWeb 请求 API 限制。

## 平台 import

`1.3.0` 起，Android/iOS/macOS 改用仓库内的 fork 包。原先导入
`webview_flutter_android` 或 `webview_flutter_wkwebview` 的平台特性代码，
应改为：

```dart
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
```

新增桌面、OHOS、Web 平台特性时：

```dart
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
```

## 1.3.1 更新内容

`1.3.1` 在不改变公共 controller 接口的前提下强化运行时失败处理：

- macOS 按系统版本使用原生 API，不可用能力打印说明并安全降级。
- Web 保持受管理 HTML 的 origin 隔离，通过绑定导航生命周期的消息桥恢复受支持能力。
- Linux 缩放禁用实际生效；OHOS 正确传播加载失败；Windows 初始化失败转为可诊断的平台错误。
- Android 无法保留自定义 header 的 POST 会明确拒绝，不再静默发送语义不同的请求。

## 1.3.0 更新内容

- Windows、Linux、OHOS 和 Web controller 使用弱引用回调及自动 finalizer
  清理。
- Linux 插件会在标准 Flutter runner realize `FlView` 前自动安装所需的
  `GtkOverlay`。现有应用可以把 `linux/runner/my_application.cc` 恢复为
  Flutter 默认实现；已经手动用 `GtkOverlay` 包裹 `FlView` 的应用也可以保留
  现有代码，插件会直接复用已有 Overlay，不会再嵌套一层。

## 1.2.0 更新内容

- Windows 扩展了 WebView2 环境、DevTools、popup 策略、暂停恢复、zoom、cache、HTTP/SSL auth、JS dialog、权限、console、scroll、完整 cookie 元数据。
- Linux 扩展了 WebKitGTK 设置、Inspector、HTTP/SSL auth、权限、JS dialog、console、scroll。
- OHOS 扩展了 ArkWeb 设置、文件选择、定位提示、全屏 custom view、权限、JS dialog、HTTP/SSL 错误、第三方 cookie。
- Web 扩展了 iframe 属性、fetch-backed 请求、直接同源控制、插件管理 HTML 的隔离 bridge 和媒体权限中介。

## 迁移时重点检查

| 区域 | 需要确认 |
| --- | --- |
| `loadRequest` | Android/OHOS 不支持 POST + 自定义 headers。Web 受 CORS 限制。 |
| JavaScript | Web 可直接控制同源内容，并通过消息桥控制插件管理的隔离 HTML；直接跨域 iframe URL 仍由浏览器隔离。 |
| Cookie | Web cookie 只来自宿主页 `document.cookie`。 |
| TLS | Web 无法暴露可恢复证书错误决策。 |
| macOS | 部分 UIKit 风格 WebKit 属性没有 macOS bridge。 |
| Linux | 需要 WebKitGTK 4.1；标准 Flutter runner 无需修改源码。 |

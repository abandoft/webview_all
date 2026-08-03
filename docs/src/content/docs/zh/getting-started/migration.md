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

## 1.3.3 更新内容

`1.3.3` 在不改变公共 API 的前提下完善失败恢复：

- Windows 应用决策超过 30 秒未完成时使用安全默认值；回调在完成决定后抛错时，
  已完成的决定仍会保留。
- Linux widget 切换 controller 时会同步迁移原生视图的位置和可见性。
- WKWebView 会等待用户脚本和消息处理器移除完成，再重建 JavaScript channel。
- Web 和 OHOS 会隔离关键回调失败，避免对话框、权限或认证请求破坏 WebView
  运行状态。

## 1.3.2 更新内容

`1.3.2` 在不增加公共 `WebViewController.dispose()`、不提高 Flutter 3.35 /
Dart 3.9 最低版本的前提下，完善资源生命周期、失败恢复和测试：

- Windows 初始化具备幂等、失败清理和重试能力；居中的失败界面提供
  **Install Webview2** 与 **Refresh**，过期的 resize 任务不会再覆盖新状态。
- Web 会拒绝非法或保留的 iframe 属性；有上限的类型化历史记录会复用请求结果，
  前进/后退不重放 POST，显式 reload 仍会重新请求，并发旧导航也不会覆盖新页面。
- Web Cookie 读取要求请求 URL 的 scheme、host、path 与当前宿主文档完全
  一致；拒绝外域写入，清理结果按浏览器可见 cookie 是否实际消失判断。
- Linux 各类决策回调异常时默认采用安全结果，native 请求增加 30 秒截止时间，
  避免导航、认证、TLS、权限或对话框永久阻塞引擎。
- Android Cookie 解析保留值中的 `=`，容忍错误的 percent encoding，并迁移
  当前最低 Flutter 版本可实现的上游 native binding 访问入口。
- WKWebView 插件增加幂等的应用终止清理；需要更高 Flutter 最低版本的 scene
  和 registrar API 暂不引入。
- 所有非 OHOS 包增加最低/当前 Flutter CI、浏览器测试和宿主平台 native
  构建；OHOS 可通过隔离脚本运行，不再覆盖 stock Flutter 的 package 配置。

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
| Cookie | Web Cookie 读取要求当前宿主文档的精确 URL，写入不能指定外域。 |
| TLS | Web 无法暴露可恢复证书错误决策。 |
| macOS | 部分 UIKit 风格 WebKit 属性没有 macOS bridge。 |
| Linux | 需要 WebKitGTK 4.1；标准 Flutter runner 无需修改源码。 |

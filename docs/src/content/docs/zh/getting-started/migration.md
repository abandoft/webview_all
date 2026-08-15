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

## 1.3

从 `1.2` 升级时：

- 将直接使用的 `webview_flutter_android` 和
  `webview_flutter_wkwebview` import 替换为上方对应的 fork 包。
- Linux 不再要求修改应用 runner，可以将
  `linux/runner/my_application.cc` 恢复为 Flutter 默认实现。已经手动添加的
  `GtkOverlay` 仍然兼容，也可以保留。

`1.3` 内的补丁版本不需要额外迁移。

## 1.2

继续使用 `1.2.1` 的应用应参考已冻结的
[1.2 文档](/webview_all/zh/1.2/)。该版本的 Linux 接入仍需按文档修改 runner；
新的 `1.3` 应用不要再添加这段改动。

## 迁移时重点检查

| 区域 | 需要确认 |
| --- | --- |
| `loadRequest` | Android/OHOS 不支持 POST + 自定义 headers。Web 受 CORS 限制。 |
| JavaScript | Web 可直接控制同源内容，并通过消息桥控制插件管理的隔离 HTML；直接跨域 iframe URL 仍由浏览器隔离。 |
| Cookie | Web Cookie 读取要求当前宿主文档的精确 URL，写入不能指定外域。 |
| TLS | Web 无法暴露可恢复证书错误决策。 |
| macOS | 部分 UIKit 风格 WebKit 属性没有 macOS bridge。 |
| Linux | 需要 WebKitGTK 4.1；标准 Flutter runner 无需修改源码。 |

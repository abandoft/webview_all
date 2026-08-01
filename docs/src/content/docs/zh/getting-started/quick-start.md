---
title: 快速开始
description: 创建控制器、加载页面并渲染 WebView。
---

通用 API 主要由四个类组成：

- `WebViewController`：控制 WebView。
- `WebViewWidget`：显示 WebView。
- `NavigationDelegate`：接收导航事件。
- `WebViewCookieManager`：管理 WebView cookie。

## 基础用法

```dart
import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => debugPrint('Started $url'),
          onPageFinished: (url) => debugPrint('Finished $url'),
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse('https://flutter.dev'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browser')),
      body: WebViewWidget(controller: controller),
    );
  }
}
```

Windows、Linux、OHOS 和 Web 会在不再使用的 controller 变为不可达后自动释放
平台资源，无需编写平台专用的生命周期代码。

## 导航控制

```dart
if (await controller.canGoBack()) {
  await controller.goBack();
}

if (await controller.canGoForward()) {
  await controller.goForward();
}

await controller.reload();
```

## 加载 HTML

```dart
await controller.loadHtmlString(
  '<html><body><h1>Hello</h1></body></html>',
  baseUrl: 'https://example.com/docs/',
);
```

## JavaScript Channel

```dart
await controller.addJavaScriptChannel(
  'AppBridge',
  onMessageReceived: (JavaScriptMessage message) {
    debugPrint('Message from page: ${message.message}');
  },
);

await controller.runJavaScript('AppBridge.postMessage("ready")');
```

Web 平台上，同源内容使用直接访问；`loadHtmlString` 和 fetch-backed
`loadRequest` 管理的隔离 HTML 使用消息桥实现 JavaScript 执行和 channel。
直接跨域 iframe URL 仍受浏览器同源策略隔离。

## 使用平台实现

```dart
if (controller.platform is WindowsWebViewController) {
  final windows = controller.platform as WindowsWebViewController;
  await windows.openDevTools();
}
```

构造时需要平台参数时：

```dart
PlatformWebViewControllerCreationParams params =
    const PlatformWebViewControllerCreationParams();

if (WebViewPlatform.instance is WebKitWebViewPlatform) {
  params = WebKitWebViewControllerCreationParams(
    allowsInlineMediaPlayback: true,
    mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
  );
}

final controller = WebViewController.fromPlatformCreationParams(params);
```

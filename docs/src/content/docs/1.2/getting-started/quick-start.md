---
title: Quick Start
description: Create a controller, load content, and render the widget.
---

The common API uses four app-facing classes:

- `WebViewController` controls a WebView.
- `WebViewWidget` renders a controller.
- `NavigationDelegate` receives navigation callbacks.
- `WebViewCookieManager` manages shared WebView cookies.

## Basic WebView

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
          onPageStarted: (String url) {
            debugPrint('Started $url');
          },
          onPageFinished: (String url) {
            debugPrint('Finished $url');
          },
          onWebResourceError: (WebResourceError error) {
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

## Navigation Controls

```dart
Future<void> goBackIfPossible(WebViewController controller) async {
  if (await controller.canGoBack()) {
    await controller.goBack();
  }
}

Future<void> goForwardIfPossible(WebViewController controller) async {
  if (await controller.canGoForward()) {
    await controller.goForward();
  }
}
```

## Loading HTML

```dart
await controller.loadHtmlString(
  '''
  <!doctype html>
  <html>
    <body>
      <h1>Hello from WebView All</h1>
    </body>
  </html>
  ''',
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

On the web platform, JavaScript execution and channel injection require same-origin iframe content or content loaded by `loadHtmlString`/fetch-backed `loadRequest`. Cross-origin browser iframes intentionally block direct DOM and JavaScript access.

## Accessing Platform Implementations

```dart
if (controller.platform is WindowsWebViewController) {
  final windowsController = controller.platform as WindowsWebViewController;
  await windowsController.openDevTools();
}
```

Create platform-specific parameters before constructing the controller:

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

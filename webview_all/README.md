# WebView All

[English Doc](https://abandoft.github.io/webview_all) | [中文文档](https://abandoft.github.io/webview_all/zh)

A WebView component for all Flutter platforms, compatible with the
[webview_flutter](https://pub.dev/packages/webview_flutter) API.

|     Platform     | **Support** | **Implementation** |
|-------------|--------------|--------------|
|Android|API 24+|[WebView](https://developer.android.com/reference/android/webkit/WebView)|
|iOS|13.0+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|macOS|10.15+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|Windows|Win10 1809+|[WebView2](https://developer.microsoft.com/microsoft-edge/webview2)|
|Linux|webkit2gtk-4.1|[WebKitGTK](https://webkitgtk.org)|
|OHOS|API 12+|[ArkWeb](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/ts-basic-components-web-V5)|
|Web|Any|[js-interop](https://dart.dev/interop/js-interop)|

## Features

- Comprehensive support for all platforms
- Full compatibility with the `webview_flutter` API
- Additional features:
  - Promise-aware JavaScript calls
  - Document-start user scripts
  - Website data cleanup without a controller
  - Deterministically closable offscreen sessions
  - ......

## Quick Start

1. Instantiate a `WebViewController`:

```dart
controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse('https://flutter.dev'));
```

2. Pass `controller` to `WebViewWidget`:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Flutter Simple Example')),
    body: WebViewWidget(controller: controller),
  );
}
```

For detailed usage, API coverage, and platform limits, see the [Documentation](https://abandoft.github.io/webview_all).

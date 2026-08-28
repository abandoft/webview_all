# WebView All

[English Doc](https://abandoft.github.io/webview_all) | [中文文档](https://abandoft.github.io/webview_all/zh)

支持所有 Flutter 平台的 WebView 组件，兼容[webview_flutter](https://pub.dev/packages/webview_flutter)接口。

|     系统     | **支持情况** | **技术实现** |
|-------------|--------------|--------------|
|Android|API 24+|[WebView](https://developer.android.com/reference/android/webkit/WebView)|
|iOS|13.0+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|macOS|10.15+|[WKWebView](https://developer.apple.com/documentation/webkit/wkwebview)|
|Windows|Win10 1809+|[WebView2](https://developer.microsoft.com/microsoft-edge/webview2)|
|Linux|webkit2gtk-4.1|[WebKitGTK](https://webkitgtk.org)|
|OHOS|API 12+|[ArkWeb](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-basic-components-web-V5)|
|Web|Any|[js-interop](https://dart.dev/interop/js-interop)|

## 项目特色

- 完善的全平台支持
- 全面兼容 `webview_flutter` 接口
- 更多特性支持！
  - 支持 Promise 的 JavaScript 调用
  - 支持 document-start 用户脚本
  - 无需依赖 controller 的网站数据清理
  - 可确定关闭的离屏会话
  - ......

## 快速入门

1. 实例化一个 `WebViewController`:

```dart
controller = WebViewController()
  ..setJavaScriptMode(JavaScriptMode.unrestricted)
  ..loadRequest(Uri.parse('https://flutter.dev'));
```

2. 将 controller 传给 `WebViewWidget`:

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Flutter Simple Example')),
    body: WebViewWidget(controller: controller),
  );
}
```

更详细的用法、接口覆盖和平台限制请参考[中文文档](https://abandoft.github.io/webview_all/zh)

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
|OHOS|API 22+|[ArkWeb](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-basic-components-web-V5)|
|Web|Any|[js-interop](https://dart.dev/interop/js-interop)|

## 项目特色

- 完善的全平台支持
- 全面兼容 `webview_flutter` 接口
- 在成熟的商业级软件中被广泛采用
- 更多特性支持！
  - Promise 异步 JavaScript 调用
  - 页面脚本执行前的自定义 JavaScript 注入
  - 桌面端下载控制及 Windows 调试与快捷键设置
  - 更丰富的 Web 端交互与 iframe 配置
  - 无需 controller 的网站数据清理
  - 可主动关闭的离屏 WebView 会话
  - 自定义下载处理与进度回调

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

## 谁在使用

- [野火 IM](https://github.com/wildfirechat) 官方 Flutter 版：老牌的 IM/RTC 商业软件。
- [GodotHub](https://godothub.com) 官方客户端：广受喜爱的 Godot 社区平台。
- [Operit2](https://github.com/AAswordman/Operit2)：全平台的 AI Agent 智能体。
- [Miru](https://github.com/miru-project) 新版客户端：知名的视频、漫画和小说聚合应用。
- [SubDock](https://github.com/sub-store-org) 桌面端：Sub-Store 官方的桌面运行与管理工具。
- [OpenHarness](https://github.com/autonomous-ai/openharness) 桌面端：统一管理编程 Agent 与远程机器的 AI 工作台。
- [AnymeX](https://github.com/RyanYuuki/AnymeX)：跨平台动画、漫画进度追踪客户端。
- [ChessEver](https://chessever.com) 桌面端：集赛事直播、棋谱分析于一体的国际象棋平台。
- [Dartotsu](https://github.com/aayush2622/Dartotsu)：跨平台动画、漫画和小说追踪客户端。
- [Bili-music](https://github.com/AprDeci/bili-music)：基于哔哩哔哩的跨平台音乐播放器。
- [ShonenX](https://github.com/roshancodespace/ShonenX)：发现新番、追踪进度、在线播放一站搞定。
- [AFAN](https://github.com/SX-Code/afan)：集成切片、网页嗅探、自定义播放源的追番应用。

---
title: 文件、Asset 和 HTML
description: 安全加载本地文件、Flutter asset、内联 HTML 和自定义请求。
---

## 本地文件

```dart
await controller.loadFile('/Users/me/Documents/page.html');
```

| 平台 | 行为 |
| --- | --- |
| Android | 通过 file URL 加载，`AndroidLoadFileParams` 可附加 headers。 |
| iOS/macOS | WebKit 本地文件加载，`WebKitLoadFileParams` 控制可读范围。 |
| Windows | 把文件目录映射为内部 HTTPS virtual host。 |
| Linux | 通过 WebKitGTK 加载绝对路径。 |
| OHOS | 启用 file access 后加载 file URL。 |
| Web | 不支持。浏览器不允许 hosted app 读取任意本地文件。 |

## Android 文件 headers

```dart
await (controller.platform as AndroidWebViewController).loadFileWithParams(
  AndroidLoadFileParams(
    absoluteFilePath: '/sdcard/Download/page.html',
    headers: const <String, String>{'X-Source': 'app'},
  ),
);
```

## WebKit read access

```dart
await (controller.platform as WebKitWebViewController).loadFileWithParams(
  WebKitLoadFileParams(
    absoluteFilePath: '/Users/me/site/index.html',
    readAccessPath: '/Users/me/site',
  ),
);
```

`readAccessPath` 必须覆盖 HTML 引用的图片、脚本和样式。

## Flutter Asset

```yaml
flutter:
  assets:
    - assets/help/index.html
```

```dart
await controller.loadFlutterAsset('assets/help/index.html');
```

Windows 会把 asset 目录映射到内部 HTTPS host；Web 会解析为生成后的 `assets/` 路径。

## 内联 HTML

```dart
await controller.loadHtmlString(
  '<html><body><a href="details.html">Details</a></body></html>',
  baseUrl: 'https://docs.example.com/help/',
);
```

有相对链接时应提供 `baseUrl`。

## 自定义请求

```dart
await controller.loadRequest(
  Uri.parse('https://api.example.com/form'),
  method: LoadRequestMethod.post,
  headers: const <String, String>{'Content-Type': 'application/json'},
  body: Uint8List.fromList(utf8.encode('{"ok":true}')),
);
```

| 平台 | 说明 |
| --- | --- |
| Android | POST + 自定义 headers 不支持。 |
| OHOS | POST + 自定义 headers 不支持，会抛 `UnsupportedError`。 |
| Web | 非简单请求通过 `fetch`，需要服务端 CORS 允许。 |
| Windows/Linux/iOS/macOS | 支持 method、headers 和 body。 |

不支持的平台可用 app HTTP client 手动请求，再用 `loadHtmlString` 加载响应 HTML；但这不等价于浏览器原生导航，cookie、redirect、service worker 等语义会不同。

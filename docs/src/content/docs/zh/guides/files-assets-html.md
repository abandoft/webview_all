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

Windows 会为每个 controller 使用随机私有 HTTPS host 映射规范化后的 asset 目录，拒绝跨 origin 访问，并随导航替换或清理映射。Linux 只接受绝对文件路径，并会在加载前将其规范化；两者都会拒绝路径穿越和逃出 Flutter asset 目录的符号链接。Web 会解析为生成后的 `assets/` 路径。

## 应用资源 URL

需要让网页引用应用私有文件时，可通过资源代理提供内容，无需转成 Base64：

```dart
await controller.setResourceDelegate(
  WebViewResourceDelegate(onRequest: (request) {
    if (request.path != '/video.mp4') return null;
    return WebViewResourceResponse.file(videoPath, mimeType: 'video/mp4');
  }),
);

final url = controller.getResourceUri('video.mp4');
if (url != null) {
  await controller.loadHtmlString(
    '<video controls src="$url"></video>',
    baseUrl: controller.getResourceUri('/')!.toString(),
  );
}
```

`videoPath` 为应用已授权访问的绝对文件路径。资源路径按原始名称传入，无需预先进行 URL 编码。页面内可使用相对路径，或由 `getResourceUri` 生成的完整 URL 引用资源。代理默认关闭，只处理该 controller 生成的资源 URL；返回 `null` 会使该资源返回 404，普通网络请求不受影响。请使用返回的 URL，不要硬编码协议或域名。

`WebViewResourceResponse.bytes` 提供字节数据，`.file` 按需读取文件，两者自动支持 HEAD 和单段 Range，包括音视频拖动需要的分段响应。`.stream` 支持持续输出数据，取消请求或更换代理时会取消订阅；需要定位读取的流应自行根据请求头返回对应的 206 响应。

Android、iOS、macOS、Linux、OHOS 支持文件、字节及流响应。Windows 支持文件和字节响应，可通过 `controller.resourceCapabilities.supportsStreaming` 判断持续流能力；不支持的流响应会打印说明并使该资源加载失败，不会中断应用。Web 暂不支持，设置代理会打印说明，`getResourceUri` 返回 `null`。

移除代理可调用 `setResourceDelegate(null)`。资源 URL 由所属 controller 管理，销毁后失效；网页的 CORS、CSP 和媒体格式限制仍然适用。代理应校验请求，只返回应用允许网页读取的文件。

Linux 使用带随机访问路径的本机 HTTP 服务，以兼容 WebKitGTK 的音视频加载。服务只监听本机地址，随 controller 关闭；资源 URL 仅应交给获准读取资源的页面。

使用 `loadHtmlString` 时，可将资源 URL 的根路径作为 `baseUrl`，让页面与资源保持同源。

Android WebView 无法可靠处理 `If-Range` 不匹配时忽略 Range 的回退，且已知长度的资源不能超过 2,147,483,647 字节，遇到这些情况会打印说明并返回 501。前者可移除 Range 或 If-Range 后重试；更大的内容可用不指定长度的流顺序读取。

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
| Web | 非简单请求通过 `fetch`，需要服务端 CORS 允许；响应保留原始二进制字节，并使用 redirect 后的最终 URL。 |
| Windows/Linux/iOS/macOS | 支持 method、headers 和 body。 |

不支持的平台可用 app HTTP client 手动请求，再用 `loadHtmlString` 加载响应 HTML；但这不等价于浏览器原生导航，cookie、redirect、service worker 等语义会不同。

---
title: 错误与限制
description: 异常、不可用能力和平台边界。
---

## 通用校验

| API | 失败情况 |
| --- | --- |
| `loadRequest` | URI 没有 scheme 时抛 `ArgumentError`。 |
| `loadFlutterAsset` | key 为空或 asset 不存在时失败。 |
| `loadFile` | 文件不存在时失败；Web 不支持。 |
| `runJavaScriptReturningResult` | 返回 `null`、`undefined` 或不可序列化值时失败。 |
| `addJavaScriptChannel` | 重名 channel 会失败；部分平台还要求合法 JS identifier。 |
| `setCookie` | cookie name/domain/path 非法时失败。 |

## 不支持能力

| 平台 | API | 行为 |
| --- | --- | --- |
| Android | POST + 自定义 headers | Android `postUrl` 不支持。 |
| OHOS | POST + 自定义 headers | ArkWeb `postUrl` 不支持，抛 `UnsupportedError`。 |
| Web | `loadFile` | 抛 `UnsupportedError`。 |
| Web | `setUserAgent(nonNull)` | 打印一次说明并忽略，不抛异常。 |
| Web | SSL auth 决策 | 浏览器不暴露。 |
| Web | 跨域 JS/scroll | 浏览器同源策略阻止。 |
| macOS | 滚动位置、滚动回调、滚动条和 overscroll | fork 会打印缺少公开 WKWebView API 的说明并安全忽略；位置读取返回 `Offset.zero`。 |
| macOS | 受系统版本限制的 WebKit 属性 | 背景色需要 macOS 12，inspect 需要 macOS 13.3；更早系统打印说明并安全忽略。 |

## 请求加载限制

最大兼容建议：

- Android/OHOS 上需要自定义 headers 时优先使用 GET。
- 同时要求 Android/OHOS 时避免 POST 自定义 headers。
- Web 非简单请求必须由服务器正确配置 CORS。
- 手动 HTTP 请求再 `loadHtmlString` 只适合可控 HTML，不等同于浏览器导航。

## TLS

生产环境应取消证书错误：

```dart
onSslAuthError: (SslAuthError error) async {
  await error.cancel();
}
```

`proceed()` 只能用于内部测试、实验环境或完全受控网络。

## Web 隔离限制

Web 可直接控制同源内容，并通过来源校验消息桥控制插件管理的隔离 HTML。
直接跨域 iframe URL 仍无法检查或脚本控制。隔离 HTML 的 `confirm` 和
`prompt` 保留浏览器原生对话框，因为同步 API 无法等待异步跨 frame 回调。

## 运行时限制

| 平台 | 限制 |
| --- | --- |
| Windows | 必须安装 WebView2 Runtime。 |
| Linux | 必须安装 WebKitGTK 4.1；标准 Flutter runner 的 `GtkOverlay` 由插件自动安装。 |
| OHOS | 需要 OHOS Flutter SDK，ArkWeb 行为会随 API 版本变化。 |
| Android | 能力取决于系统 WebView/Chrome 版本。 |
| iOS/macOS | 能力取决于 OS 版本和应用 entitlement。 |

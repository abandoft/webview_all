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
| `callAsyncJavaScript` | function body 为空、参数名非法或为保留字、参数不能转换为 JSON、数值非有限值、timeout 非正数时抛 `ArgumentError`；Promise reject 和运行时错误产生 `JavaScriptExecutionException`，超时产生 `TimeoutException`。 |
| `addUserScript` | source 为空时抛 `ArgumentError`；注入阶段不可用时抛 `UnsupportedError`，应先检查 `isUserScriptInjectionSupported`。 |
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
| Web | 查询其他 origin 的 Cookie | 返回空列表并打印一次说明；浏览器 JavaScript 无法检查对应 cookie jar。 |
| Web | document-start 用户脚本 | iframe 无法保证早于页面脚本执行，能力检查返回 false。 |
| Web | `WebViewDataManager.clearAllWebsiteData` | 所有类型均返回不支持，宿主页无权清理任意 iframe storage 或 `HttpOnly` Cookie。 |
| OHOS | document-start 用户脚本 | 当前 ArkWeb bridge 没有确定性的 document-start 接口，能力检查返回 false。 |
| Android | 较旧系统 WebView 的 document-start 用户脚本 | 能力检查返回 false，应用可跳过注册并继续运行。 |
| Windows | 网站数据清理 | WebView2 profile API 不支持 session storage 和 service worker 注册；旧 Runtime 没有该接口时，所有类型均返回不支持。 |
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

Web 的 fetch-backed 导航最多保留 100 条类型化历史记录。前进、后退直接恢复
已保存的响应快照，不会重放修改型请求；只有显式调用 `reload()` 才重新请求。
导航代理拒绝跳转时不会改变当前历史位置。

## 网站数据清理结果

`clearAllWebsiteData` 使用结果对象区分完整清理、引擎不支持和原生执行失败。生产环境的注销流程应检查 `result.isComplete`，否则继续检查 `unsupportedDataTypes` 和 `failures`。该接口不会退而清理浏览记录、密码、自动填充或 profile 设置。

## 回调失败安全

Linux 的导航、HTTP 认证、TLS、权限和 JavaScript 对话框回调抛错时会采用安全的
拒绝或取消结果；native 待决请求也会在 30 秒后超时。错误以单行日志记录，既能
定位应用回调问题，又不会永久阻塞 WebKitGTK。

Windows 初始化或渲染失败会显示在组件内，可用 **Refresh** 重试。渲染失败后
会暂停自动重试，避免布局变化反复启动失败的捕获会话。**Install Webview2**
仅在错误为 `webview2_runtime_unavailable` 时显示，用于打开 WebView2 Runtime
官方下载页。重试前会释放未完成初始化留下的资源。

### Windows 初始化与渲染错误

| 错误码 | 阶段 | 含义 |
| --- | --- | --- |
| `webview2_runtime_unavailable` | `webview2_runtime` | 指定浏览器路径下没有兼容的 Runtime。 |
| `environment_creation_failed` | `webview2_environment` | WebView2 无法创建指定 profile 环境。 |
| `winrt_runtime_unavailable` / `winrt_initialization_failed` | `winrt_runtime` / `winrt_initialization` | 渲染器所需 Windows Runtime 无法加载或初始化。 |
| `graphics_capture_unavailable` / `graphics_capture_initialization_failed` | `graphics_capture` | 当前系统、设备、策略或会话不支持图形捕获。 |
| `dispatcher_queue_initialization_failed` | `dispatcher_queue` | 无法复用或创建 UI 线程的 Composition 队列。 |
| `d3d_device_creation_failed` | `d3d_device` | Direct3D 硬件设备和 WARP 软件回退均创建失败。 |
| `dxgi_device_initialization_failed` | `dxgi_device` | Direct3D 设备没有提供所需的 DXGI 接口。 |
| `d3d_interop_initialization_failed` | `d3d_interop` | Windows Runtime Direct3D 互操作初始化失败。 |
| `composition_initialization_failed` | `composition` | Windows Composition compositor 创建失败。 |
| `webview_creation_failed` | `webview2_controller` | 环境创建后 controller 创建失败。 |
| `graphics_capture_item_creation_failed` | `graphics_capture_item` | 无法将 Composition 画面连接到 Windows 图形捕获。 |
| `graphics_capture_size_unavailable` | `graphics_capture_size` | 捕获对象未能提供有效的画面尺寸。 |
| `graphics_capture_frame_pool_creation_failed` | `graphics_capture_frame_pool` | 无法创建 UI 线程帧池。 |
| `graphics_capture_frame_handler_registration_failed` | `graphics_capture_frame_handler` | 无法注册帧回调。 |
| `graphics_capture_session_creation_failed` / `graphics_capture_start_failed` | `graphics_capture_session` / `graphics_capture_start` | 无法创建或启动捕获会话。 |
| `graphics_capture_resize_failed` | `graphics_capture_resize` | 无法调整捕获帧池尺寸。 |
| `flutter_texture_registration_failed` | `flutter_texture_registration` | Flutter 未能注册原生纹理。 |
| `invalid_surface_size` / `webview_surface_update_failed` | `webview_surface_size` / `webview_surface` | 画面尺寸无效，或 WebView2 未能应用该尺寸。 |
| `webview_visibility_update_failed` | `webview_visibility` | WebView2 未能应用显示状态。 |
| `website_data_clearing_failed` | `webview2_data_window` / `webview2_data_controller` / `webview2_data_webview` / `webview2_profile` / `webview2_website_data` | 隔离窗口、临时 controller、WebView 访问、profile 查询或清理操作失败。 |

Windows 原生异常详情包含 `stage`、十六进制 `hresult`、有符号
`hresultValue`、`remoteSession`，并在检测成功时包含
`webView2RuntimeVersion`。配置相同的并发 `ensureEnvironment` 调用只执行一次
原生创建；配置冲突时不会替换正在创建或已生效的环境。

## 运行时限制

| 平台 | 限制 |
| --- | --- |
| Windows | 必须安装 WebView2 Runtime。 |
| Linux | 必须安装 WebKitGTK 4.1；标准 Flutter runner 的 `GtkOverlay` 由插件自动安装。 |
| OHOS | 需要 OHOS Flutter SDK，ArkWeb 行为会随 API 版本变化。 |
| Android | 能力取决于系统 WebView/Chrome 版本。 |
| iOS/macOS | 能力取决于 OS 版本和应用 entitlement。 |

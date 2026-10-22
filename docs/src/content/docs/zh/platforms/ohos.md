---
title: OHOS
description: ArkWeb 实现、API 和 HarmonyOS/OpenHarmony 限制。
---

OHOS 由 `webview_all_ohos` 提供，底层使用 ArkWeb。从 1.4.5 起，宿主应用的最低兼容版本必须设置为 API 22 或更新版本，详见[平台配置](/zh/getting-started/platform-setup/#ohos)。

| 项 | 值 |
| --- | --- |
| Controller | `OhosWebViewController` |
| Widget | `OhosWebViewWidget` |
| Delegate | `OhosNavigationDelegate` |
| Cookie manager | `OhosWebViewCookieManager` |
| 引擎 | ArkWeb |
| 最低目标 | OHOS API 22+ |

## 创建参数

```dart
final params = OhosWebViewControllerCreationParams(
  domStorageEnabled: true,
  javaScriptCanOpenWindowsAutomatically: true,
  supportMultipleWindows: true,
  loadWithOverviewMode: true,
  useWideViewPort: true,
  allowFileAccess: true,
  mixedContentMode: OhosMixedContentMode.neverAllow,
  mediaPlaybackRequiresUserGesture: false,
  supportZoom: true,
  textZoom: 100,
);
```

## 主要 API

| API | 作用 |
| --- | --- |
| `OhosWebViewController.enableDebugging` | 全局启用 ArkWeb 调试。 |
| `webViewIdentifier` | 原生 WebView 实例 ID。 |
| `setAllowFullScreenRotate` | 控制全屏旋转。 |
| `setDomStorageEnabled` | 控制 DOM storage。 |
| `setJavaScriptCanOpenWindowsAutomatically` | 控制 JavaScript 自动开窗。 |
| `setSupportMultipleWindows` | 保留兼容；页面请求的新窗口继续在当前 WebView 打开。 |
| `setLoadWithOverviewMode` / `setUseWideViewPort` | 视口相关设置。 |
| `setDisplayZoomControls` / `setBuiltInZoomControls` | 保留兼容，不保证提供原生缩放控件；页面缩放由 `setSupportZoom` 控制。 |
| `setAllowFileAccess` | file access。 |
| `setMixedContentMode` | 控制 HTTP/HTTPS 混合内容。 |
| `setSupportZoom` | 控制页面缩放，包括 Ctrl 配合加减键或鼠标滚轮缩放。 |
| `setMediaPlaybackRequiresUserGesture` | 控制媒体播放是否需要用户手势。 |
| `setTextZoom` | 设置文字缩放比例。 |
| `setOnShowFileSelector` | 文件选择。 |
| `setGeolocationPermissionsPromptCallbacks` | 定位提示。 |
| `setCustomWidgetCallbacks` | 全屏 custom view。 |

## 动态设置与滚动

JavaScript、DOM storage、file access、媒体手势策略、缩放、视口、背景色、文字大小和混合内容等设置，可在创建组件前配置，也可在 WebView 显示期间调整。

修改 User-Agent 或增删 JavaScript channel 不会强制刷新当前页面。User-Agent 修改影响后续请求；新增 channel 通常在下一个文档生效，当前页面需要使用时可显式刷新。

支持 `scrollTo` 和 `scrollBy`；滚动位置读取与回调以实际页面位置为准，包括页面边缘限制后的结果。

页面请求的新窗口沿用当前 WebView 打开。`supportMultipleWindows` 保留兼容，不创建独立窗口或标签页。`displayZoomControls` 和 `builtInZoomControls` 不保证提供原生缩放控件。通过 `supportZoom` 控制页面缩放，也包括 API 22+ 上按住 `Ctrl` 配合加减键或鼠标滚轮的缩放操作。

## 文档开始脚本

ArkWeb 会在页面 JavaScript 之前，按注册顺序执行用户脚本。可在 `WebViewWidget` 挂载前注册；开始导航前必须等待 `addUserScript` 完成，确保首个页面也能收到脚本。

注册和移除只影响后续文档及刷新，不会在当前文档补执行，也不会撤销已经运行的脚本效果。详见 [JavaScript 指南](/zh/guides/javascript/#document-start-用户脚本)。

导航会取消尚未完成的 `callAsyncJavaScript` 调用并返回 `JavaScriptExecutionException`，避免返回旧文档的结果。等待视图就绪的操作会在视图被移除时失败。

## 网站数据

`WebViewDataManager.clearAllWebsiteData()` 无需创建 WebView，即可清理 Cookie、所有 WebView 共享的资源缓存、local storage 和 WebSQL。session storage、IndexedDB、Cache Storage 和 service worker 注册返回不支持。应检查返回的清理结果，详见[网站数据清理](/zh/guides/cookies/#清理全部网站数据)。

## 混合内容

从 1.4.4 起，HTTPS 页面默认不能加载不安全的 HTTP 资源，建议将资源地址改为 HTTPS。如果需要兼容旧网页，可在加载页面前，通过创建参数或 `setMixedContentMode` 显式选择 `OhosMixedContentMode.compatibilityMode` 或 `OhosMixedContentMode.alwaysAllow`。修改策略不会移除已经加载的资源，也不影响直接打开 HTTP 页面。

## `loadRequest`

| 请求 | 支持 |
| --- | --- |
| GET 无 headers | 支持。 |
| GET 自定义 headers | 支持。 |
| POST 无自定义 headers | 支持。 |
| POST 自定义 headers | 不支持，抛 `UnsupportedError`。 |

ArkWeb `postUrl` 只接收 URL 和 body，不接收 headers，因此库明确失败。

## 权限和 Cookie

OHOS 支持 camera、microphone，并扩展 `midiSysex`、`protectedMediaId`。

```dart
await (WebViewCookieManager().platform as OhosWebViewCookieManager)
    .setAcceptThirdPartyCookies(
  controller.platform as OhosWebViewController,
  true,
);
```

## WebAuthn 与 Passkey

当前支持的 ArkWeb SDK 公开接口没有明确的 WebAuthn/Passkey 启用或代理能力。
`webview_all_ohos` 因此不声明支持该功能，也不增加没有原生实现的 Android 式开关。
应用需要在每个目标 API 级别和设备上验证标准网页能力，保留其他认证方式；
业务必须使用 Passkey 时，应转交给已确认支持的外部浏览器。插件不注入 JS 凭据模拟。

## 限制

- WebView 权限批准不等于系统权限，宿主应用仍需声明并获取权限。
- ArkWeb 公开宿主 API 不保证 WebAuthn/Passkey，不能只根据其浏览器引擎推断可用。
- ArkWeb 行为可能随 HarmonyOS/OpenHarmony 版本变化，尤其是媒体、文件选择和权限。

## Toolchain 隔离

不要在同一个 package 目录交替运行 stock Flutter 和 OHOS Flutter SDK：两者都会
写 `.dart_tool/package_config.json`，但 SDK package 集合不兼容。仓库脚本会
把包含未提交改动的当前代码复制到临时目录后再运行 OHOS 命令：

```sh
OHOS_FLUTTER=/absolute/path/to/ohos/flutter \
  ./tool/run_ohos_flutter.sh -- analyze

OHOS_FLUTTER=/absolute/path/to/ohos/flutter \
  ./tool/run_ohos_flutter.sh --workdir webview_all/example -- build hap
```

脚本要求显式的绝对 SDK 路径，复制时排除 cache/generated 目录，结束后始终删除
临时工作区，因此真实仓库的 `.dart_tool` 不会被污染。

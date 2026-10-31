---
title: Linux
description: WebKitGTK 实现、自动 GtkOverlay 集成、API 和限制。
---

Linux 由 `webview_all_linux` 提供，底层使用 WebKitGTK。

| 项 | 值 |
| --- | --- |
| Controller | `LinuxWebViewController` |
| Widget | `LinuxWebViewWidget` |
| Delegate | `LinuxNavigationDelegate` |
| Cookie manager | `LinuxWebViewCookieManager` |
| 引擎 | WebKitGTK |
| 系统依赖 | `webkit2gtk-4.1` |

## Runner 集成

Linux WebView 是 native GTK widget。插件会在标准 Flutter runner realize
`FlView` 前自动安装所需的 `GtkOverlay`，应用无需修改 runner。

## 网站数据目录

从 1.4.7 起，可在首次创建 WebView、操作 Cookie 或清理网站数据前配置共享环境。
应先完成 `WidgetsFlutterBinding.ensureInitialized()`：

```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:webview_all_linux/webview_all_linux.dart';

final dataDirectory = await getApplicationSupportDirectory();
final cacheDirectory = await getApplicationCacheDirectory();
await LinuxWebViewController.ensureEnvironment(
  userDataPath: p.join(dataDirectory.path, 'WebKit'),
  cachePath: p.join(cacheDirectory.path, 'WebKit'),
);
```

普通 WebView、Cookie 和网站数据清理共用该环境。`userDataPath` 指定持久化网站
数据目录，`cachePath` 指定缓存目录。两项都为 `null` 时，复用已选环境；尚未选择
时沿用 WebKitGTK 默认目录。相对路径按当前工作目录解析。

相同配置可重复调用。显式传参代表完整配置，其中省略或空字符串路径表示平台默认
目录；配置不一致时返回 `environment_configuration_conflict`，已选环境不能更换
目录。所选环境会保持到应用进程结束，关闭全部 WebView 也不会重置目录。也可使用
`initializeEnvironment` 进行严格的一次性初始化。

配置后，默认 `WebViewCookieManager` 和 `WebViewDataManager` 自动使用所选环境，
无需重复传路径。如果首次操作就是清理，也可通过
`LinuxWebViewDataManagerCreationParams(userDataPath: ..., cachePath: ...)`
指定目录。

切换目录不会自动迁移旧网站数据。应用后续启动应继续使用相同路径，才能访问该
数据。Cookie 的有效期和持久化行为保持原样。

## 无痕会话

创建 controller 时设置 `LinuxWebViewControllerCreationParams(incognito: true)`，
即可使用独立的临时 WebKitGTK context。每个无痕 controller 的 Cookie 和网站存储
彼此隔离，也不与普通 WebView 共用；数据不会写入共享配置的持久化目录。

共享 Cookie 和网站数据管理器不访问这些会话。创建无痕 controller 不会选择或锁定
共享环境的数据目录。会话结束时调用 controller 的 `dispose()`。

## 创建参数

```dart
final params = const LinuxWebViewControllerCreationParams(
  incognito: false,
  developerExtrasEnabled: true,
  downloadsEnabled: false,
  mediaPlaybackRequiresUserGesture: false,
  pageCacheEnabled: true,
  allowFileAccessFromFileUrls: false,
  allowUniversalAccessFromFileUrls: false,
  zoomFactor: 1.0,
);
```

`incognito` 默认为 `false`；其他字段可为 `null`，表示保留 WebKitGTK 默认值。

下载默认允许。可在创建时设置 `downloadsEnabled: false`，或在加载内容前等待
`setDownloadsEnabled(false)` 完成，取消新下载并阻止保存文件。已开始的下载和
其他 WebView 不受影响。允许下载时使用默认下载目录，并以不覆盖方式安全保存。
从 1.4.8 起，可通过[下载代理](/webview_all/zh/guides/downloads/)选择目标文件、
获取进度及结果；插件不会创建保存窗口。

## 主要 API

| API | 作用 |
| --- | --- |
| `setDeveloperExtrasEnabled` | 启用开发者功能。 |
| `openDevTools` | 打开 Web Inspector。 |
| `setDownloadsEnabled` | 控制此 WebView 是否允许新下载，默认允许。 |
| `setJavaScriptCanOpenWindowsAutomatically` | 控制 JS popup。 |
| `setMediaPlaybackRequiresUserGesture` | 控制媒体自动播放。 |
| `setMediaPlaybackAllowsInline` | 控制内联媒体播放。 |
| `setPageCacheEnabled` | 控制 page cache。 |
| `setAllowFileAccessFromFileUrls` | 允许 file 页面读其他 file URL。 |
| `setAllowUniversalAccessFromFileUrls` | 允许 file 页面访问所有 origin。 |
| `setDefaultFontSize` / `setMinimumFontSize` | 字号设置。 |
| `setZoomFactor` | 页面缩放。 |
| `dispose` | 可选的 Linux 平台专用提前释放入口。 |

常规清理也是自动的：Linux controller 不再可达时，finalizer 会释放 native
WebView。公共 `WebViewController` 没有增加 `dispose()`，组件移出树也不会让仍
可能复用的 controller 失效。

通用 `enableZoom(false)` 会禁用插件可控制的 WebKitGTK 缩放手势，包括
Ctrl+鼠标滚轮和 Ctrl+`+`/`-`/`0`；普通滚动与键盘输入不受影响。

## 事件覆盖

Linux 通过 event channel 上报 URL、页面生命周期、进度、history、title、资源错误、HTTP 错误、JS channel、console、scroll、导航请求、HTTP auth、SSL auth、权限请求和 JS dialog。

所有等待 Dart 决策的 native request 都有 30 秒期限。如果应用没有完成请求或
event channel 关闭，导航会拒绝，认证/dialog/TLS 会取消，权限会拒绝。应用回调
抛异常时会打印单行信息并使用相同的安全默认值，不会让 WebKitGTK 一直阻塞。

## WebAuthn 与 Passkey

WebKitGTK 的 GTK port 目前还没有 WebAuthn 支持，上游工作仍记录在
[WebKit bug 205350](https://bugs.webkit.org/show_bug.cgi?id=205350)。因此
`webview_all_linux` 不声明支持 Passkey，也不暴露底层无法执行的虚假开关。
必须使用 Passkey 的 Linux 应用应将认证流程交给支持该能力的外部浏览器，
或保留其他认证方式。插件不使用 JS 凭据模拟，因为它无法保证 WebAuthn 的
origin 与 authenticator 安全语义。

## 限制

- WebView 是 GTK 原生 widget，而非 Flutter texture。它会跟随 Flutter
  的逻辑位置和尺寸，并在 Flutter 视口边界裁剪；但 `GtkOverlay` 无法复现任意
  Flutter 图层穿插和裁剪形状。
- 支持系统 HiDPI 和通过 `ViewConfiguration` 配置的应用界面缩放。
- 组件变换支持平移；缩放、旋转、倾斜、透视和镜像无法由 GTK 原生子组件准确表示。
  遇到这些变换时，插件会隐藏 WebView 并打印限制说明，避免留下视觉错位但仍可交互
  的原生区域。
- 本地文件必须使用绝对路径，并会在加载前规范化；Flutter asset 中的路径穿越、绝对路径和逃出 asset bundle 的符号链接会被拒绝。
- 不可信本地文件不要启用 universal file URL access。
- 不同发行版 WebKitGTK 版本差异明显，媒体、权限和 dialog 需要在目标发行版验证。
- WebAuthn/Passkey 需要等待 WebKitGTK GTK port 实现平台 authenticator 集成。
- frame 更新是异步且错误隔离的，组件销毁阶段不会泄漏未处理异常。

## 1.3.10

* 修复部分设备上的 Windows 渲染失败，提升帧捕获和尺寸变化时的稳定性。
* 避免 Windows 渲染错误重复输出，并在渲染需要恢复时提供 **Refresh** 操作。
* Windows 清理网站数据时不再启动图形捕获或创建 Flutter 纹理。

## 1.3.9

* 修复部分 Windows 桌面应用中 WebView2 无法启动的问题。
* 提升 Windows 初始化、重试和多 WebView 使用时的稳定性。
* 优化启动错误提示，缺少 WebView2 Runtime 时可直接前往安装。

## 1.3.8

* 新增可等待 Promise 的 `callAsyncJavaScript`，支持结构化参数、超时、一致的 JSON 结果和类型明确的 JavaScript 错误。
* Android、iOS、macOS、Windows 和 Linux 新增可检测能力、可安全移除的 document-start 用户脚本。
* 新增 `WebViewDataManager.clearAllWebsiteData()`，注销时无需 controller 即可清理网站数据，并区分已清理、不支持和失败的数据类型。
* 新增 `OffscreenWebViewSession`，可在 Android、iOS、macOS、Windows 和 Linux 确定性释放离屏 controller。
* Windows 共享 WebView2 环境配置支持安全复用，网站数据清理也可传入相同配置。

## 1.3.7

* Android 新增 WebAuthn（Passkey）配置，可通过 `setWebAuthenticationSupport` 为已关联应用或具备资格的浏览器应用启用。
* 修复 Windows 应用窗口最小化，或 WebView 被隐藏、移除后，WebView2 仍可能拦截桌面点击的问题。
* 完善 Windows WebView 在应用前后台切换、WebView 显隐、窗口移动、显示器及缩放变化时的显示和渲染恢复。
* 新增 `WindowsWebViewController.dispose()`，可确定性释放 WebView2 资源，并支持初始化期间安全释放和自动兜底清理。

## 1.3.6

* 修复 Linux 系统输入路由，使 WebKitGTK 可接收鼠标、键盘和滚轮输入，同时不再导致 Flutter 控件失去交互或点击穿透应用窗口。
* 完善 Linux 原生 WebView 在 HiDPI、视口边界、controller 切换、应用前后台切换，以及组件被隐藏或移出可见区域时的位置与显示状态。
* 完善 Linux `GtkOverlay` 的布局和资源清理，避免较早的位置更新覆盖最新状态；遇到 GTK 无法准确显示的缩放、旋转等变换时会安全隐藏 WebView。

## 1.3.5

* 修改文档细节。

## 1.3.4

* Linux 媒体手势设置同时应用于新版 WebKitGTK 自动播放策略，页面请求的新窗口可稳定在当前 WebView 中打开。
* Windows 导航策略覆盖页面触发的主 frame 加载和同窗口 popup，同时保留 controller 请求的 method、headers 和 body。
* Windows 本地文件和 asset 使用每个 controller 独立的私有 host，拒绝不安全路径并清理过期映射，同时提高 WebView2 决策和下载回调的可靠性。
* Web 保留响应的原始二进制字节和 redirect 后的最终 URL，并按条目数与总大小共同限制响应 history。
* 补齐 OHOS bridge 对象释放确认，过期的权限、认证、对话框和自定义视图回调会安全结束，不再泄漏或崩溃。
* 隔离 Android 与 OHOS 导航回调失败，加强各平台 JavaScript channel 名称安全，并拒绝 Linux 不安全的文件和 asset 路径。
* Windows 原生构建保持使用 C++17，不再要求应用支持 C++20 或旧式协程参数。

## 1.3.3

* 避免 Windows WebView2 在应用回调失败或未完成时长期阻塞，并使用安全默认行为保持 WebView 运行。
* 修复 Linux `WebViewWidget` 切换 controller 时原生视图位置和可见性不同步的问题。
* 修复 WKWebView JavaScript channel 的清理顺序，并安全处理受系统版本限制的配置。
* 隔离 Web 和 OHOS 的关键应用回调失败，避免未捕获异常中断 WebView 运行。

## 1.3.2

* 完善 Windows WebView2 的启动恢复和资源清理，初始化失败后可安全重试，并避免过期的 resize 更新覆盖当前状态。
* Windows 启动失败时显示居中错误界面，**Install Webview2** 跳转 Microsoft 官方下载页，**Refresh** 重新尝试初始化。
* 校验 Web iframe 属性名，并禁止覆盖由控制器管理的 `id`、`src` 和 `srcdoc` 属性。
* 完善 Web 导航历史，前进和后退可正确恢复 URL、HTML 或请求响应，不会重放 POST，显式 reload 仍会重新获取内容。
* 避免较早完成的 Web 并发请求覆盖较新的导航，并将控制器管理的历史记录限制为最多 100 条。
* 完善 Web Cookie 的安全性和结果准确性，拒绝外域写入、限制跨上下文读取、更完整地清理可见 Cookie path，并容忍错误的编码值。
* 避免 Linux 导航、认证、TLS、权限和 JavaScript 对话框在应用回调失败或未完成时永久阻塞 WebView。
* 完善 Android Cookie 解析，支持编码后的名称、包含 `=` 的值和错误的编码值，完善 Android 宿主代码访问原生 WebView 的方式，并兼容传统 Kotlin 与 Built-in Kotlin 构建。
* 完善 iOS 应用终止、scene 断开或 Flutter engine detach 时的 WebView 资源清理，并支持通过 `FlutterPluginRegistrar` 查询原生 `WKWebView`。
* OHOS Cookie 读取支持编码后的名称并可容忍错误的编码值，同时新增隔离运行 OHOS Flutter 命令的辅助脚本，避免改变 stock Flutter 的 package 配置。
* Web 实现的 `web` 依赖更新至 1.1.1。

## 1.3.1

* macOS 能力改为按系统版本判断：可用时使用原生背景色和 magnification API，旧系统回退到兼容的 JavaScript preferences；没有公开 WebKit API 的能力打印说明并安全忽略。
* Web 的 fetch-backed HTML 与严格 sandbox HTML 保持不透明 origin，通过校验消息来源且绑定导航生命周期的隔离 bridge 恢复受支持的控制器能力，并强化 Content-Type 解码和同步对话框降级。
* Linux `enableZoom` 改为实际生效；Android 无法保留自定义 header 的 POST 会明确拒绝，未知的新文件选择模式安全降级。
* OHOS 本地加载会先完成 file access 设置，ArkWeb 原生加载失败会向 Dart 传播，不再误报成功。
* Windows WebView2 environment、纹理和帧捕获初始化失败会转为可诊断的平台错误，不再触发原生断言崩溃。

## 1.3.0

* 使用弱引用回调和 finalizer 自动清理，使内置 Windows、Linux 和 Web controller 变为不可达后释放平台资源；OHOS 继续使用已有的 instance manager 自动生命周期。
* Linux 插件会自动安装 GTK overlay，无需再修改 runner 源码。

## 1.2.1

* 在 macOS 上忽略 `setBackgroundColor` 并打印日志，避免 WKWebView `opaque` / `backgroundColor` 未实现导致应用异常。
* 完善 `examples/platform` 的Linux 平台，在创建 WebKitGTK 视图前先将 Flutter view 挂到 `GtkOverlay`。

## 1.2.0

* 补齐各平台包对 `webview_flutter_platform_interface` 的覆盖。
* 新增 Linux WebKitGTK 平台专用 controller 创建参数与运行时设置，覆盖 developer extras、JavaScript 自动开窗、媒体播放、page cache、file URL 访问、文本缩放/字体大小、页面缩放与 DevTools 打开能力。
* 新增 Web iframe 平台专用创建参数与运行时属性设置，覆盖 `allow`、`sandbox`、`referrerpolicy` 与自定义 iframe 属性，并在 JavaScript mode 切换时保留用户自定义 sandbox。
* 新增 OHOS ArkWeb 平台专用 controller 创建参数与运行时 WebSettings setter，覆盖 DOM storage、JavaScript 自动开窗、多窗口、viewport/overview、缩放控件、file access、媒体手势策略、support zoom、text zoom 与全屏旋转。
* 为各平台控制器补齐显式 `loadFileWithParams` override。
* 当原生平台未提供证书数据时，平台 SSL 认证错误的 certificate 统一返回 `null`。
* 在转发到平台 Cookie 存储前统一校验通用 WebView Cookie。
* 避免 OHOS 在导航代理放行子 frame 请求后将其重放为主 frame 加载。
* HTTP 状态错误回调会在可用时带上平台专用的请求元数据与响应详情。
* OHOS JavaScript 执行结果改为优先按 JSON 解码，使字符串、数组、对象、布尔值和数字尽可能与其他平台的结构化返回行为一致。
* OHOS POST `loadRequest` 携带自定义请求头时改为明确失败，避免静默丢弃请求头，并记录 ArkWeb 的底层限制。
* Windows 遇到无法映射到通用资源类型的 WebView2 权限请求时改用默认决策，避免向应用暴露空资源请求。
* Linux 权限请求如果不包含任何可识别资源类型，将直接拒绝原生请求，避免向应用暴露空资源请求。
* 为主包封装补充 `WebViewController`、`NavigationDelegate`、权限请求与 `WebViewWidget` 的转发测试。
* 为主包和各平台包增加共享 analyzer lint 配置。
* 将 `examples/platform` 纳入本地验证，并审计其 path 包 lockfile 版本与工作区发布版本一致。
* 将示例 Android 工程更新到当前 Flutter Gradle 模板形态，app 模块不再直接应用 Kotlin Gradle 插件。
* 将示例 iOS 与 macOS 工程迁移为仅使用 Swift Package Manager，并移除模板 CocoaPods 集成。
* 恢复示例应用的 `cupertino_icons` 依赖，确保 Web release 构建包含所引用的图标字体。
* 补充 Linux 权限请求 grant/deny 分发与 Web user-agent reset 行为的回归测试。
* 补齐 OHOS 权限请求 grant 覆盖：支持 camera、microphone、MIDI sysex 与 protected media 资源，并安全拒绝未知资源。
* 移除 Web JavaScript dialog bridge 中触发 Flutter Web wasm dry-run 警告的运行时类型检查，并补充多 WebView dialog bridge 覆盖。
* 为 Windows 与 Linux 补齐 `loadRequest` 的请求 body/header 处理与 HTTP 状态错误回调覆盖。
* 为 Windows 与 Linux 增加原生 local storage 清理能力。
* 补齐 OHOS HTTP error 与 SSL auth 回调桥接。
* 加强 Web 实现：在浏览器允许的范围内补齐同源 JavaScript 执行、JavaScript channel、console 转发、alert/confirm/prompt 转发、滚动、滚动条、over-scroll、JavaScript mode、zoom 与权限请求覆盖。
* 新增显式 Web `PlatformSslAuthError` 实现，将可恢复证书决策标记为不支持，而不是让平台接口方法保持缺失。
* 新增 `WebWebViewWidgetCreationParams`，使 Web 平台与其他 federated 包的平台专用 widget creation params 模式保持一致。

## 1.1.2

* 将 `WebViewCookieManager.getCookies({required Uri domain})` 与上游 `webview_flutter` 公共 API 对齐。

## 1.1.1

* 示例改为使用 `abutil` 包进行平台判断。
* 简化示例应用中的 OHOS 与 Web 平台分支。
* 将平台包的许可证文件同步为主包许可证文本。

## 1.1.0

* 新增 OpenHarmony 平台实现支持。
* 完善 cookie API 覆盖：
  * 在主插件封装层新增通用 `WebViewCookieManager.getCookies({required Uri domain})` API。
  * 为各 federated 平台包实现并验证跨平台 cookie 读取能力。
  * 为 Windows WebView2 增加包含完整 cookie 元数据与删除流程的平台专用 API。
* 加强 Web 平台实现：
  * 为 `loadHtmlString` 与基于 XHR 的 `loadRequest` 保留逻辑 `currentUrl()`，避免向用户暴露内部 `data:` iframe URL。
  * 按 Flutter Web 生成的 `assets/` 目录解析资源，并正确编码资源路径片段。
  * 基于 XHR 的加载失败会通过 `onWebResourceError` 上报，且不再把不支持的自定义 user agent 覆盖误报为已生效。
  * 写入 `document.cookie` 前校验并编码浏览器可见 cookie，在文档中明确 iframe 与浏览器 cookie 限制。
* 完善 Linux 平台实现：
  * 修复 native WebView 可见性同步问题，稳定的 Flutter 帧不再把 GTK/WebKit 视图折叠为 `0x0`。
  * 加强 Linux frame、cookie 与 JavaScript channel 的入参校验，避免非法 native 状态和不安全脚本注入。
* 各平台子插件的更新日志统一为 `webview_all` 的更新内容。
* 统一主插件与各平台子插件的版本号。

## 1.0.3

* 文档更新。
* 依赖更新。

## 1.0.2

* 文档更新。

## 1.0.1

* 文档更新。

## 1.0.0

* 新增 Linux 支持。

## 0.9.3

* 问题修复。

## 0.9.2

* 问题修复。

## 0.9.1

* 重构：包含破坏性变更。

## 0.5.3

* 更新依赖。
  * 修复 MacOS 上 `opaque` 未实现导致的问题。

## 0.5.2

* 文档更新。

## 0.5.1

* 大版本依赖更新。
* 问题修复。

## 0.4.5

* 依赖更新。
* 问题修复。

## 0.4.3

* 依赖更新。

## 0.4.1

* 重构。

## 0.3.7

* 依赖更新。

## 0.3.6

* 文档更新。

## 0.3.5

* 文档更新。

## 0.3.4

* 文档更新。

## 0.3.3

* 文档更新。

## 0.3.1

* 修复 Web 相关问题。

## 0.2.4

* 依赖更新。

## 0.2.3

* 文档更新。

## 0.2.2

* 修复 Web 相关问题。

## 0.2.1

* 初步运行成功。

## 0.1.3

* 问题修复。

## 0.1.2

* 问题修复。

## 0.1.1

* 故事开始。

---
title: Profile 与页面工具
description: 共享指定的网站数据、恢复原生导航状态、导出页面及打印。
---

## Profile 与关联页面

`WebViewProfile` 管理一组网站数据，并创建共享该数据的 `WebViewSession`。
不指定名称时默认使用 `isolatedIncognito`；指定名称时默认使用持久化的 `shared`
存储。不支持所请求能力时打印原因并返回 `null`。

```dart
final profile = await WebViewProfile.create(name: 'account_1');
if (profile == null) return;
final first = await profile.createSession();
final second = await profile.createSession();
// 两个页面共享该 Profile 的 Cookie 和持久化网站数据。
// 使用各自的 session.controller 创建 WebViewWidget。
await profile.close(); // 停止创建页面，已有页面仍可使用。
// 先移除组件，再关闭会话。
await first?.close();
await second?.close();
await profile.whenReleased;
```

命名 Profile 需要 Android 运行时的 `MULTI_PROFILE` 能力、iOS 17 / macOS 14、
支持 Profile 选项的 WebView2，或 Linux WebKitGTK。名称为 1–64 个 ASCII 字母、数字、
下划线或连字符；使用相同名称可重新打开持久化数据。关闭 Profile 不会删除这些数据，
需要通过其管理器主动清理。OHOS 和 Web 不提供独立的命名存储。

Apple、Windows、Linux 的私密 Profile 在明确关联的页面间共享一组临时存储，
关闭其中一个页面不会清空其他页面的数据。Android 的 `incognito` 仍是有限无痕，
会共享普通数据；仅在接受该行为时明确传入 `mode: WebViewSessionMode.incognito`。
OHOS 的无痕页面共享引擎的私密存储。以 `getCapabilities()` 的结果为准。
使用 `request.createController()` 创建的原生子窗口沿用父页面的 Profile，
子窗口的界面和关闭仍由应用负责。

## 管理已保存的 Profile

```dart
final manager = WebViewProfileManager();
final profiles = await manager.listProfiles();
final result = await manager.requestDeletion('account_1');
if (result.isDeleted) {
  // 原生数据区已经删除。
}
```

仅列出和删除插件创建的**命名持久 Profile**，不包含默认数据区和私密会话。删除前先关闭
相关会话、移除网页组件并释放导航状态。删除会使旧 Profile 的 manager 和配置句柄失效，
再次使用时应重新创建。

检查 `result.status`：`busy` 表示原生引用仍占用数据区，`pending` 表示删除仍在执行或等待磁盘
清理，`requiresRestart` 表示需在应用下次启动、加载该 Profile 前重试。Android 无法
删除当前进程已经加载的 Profile；Windows 要等待浏览器进程退出才清理文件，期间不能重用
该名称；Windows 的名称不区分大小写。Apple 需要 iOS 17／macOS 14，WebKit 释放原生引用期间可能返回 `busy`。
Linux 会检查网页、导航状态及其他进程的占用。`unknown` 不代表删除没有发生，应先重新查询。
不支持的平台会打印说明并返回 `null` 或 `unsupported`，不会改为清理默认数据区。

## 原生导航状态

```dart
final state = await controller.saveNavigationState();
if (state != null) {
  final target = await profile.createSession(); // 同一存储中的新页面。
  final accepted = await target?.controller.restoreNavigationState(state);
  // 恢复后通过导航回调等待页面就绪。
  await state.dispose();
}
await controller.clearNavigationHistory();
```

状态是仅存在于内存的原生句柄，不能序列化，只能在同一个 Flutter 引擎内、兼容的数据存储中恢复。
Android、Apple、Linux 使用原生状态接口；OHOS 保存有大小限制的原生状态。
Windows、Web 不提供该恢复能力。引擎状态不保证保存 JavaScript 内存或恢复正在进行的请求。
及时释放不用的句柄，每个引擎最多保留 16 份。Android、Windows、OHOS 支持清理历史，
不支持的平台打印说明并返回 `false`，不会通过重新加载当前 URL 模拟清理。

Android 的 `restoreState` 必须在新的 WebView 开始导航前调用。检查 `navigationStateRequiresNewView`，并在同一个 Profile 创建新的关联会话；向已导航的页面恢复会打印原因并返回 `false`，保留当前页面。

## 截图、PDF 与归档

```dart
final png = await controller.takeScreenshot(
  options: const WebViewScreenshotOptions(
    region: Rect.fromLTWH(0, 0, 200, 100), scale: 2,
  ),
);
final pdf = await controller.createPdf(
  options: const WebViewPdfOptions(
    paperSize: Size(595.28, 841.89),
    margins: EdgeInsets.all(28.35), landscape: false,
  ),
);
final archive = await controller.createArchive(format: WebViewArchiveFormat.mhtml);
```

截图区域使用**原始 PNG 的像素坐标**，不是 Flutter 逻辑像素。截图不包含 Flutter 覆盖层，
受保护视频可能不在截图中。原图和输出均限制为约 1600 万像素，参数无效或区域越界时打印原因并返回 `null`。
Windows、Linux 可使用 `WebViewScreenshotOptions(fullDocument: true)` 获取原生整页 PNG，
不滚动页面、不拼接截图。先查询 `fullDocumentScreenshot`，其他平台会打印说明并返回 `null`。
懒加载或受保护内容可能不会包含在结果中，仍受截图像素和输出大小限制。

PDF 纸张和边距使用**点（每英寸 72 点）**；不传 PDF 选项时沿用引擎默认布局。
Android 提供系统打印，不直接返回 PDF 字节；OHOS 支持 WebView 表面截图及 ArkWeb PDF 导出。
Web 不支持截图和 PDF 导出。

通过 `getBrowserCapabilities()` 选择归档格式：Apple 支持 WebArchive，Android、Windows、
Linux、OHOS 支持 MHTML。归档是引擎页面快照，不保证整个网页应用离线可用，也不保存登录会话。
导出文件限制为 64 MiB，由应用选择保存或分享的位置。Linux PDF 导出需要 GTK 的 Print to File 后端。

macOS 的自定义 PDF 导出保留引擎矢量页面布局，按可打印宽度缩放并分页，不会按纸张宽度重新排版 HTML。

## 系统打印

```dart
final job = await controller.printPage(jobName: '收据');
if (job != null) {
  final state = await job.getState();
  if (job.canCancel) await job.cancel();
  await job.dispose();
}
```

打印使用系统界面。Android 需要 Activity，其他原生页面需要挂载到窗口。
Android、Apple、Linux、OHOS 提供可用的任务事件；Windows 报告已展示原生打印界面，
同源 Web 仅返回 `requested`，因为浏览器不能确认打印界面是否真的打开。
任务完成表示原生处理或送入打印队列完成，不代表纸张已实际打印。macOS 无法区分取消和所有打印错误，
因此返回 `cancelledOrFailed`。Android、iOS 支持主动取消。释放句柄不会取消系统拥有的打印任务，
也不应假设用户会在固定时间内关闭打印面板。

Android 取消打印任务不保证同时关闭系统打印 Activity，用户可能仍需关闭打印面板。

`jobName` 在原生支持时用作任务名称；Windows、Linux、Web 沿用网页或浏览器提供的标题。

## 网站数据范围

```dart
final manager = session.dataManager;
final caps = await manager.getCapabilities();
final origin = WebViewDataTarget.origin(Uri.parse('https://example.com'));
final records = await manager.getWebsiteDataRecords(target: origin);
final result = await manager.clearWebsiteDataFor(
  origin, dataTypes: {WebViewDataType.localStorage},
);
// 检查 result.clearedDataTypes、unsupportedDataTypes 和 failures。
```

范围明确区分：Windows 使用精确的 HTTP(S) **origin**；Apple、Linux 使用引擎返回的
**domain** 记录；较新的 Android WebStorage 按可注册 **site** 清理整组数据。
不会把只要求清理一个 origin 的请求扩大到整个域名或站点。使用原生记录返回的 target，
并通过 `scopedClearingGroups` 选择可用的数据类别组合。Apple/Linux 的记录名不一定是可注册域名。
Windows 查询必须指定 target，返回原生配额估算，不能视为所有存储类别的完整清单。
Android 不能单独清理站点组内的一个类别，必须请求完整的受支持组合。
OHOS、Web 没有适合该能力的现代精细存储接口。默认管理器操作普通数据，会话及 Profile
管理器操作所选存储，清理会影响共享该存储的所有页面。

## 原生菜单与媒体

`setContextMenuEnabled` 控制 Windows、Linux、macOS 的原生菜单。
Android/iOS 不通过拦截所有长按来模拟该功能，以免同时影响文字选择。
Windows、Linux、OHOS 支持 `setAudioMuted`；Apple、OHOS 支持 `pauseMedia`；
Apple 还支持 `setMediaPlaybackSuspended`。这些操作使用原生引擎接口，
不会通过主文档 JavaScript 假装能控制所有跨域 frame。
通过 `getBrowserCapabilities()` 的各项标志查询，不支持时打印说明并返回 `false`。

## 浏览器页面与认证

应用可使用 `WebViewWidget`、导航及标题回调、拥有生命周期的会话构建浏览器页面，
自行决定工具栏、标签、地址栏与路由。打开系统浏览器、Custom Tabs 或 Safari 界面时，
使用专门的 URL 打开方案；这些窗口不提供本插件 controller 的脚本、Profile 或资源代理。

OAuth 系统认证属于独立会话，应使用处理系统回调、取消和 PKCE 的认证库。
Apple 提供 [ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession)，
Android 使用 Custom Tabs 等基于浏览器的流程。嵌入式 WebView 的无痕模式不等同于
系统浏览器的单点登录能力，也不具备系统认证会话的回调保障。

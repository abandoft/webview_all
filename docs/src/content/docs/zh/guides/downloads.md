---
title: 下载
description: 接管 WebView 下载，由应用决定保存交互。
---

从 1.4.8 起，可通过 `WebViewController.setDownloadDelegate` 独立接管下载。
插件不创建下载窗口或后台下载管理器，由应用决定是否询问用户以及保存位置。

```dart
await controller.setDownloadDelegate(
  WebViewDownloadDelegate(
    onDownloadRequest: (request) async {
      if (!request.supportedActions.contains(WebViewDownloadAction.saveToFile)) {
        return const WebViewDownloadDecision.cancel();
      }
      // 应用代码：使用自己的界面或文件选择组件。
      final path = await chooseDownloadPath(request.suggestedFilename);
      return path == null
          ? const WebViewDownloadDecision.cancel()
          : WebViewDownloadDecision.saveToFile(path);
    },
    onDownloadProgress: (progress) {
      debugPrint('${progress.id}: ${progress.bytesReceived} bytes');
    },
    onDownloadResult: (result) {
      debugPrint('${result.id}: ${result.status}, ${result.path}');
    },
  ),
);
```

上述 `chooseDownloadPath` 由应用提供。文件目标必须是已存在、应用可写目录中的绝对路径，
建议文件名属于不可信元数据，应由应用界面校验。
不会覆盖已有文件。下载文件与 `userDataPath`、缓存目录、网站数据清理相互独立。

Linux 的原生 WebView 会覆盖普通 Flutter 浮层。保存确认可放在不含 WebView 的
不透明页面路由中，或使用应用提供的原生文件选择器。

| 决策 | 含义 |
| --- | --- |
| `cancel()` | 拒绝本次下载。 |
| `platformDefault()` | 使用当前平台支持的默认处理。 |
| `saveToFile(path)` | 在支持时，将原生下载保存到指定文件。 |
| `handledExternally()` | 应用已接管，不再同时运行旧下载或导航处理。 |

请检查 `request.supportedActions`；不支持的决策会失败，不会被静默替换。
取不到的元数据为 `null`。决策等待上限为 30 秒；异常、超时或无效决策不会触发
重新请求 URL。下载进度独立于页面 `onProgress`。
`handedOff` 只表示已交给其他方处理，**不代表文件已保存**。

## 平台行为

| 平台 | 行为 |
| --- | --- |
| Windows | 保留原 WebView2 下载任务，支持文件目标、进度及结果。无代理时继续自动保存到默认下载目录。离屏 WebView 的默认下载面板不能作为可靠界面，请在应用中选择交互方式。 |
| Linux | 保留 WebKit 下载或自定义请求的原响应，经私有临时文件以不覆盖方式保存到最终位置。支持文件目标、进度及结果；无代理时仍使用默认下载目录。 |
| Android | 提供原生下载通知及元数据，支持拒绝或交给应用处理，不提供继续原生下载任务或指定原生保存目标。无代理时保留原 `onNavigationRequest` 行为。 |
| iOS/macOS | iOS 14.5+/macOS 11.3+ 支持指定文件、进度及结果，不提供 `platformDefault()`。旧系统明确报告新代理不受支持，现有最低兼容版本及导航行为不变。 |
| OHOS | 安装下载代理后使用 ArkWeb 原生下载任务。`platformDefault()` 保存到应用的 `filesDir/Downloads`；指定目标须为应用可写的文件路径，不支持文档提供器 URI。无代理时保留原导航回退行为。 |
| Web | 代理覆盖插件自行获取的附件响应，包括自定义请求头和 POST。普通 iframe 下载由浏览器管理，不能全部观测；交给浏览器后无法可靠报告最终文件路径或保存结果。 |

Windows 的 `controller.loadRequest` 会保留传入的方法、请求头和正文。配置
`onNavigationRequest` 时，页面表单提交可能在进入下载处理前被重新发起为 GET；
下载代理无法恢复在该导航步骤丢失的 POST 正文，详见[导航行为](/webview_all/zh/guides/navigation/)。

Android 交给应用处理时，不会提供原 POST 正文、自定义请求头或自动转移认证状态。
应用需要自行提供下载所需的上下文，重新 GET 该 URL 不等于继续原请求。

Web 附件沿用原响应，不重新请求 URL，也不替换当前页面或进入页面历史。
浏览器权限、iframe sandbox 下载限制及 CORS 仍然生效；跨域服务端需要暴露
`Content-Disposition`，插件的 fetch 路径才能读取附件头。
浏览器下载交付可能需要保留响应内容，不适合作为流式大文件下载器。

Linux 自定义请求头和 POST 请求沿用内存中的原响应，此路径可能在响应接收完毕后才报告进度。

更新或移除代理会取消尚未决策的请求；已经接受的下载继续向接受它的原代理报告结果，
直到任务结束。传入 `null` 可移除代理。Windows/Linux 的 `downloadsEnabled: false` 优先阻止
新下载。暂时隐藏或移除再挂载 widget 不等于永久销毁 controller；此接口不承诺
controller 关闭、应用退出或进程重启后仍继续下载。

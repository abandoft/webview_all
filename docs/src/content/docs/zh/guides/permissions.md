---
title: 权限
description: 处理摄像头、麦克风、定位、媒体和文件选择权限。
---

Web 内容权限有两层：

1. 宿主应用必须拥有系统权限。
2. WebView 必须批准网页请求。

```dart
final controller = WebViewController(
  onPermissionRequest: (WebViewPermissionRequest request) async {
    if (request.types.contains(WebViewPermissionResourceType.camera)) {
      await request.grant();
    } else {
      await request.deny();
    }
  },
);
```

同一个 request 只应调用一次 `grant()` 或 `deny()`。

## 通用资源

| 类型 | 含义 |
| --- | --- |
| `WebViewPermissionResourceType.camera` | 摄像头。 |
| `WebViewPermissionResourceType.microphone` | 麦克风。 |

## 平台扩展资源

| 平台 | 类型 | 含义 |
| --- | --- | --- |
| Android | `AndroidWebViewPermissionResourceType.midiSysex` | MIDI sysex。 |
| Android | `AndroidWebViewPermissionResourceType.protectedMediaId` | 受保护媒体 ID。 |
| OHOS | `OhosWebViewPermissionResourceType.midiSysex` | MIDI sysex。 |
| OHOS | `OhosWebViewPermissionResourceType.protectedMediaId` | 受保护媒体 ID。 |

## 定位权限

Android 和 OHOS 提供 geolocation prompt 回调：

```dart
await (controller.platform as AndroidWebViewController)
    .setGeolocationPermissionsPromptCallbacks(
  onShowPrompt: (request) async {
    return const GeolocationPermissionsResponse(
      allow: true,
      retain: false,
    );
  },
);
```

现代 WebView 通常要求定位请求来自 `https` 等安全 origin。

## 文件选择

Android 和 OHOS 支持 `<input type="file">`：

```dart
await (controller.platform as OhosWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  return <String>['/data/storage/el2/base/files/upload.png'];
});
```

`FileSelectorParams` 包含 `isCaptureEnabled`、`acceptTypes`、`filenameHint` 和 `mode`。

## 全屏 custom widget

Android 和 OHOS 可以把视频等全屏内容交给应用展示：

```dart
await (controller.platform as OhosWebViewController)
    .setCustomWidgetCallbacks(
  onShowCustomWidget: (Widget widget, VoidCallback onHidden) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => widget,
      ),
    );
  },
  onHideCustomWidget: () {
    Navigator.of(context).pop();
  },
);
```

## Web 权限

Web 实现会在同源内容和插件管理的隔离 HTML 中包装
`navigator.mediaDevices.getUserMedia`，并把 camera/microphone 请求转发给
`onPermissionRequest`。即使应用调用 `grant()`，浏览器仍可能继续显示自己的
权限提示。

## 统一文件选择

```dart
final capabilities = await controller.getBrowserCapabilities();
if (capabilities.fileSelector) {
  await controller.setFileSelector((request) async {
    // 使用应用自己的选择器；返回文件路径，Android 也可返回 content URI。
    // request.mode、acceptTypes、isCaptureEnabled 等描述本次选择。
    return <String>[]; // 空列表取消。
  });
}
await controller.setFileSelector(null); // 恢复引擎默认行为。
```

Android、Linux、OHOS、macOS 支持接管。iOS 需 18.4+ 及兼容的构建 SDK；较早系统
保留原生选择流程。Windows、Web 暂无统一自定义回调，调用时打印说明。
Apple 不提供 MIME 和拍摄提示；缺失提示为 `null` 或空列表。选择器异常会取消本次选择。

## 新窗口策略

```dart
await controller.setPopupPolicy(WebViewPopupWindowPolicy.deny);
await controller.setPopupPolicy(WebViewPopupWindowPolicy.platformDefault);
```

`platformDefault` 恢复平台原有策略，`deny` 拒绝新窗口，`sameView` 在当前页面加载。
可用策略见 `getBrowserCapabilities().popupWindowPolicies`。OHOS 支持默认和拒绝，
Web 暂不支持统一策略。`sameView` 不等价于创建子窗口，无法保证 `window.opener`
和表单 POST 等语义；需要这些行为时应保留平台默认处理。

## 媒体播放策略

需要统一设置时，在创建 controller 前选择策略：

```dart
final controller = WebViewController(
  mediaPlaybackPolicy: WebViewMediaPlaybackPolicy.requireUserGesture,
);
```

Android、iOS、macOS、Linux、OHOS 可在创建时配置；不传参数则保留默认值。
Android、Linux、OHOS 还可调用 `setMediaPlaybackRequiresUserGesture` 动态修改。
Apple 需重新创建 WebView 才能改变该配置。Windows、Web 无逐实例配置时会打印说明，
保留引擎策略。允许自动播放仍受引擎、网站及系统策略约束。

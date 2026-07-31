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

Web 实现会在同源 iframe 中包装 `navigator.mediaDevices.getUserMedia`，并把 camera/microphone 请求转发给 `onPermissionRequest`。即使应用调用 `grant()`，浏览器仍可能继续显示自己的权限提示。

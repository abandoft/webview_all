---
title: 调试
description: 启用引擎调试工具并检查运行时状态。
---

## Android

```dart
await AndroidWebViewController.enableDebugging(true);
```

然后使用 Chrome 或 Edge remote debugging 工具检查 Android WebView。

## iOS 和 macOS

```dart
final webKit = controller.platform as WebKitWebViewController;
await webKit.setInspectable(true);
```

是否可检查取决于 OS 版本和开发者设置。

## Windows

```dart
final windows = controller.platform as WindowsWebViewController;
await windows.openDevTools();

final version = await WindowsWebViewController.getWebViewVersion();
```

`getWebViewVersion()` 可用于启动时确认 WebView2 Runtime 是否存在。

## Linux

```dart
final linux = controller.platform as LinuxWebViewController;
await linux.setDeveloperExtrasEnabled(true);
await linux.openDevTools();
```

也可创建时启用：

```dart
final params = const LinuxWebViewControllerCreationParams(
  developerExtrasEnabled: true,
);
```

## OHOS

```dart
await OhosWebViewController.enableDebugging(true);
```

建议仅在开发构建启用 ArkWeb 调试。

## Web

WebView 是 iframe，使用浏览器 DevTools 调试。同源内容可以直接查看和操作，跨域 iframe 内部由浏览器隔离。

## Console 捕获

```dart
await controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
  debugPrint('[${message.level.name}] ${message.message}');
});
```

不要在未征得用户同意的情况下上传敏感页面 console 内容。

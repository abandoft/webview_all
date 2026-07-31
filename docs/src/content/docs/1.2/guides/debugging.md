---
title: Debugging
description: Enable engine debugging tools and inspect runtime state.
---

Debugging support is platform-specific because every engine exposes different tooling.

## Android

Enable WebView debugging globally:

```dart
await AndroidWebViewController.enableDebugging(true);
```

Use Chrome or Edge remote debugging tools to inspect the Android WebView.

## iOS and macOS

Enable WebKit inspection per controller:

```dart
final webKit = controller.platform as WebKitWebViewController;
await webKit.setInspectable(true);
```

Inspection availability depends on the OS version and developer settings.

## Windows

Open WebView2 DevTools:

```dart
final windows = controller.platform as WindowsWebViewController;
await windows.openDevTools();
```

Check runtime availability:

```dart
final version = await WindowsWebViewController.getWebViewVersion();
debugPrint('WebView2 runtime: $version');
```

## Linux

Enable WebKitGTK developer extras and open the inspector:

```dart
final linux = controller.platform as LinuxWebViewController;
await linux.setDeveloperExtrasEnabled(true);
await linux.openDevTools();
```

You can also set `developerExtrasEnabled` at creation time:

```dart
final params = const LinuxWebViewControllerCreationParams(
  developerExtrasEnabled: true,
);
final controller = WebViewController.fromPlatformCreationParams(params);
```

## OHOS

Enable ArkWeb debugging globally:

```dart
await OhosWebViewController.enableDebugging(true);
```

Turn this on only for development builds unless your product policy explicitly allows WebView inspection.

## Web

Use browser DevTools. The WebView is an iframe with an ID such as `webView0`. Same-origin content can be inspected and manipulated directly. Cross-origin iframe internals are isolated by the browser.

## Console Capture

All platforms can report page console messages when the engine exposes them:

```dart
await controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
  debugPrint('[${message.level.name}] ${message.message}');
});
```

Console capture is useful for app telemetry, but avoid uploading sensitive page content without user consent.

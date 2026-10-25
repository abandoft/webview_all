---
title: 平台设置
description: Android、Apple、Windows、Linux、OHOS 和 Web 的必要配置。
---

大多数平台添加 `webview_all` 后即可使用，但部分引擎需要运行时组件或权限。

## Android

最低 SDK 需要 API 24。根据页面能力添加系统权限：

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

如果 WebView 表单控件需要 Material Components 风格，请让应用主题兼容 Material Components。文件选择、拍照、录音等流程还需要应用自己处理 Android 运行时权限。

## iOS

最低 iOS 13.0。页面需要访问摄像头、麦克风或定位时，在 `Info.plist` 添加说明：

```xml
<key>NSCameraUsageDescription</key>
<string>Allow pages to use the camera after approval.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Allow pages to use the microphone after approval.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Allow pages to request location.</string>
```

App-Bound Domains 需要宿主应用配置域名，并用 `WebKitWebViewControllerCreationParams(limitsNavigationsToAppBoundDomains: true)` 创建控制器。

## macOS

最低 macOS 10.15。沙盒应用如需联网，需要启用 outgoing network entitlement：

```xml
<key>com.apple.security.network.client</key>
<true/>
```

macOS 与 iOS 共用 `webview_all_wkwebview`，但部分 UIKit 风格的属性在 macOS 上没有实现。详见[iOS 和 macOS](/webview_all/zh/platforms/ios-macos/)。

## Windows

Windows 使用 WebView2，目标机器必须安装 Microsoft Edge WebView2 Runtime。

```dart
final version = await WindowsWebViewController.getWebViewVersion();
if (version == null) {
  // 提示用户安装 WebView2 Runtime。
}
```

需要自定义用户数据目录或浏览器路径时，在首次创建 controller、操作 Cookie 或清理网站数据前配置共享环境：

```dart
await WindowsWebViewController.ensureEnvironment(
  userDataPath: 'C:\\Users\\Public\\MyApp\\WebView2',
);
```

相同配置可重复调用。从 1.4.7 起，无参调用也会复用已选环境；显式配置冲突时会明确失败。

## Linux

需要 WebKitGTK 4.1。Ubuntu 系发行版可安装：

```sh
sudo apt install libwebkit2gtk-4.1-dev
```

Linux 实现会在标准 Flutter runner realize `FlView` 之前自动安装所需的
`GtkOverlay`，应用无需修改 `linux/runner/my_application.cc`。

如需自定义网站数据和缓存目录，在首次创建 WebView、操作 Cookie 或清理网站数据前
调用 `LinuxWebViewController.ensureEnvironment(userDataPath: ..., cachePath: ...)`。
这些操作共用已选环境；旧数据不会自动迁移，详见 [Linux 目录配置](/webview_all/zh/platforms/linux/#网站数据目录)。

## OHOS

使用 [OHOS Flutter SDK](https://atomgit.com/CPF-Flutter/flutter_flutter) 和 API 22+。在宿主应用的 `ohos/build-profile.json5` 中，为 product 设置最低、编译和目标版本：

```json5
"compatibleSdkVersion": "6.0.2(22)",
"compileSdkVersion": "6.0.2(22)",
"targetSdkVersion": "6.0.2(22)"
```

应用的安装下限由宿主 product 决定，插件的包兼容性声明不能代替该配置。Web 内容权限由 `onPermissionRequest` 回调处理，但宿主应用仍然需要声明并获取对应系统权限。

## Web

Web 实现是 HTML `iframe`，必须遵守浏览器安全边界：

- 不能读取用户机器上的任意本地文件。
- 不能向跨域 iframe 执行 JavaScript。
- 不能拦截 TLS 证书错误决策。
- Cookie 受 `document.cookie` 和浏览器隐私策略限制。

---
title: 平台设置
description: Android、Apple、Windows、Linux、OHOS 和 Web 的必要配置。
---

大多数平台添加 `webview_all` 后即可使用，但部分引擎需要运行时组件、权限或 runner 修改。

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

macOS 与 iOS 共用 `webview_flutter_wkwebview`，但部分 UIKit 风格的属性在 macOS 上没有实现。详见[iOS 和 macOS](/webview_all/zh/1.2/platforms/ios-macos/)。

## Windows

Windows 使用 WebView2，目标机器必须安装 Microsoft Edge WebView2 Runtime。

```dart
final version = await WindowsWebViewController.getWebViewVersion();
if (version == null) {
  // 提示用户安装 WebView2 Runtime。
}
```

需要自定义用户数据目录或浏览器路径时，在创建 controller 前初始化环境：

```dart
await WindowsWebViewController.initializeEnvironment(
  userDataPath: 'C:\\Users\\Public\\MyApp\\WebView2',
);
```

## Linux

需要 WebKitGTK 4.1。Ubuntu 系发行版可安装：

```sh
sudo apt install libwebkit2gtk-4.1-dev
```

`webview_all` 1.2.x 的 Linux runner 需要提供 `GtkOverlay`，以便
`WebViewWidget` 正确加载。1.3 及更高版本不再需要手动修改 runner。

编辑应用项目中的 `linux/runner/my_application.cc`：

1. 确保文件靠前的位置存在以下回调。如果生成的 runner 已经包含该回调，
   不要重复添加：

```cpp
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}
```

2. 在 `my_application_activate` 中找到以下代码：

```cpp
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  gtk_widget_show(GTK_WIDGET(window));

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
```

不同 Flutter 版本生成的 runner 可能会在 `fl_view_new` 后包含背景色或尺寸
设置；替换时应保留这些附加设置。

3. 将该段代码替换为：

```cpp
  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  gtk_widget_show(GTK_WIDGET(view));

  GtkWidget* overlay = gtk_overlay_new();
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), overlay);

  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
```

如果生成的 runner 已经连接了 `"first-frame"` 信号或调用了
`gtk_widget_realize`，每项只保留一处。

## OHOS

使用 [OHOS Flutter SDK](https://atomgit.com/CPF-Flutter/flutter_flutter)，目标 OHOS API 12+。Web 内容权限由 `onPermissionRequest` 回调处理，但宿主应用仍然需要声明并获取对应系统权限。

## Web

Web 实现是 HTML `iframe`，必须遵守浏览器安全边界：

- 不能读取用户机器上的任意本地文件。
- 不能向跨域 iframe 执行 JavaScript。
- 不能拦截 TLS 证书错误决策。
- Cookie 受 `document.cookie` 和浏览器隐私策略限制。

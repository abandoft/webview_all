---
title: 安装
description: 添加 webview_all，并在需要时显式依赖平台包。
banner:
  content: "这是 1.4.x 系列文档。当前接口请切换至 latest。"
---

继续使用 1.4.x 时，同时固定主包和平台包的版本，避免混用新版接口或系统要求：

```yaml
dependencies:
  webview_all: '>=1.4.12 <1.5.0'
  webview_all_windows: '>=1.4.12 <1.5.0'
  webview_all_linux: '>=1.4.12 <1.5.0'
  webview_all_ohos: '>=1.4.12 <1.5.0'
  webview_all_web: '>=1.4.12 <1.5.0'
  webview_all_android: '>=1.4.12 <1.5.0'
  webview_all_wkwebview: '>=1.4.12 <1.5.0'
```

执行：

```sh
flutter pub get
```

## 平台专属接口

使用平台专属接口时，再按需导入对应包：

```dart
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
```

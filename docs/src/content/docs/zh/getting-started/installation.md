---
title: 安装
description: 添加 webview_all，并在需要时显式依赖平台包。
---

添加主包：

```yaml
dependencies:
  webview_all: ^1.4.0
```

执行：

```sh
flutter pub get
```

## 显式添加平台包

如果只使用通用 API，只依赖 `webview_all` 即可。

如果要使用某个平台的专属 webview 接口，请显式添加对应包。例如：

```yaml
dependencies:
  webview_all: ^1.4.0
  webview_all_windows: ^1.4.0
  webview_all_linux: ^1.4.0
  webview_all_ohos: ^1.4.0
  webview_all_web: ^1.4.0
  webview_all_android: ^1.4.0
  webview_all_wkwebview: ^1.4.0
```

然后按需导入：

```dart
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
```

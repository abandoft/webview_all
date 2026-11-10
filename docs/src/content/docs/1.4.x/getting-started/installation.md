---
title: Installation
description: Add webview_all and prepare platform packages.
banner:
  content: "Documentation for 1.4.x. Select latest for the current APIs."
---

To stay on 1.4.x, pin the plugin and its platform packages together to retain the APIs and system requirements documented here:

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

Run:

```sh
flutter pub get
```

## Platform-Specific APIs

Import a platform package only when using its platform-specific APIs:

```dart
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
```

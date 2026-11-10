---
title: Installation
description: Add webview_all and prepare platform packages.
banner:
  content: "Documentation for 1.2.x. Select latest for the current APIs."
---

To stay on 1.2.x, pin the plugin and its platform packages together to retain the APIs and system requirements documented here:

```yaml
dependencies:
  webview_all: '>=1.2.1 <1.3.0'
  webview_all_windows: '>=1.2.1 <1.3.0'
  webview_all_linux: '>=1.2.1 <1.3.0'
  webview_all_ohos: '>=1.2.1 <1.3.0'
  webview_all_web: '>=1.2.1 <1.3.0'
  webview_flutter_android: 4.12.0
  webview_flutter_wkwebview: 3.25.0
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
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
```

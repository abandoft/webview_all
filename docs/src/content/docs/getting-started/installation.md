---
title: Installation
description: Add webview_all and prepare platform packages.
---

Add the app-facing package:

```yaml
dependencies:
  webview_all: ^1.5.0
```

Run:

```sh
flutter pub get
```

## When to Add Platform Packages Directly

If your app only uses the common API, `webview_all` is enough.

If you cast to a platform implementation, add that package explicitly so the import is available to your app:

```yaml
dependencies:
  webview_all: ^1.5.0
  webview_all_windows: ^1.5.0
  webview_all_linux: ^1.5.0
  webview_all_ohos: ^1.5.0
  webview_all_web: ^1.5.0
  webview_all_android: ^1.5.0
  webview_all_wkwebview: ^1.5.0
```

Then import only the packages you need:

```dart
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
```

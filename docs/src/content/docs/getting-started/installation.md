---
title: Installation
description: Add webview_all and prepare platform packages.
---

Add the app-facing package:

```yaml
dependencies:
  webview_all: ^1.2.1
```

Run:

```sh
flutter pub get
```

The main package registers platform implementations through Flutter's federated plugin mechanism:

```yaml
flutter:
  plugin:
    platforms:
      android:
        default_package: webview_flutter_android
      ios:
        default_package: webview_flutter_wkwebview
      macos:
        default_package: webview_flutter_wkwebview
      linux:
        default_package: webview_all_linux
      windows:
        default_package: webview_all_windows
      ohos:
        default_package: webview_all_ohos
      web:
        default_package: webview_all_web
```

## When to Add Platform Packages Directly

If your app only uses the common API, `webview_all` is enough.

If you cast to a platform implementation, add that package explicitly so the import is available to your app:

```yaml
dependencies:
  webview_all: ^1.2.1
  webview_all_windows: ^1.2.1
  webview_all_linux: ^1.2.1
  webview_all_ohos: ^1.2.1
  webview_all_web: ^1.2.1
  webview_flutter_android: ^4.12.0
  webview_flutter_wkwebview: ^3.25.0
```

Then import only the packages you need:

```dart
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
```

## Version Contract

The `1.2.1` release is aligned across all `webview_all_*` platform packages. The wrapper depends on `webview_flutter_platform_interface ^2.15.1`, `webview_flutter_android ^4.12.0`, and `webview_flutter_wkwebview ^3.25.0`.

Keep the platform packages on the same minor line as the wrapper unless you are intentionally testing a platform package in isolation.

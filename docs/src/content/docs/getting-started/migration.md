---
title: Migration
description: Move from webview_flutter or older webview_all versions.
---

`webview_all` keeps the public wrapper shape close to `webview_flutter`: a controller, a widget, a navigation delegate, and a cookie manager. Most app code can switch imports first, then add platform-specific casts only where needed.

## From webview_flutter

Replace:

```dart
import 'package:webview_flutter/webview_flutter.dart';
```

with:

```dart
import 'package:webview_all/webview_all.dart';
```

Keep existing code that uses:

- `WebViewController`
- `WebViewWidget`
- `NavigationDelegate`
- `WebViewCookieManager`
- `NavigationDecision`
- `JavaScriptMode`
- `WebViewCookie`

Then check platform limits in the [Capability Matrix](/webview_all/platforms/capability-matrix/). The web and OHOS engines have the most visible differences because they are constrained by browser iframe security and ArkWeb request APIs.

## Platform-Specific Imports

If your old code imported `webview_flutter_android` or
`webview_flutter_wkwebview`, replace those imports with `webview_all_android`
and `webview_all_wkwebview`. The `1.3.0` line uses the forked implementations
for Android, iOS, and macOS.

For new desktop, OHOS, or web-specific code, add the relevant package and import it:

```dart
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
```

## Version 1.3

When upgrading from `1.2`:

- Replace direct imports of `webview_flutter_android` and
  `webview_flutter_wkwebview` with the forked packages shown above.
- Linux no longer requires application runner changes. You may restore
  `linux/runner/my_application.cc` to the Flutter default. An existing
  `GtkOverlay` wrapper remains compatible and can also be kept.

Patch releases within the `1.3` line do not require additional migration work.

## Version 1.2

Applications that remain on `1.2.1` should follow the frozen
[1.2 documentation](/webview_all/1.2/). Its Linux setup requires the runner
attachment described there; do not add that runner change to a new `1.3`
application.

## Behavioral Differences to Audit

Audit these areas during migration:

| Area | What to check |
| --- | --- |
| `loadRequest` | POST plus custom headers is not available on Android and OHOS. Web uses `fetch` for non-simple requests and is subject to CORS. |
| JavaScript | Web controls same-origin content directly and plugin-managed isolated HTML through a message bridge. Direct cross-origin iframe URLs remain browser-isolated. |
| Cookies | Web cookie reads require the exact current host-document URL; writes cannot target a foreign domain. Windows offers additional native metadata through `WindowsWebViewCookie`. |
| TLS | Web cannot expose recoverable TLS decisions. Native engines can report SSL auth callbacks when their engine exposes them. |
| macOS | Some UIKit-style WebKit properties have no macOS implementation. |
| Linux | WebKitGTK 4.1 is required; the standard Flutter runner needs no source changes. |

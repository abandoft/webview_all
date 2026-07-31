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

Then check platform limits in the [Capability Matrix](/webview_all/1.2/platforms/capability-matrix/). The web and OHOS engines have the most visible differences because they are constrained by browser iframe security and ArkWeb request APIs.

## Platform-Specific Imports

If your old code imported `webview_flutter_android` or `webview_flutter_wkwebview`, keep those imports. The main package still uses those implementations for Android, iOS, and macOS.

For new desktop, OHOS, or web-specific code, add the relevant package and import it:

```dart
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_all_web/webview_all_web.dart';
```

## Version 1.2.0 Notes

The `1.2.0` line aligns every `webview_all_*` platform package and expands platform API coverage:

- Windows exposes WebView2 runtime setup, popup policy, DevTools, suspend/resume, zoom factor, cache disabling, virtual host loading, HTTP errors, HTTP auth, SSL auth, JavaScript dialogs, permission requests, console messages, scroll changes, and full cookie metadata.
- Linux exposes WebKitGTK creation settings, Web Inspector, JavaScript dialogs, HTTP/SSL auth, permission requests, console messages, scroll changes, and common WebView operations.
- OHOS exposes ArkWeb settings, file selector, geolocation prompts, fullscreen custom widgets, permission requests, JavaScript dialogs, HTTP errors, SSL auth, scrollbars, overscroll styling, and third-party cookie control.
- Web exposes iframe attributes, fetch-backed custom loads, same-origin JavaScript control, same-origin JavaScript channels, same-origin console/dialog hooks, media permission mediation, and document cookie management.

## Behavioral Differences to Audit

Audit these areas during migration:

| Area | What to check |
| --- | --- |
| `loadRequest` | POST plus custom headers is not available on Android and OHOS. Web uses `fetch` for non-simple requests and is subject to CORS. |
| JavaScript | Web can only execute scripts in same-origin iframe content. |
| Cookies | Web cookies are host-document cookies. Windows offers additional native metadata through `WindowsWebViewCookie`. |
| TLS | Web cannot expose recoverable TLS decisions. Native engines can report SSL auth callbacks when their engine exposes them. |
| macOS | Some UIKit-style WebKit properties have no macOS implementation. |
| Linux | Runner must use `GtkOverlay` for correct native view placement. |

---
title: Errors and Limits
description: Exceptions, unsupported operations, and engine-specific edge cases.
---

This page lists important failures and platform limits that production code should handle.

## Common Validation

| API | Failure |
| --- | --- |
| `loadRequest(Uri())` | Throws `ArgumentError` when the URI has no scheme. |
| `loadFlutterAsset('')` | Throws or asserts because asset keys must not be empty. |
| `loadFile` | Throws when the file does not exist on platforms that can validate it. |
| `runJavaScriptReturningResult` | Throws when the result is `null`, `undefined`, or cannot be serialized. |
| `addJavaScriptChannel` | Throws for duplicate names. Some platforms also require valid JavaScript identifiers. |
| `setCookie` | Throws for invalid cookie names, domains, or paths. |

## Unsupported Operations

| Platform | API | Behavior |
| --- | --- | --- |
| Android | `loadRequest` with `POST` and custom headers | Throws because Android WebView `postUrl` cannot attach custom headers. |
| OHOS | `loadRequest` with `POST` and custom headers | Throws `UnsupportedError` because ArkWeb `postUrl` cannot attach custom headers. |
| Web | `loadFile` | Throws `UnsupportedError`; browsers cannot read arbitrary host files. |
| Web | `setUserAgent(nonNull)` | Throws `UnsupportedError`; iframe user agent cannot be overridden by page JavaScript. |
| Web | recoverable SSL decisions | `WebPlatformSslAuthError.proceed()` and `cancel()` throw `UnsupportedError`. |
| Web | cross-origin JavaScript and scroll APIs | Throws `UnsupportedError` or silently cannot install hooks when browser policy blocks access. |
| macOS | selected UIKit-backed WebKit properties | May throw `UnimplementedError` in the official WK package. |

## Request Loading Limits

For maximum portability:

- Use GET for navigations that need custom headers on Android or OHOS.
- Avoid POST custom headers if Android or OHOS are required.
- For web, ensure the server sends the CORS headers required by your method and custom headers.
- Use `loadHtmlString` as a fallback only when you control the response and do not need browser-native redirect, cookie, or service worker semantics.

## SSL and Certificate Errors

Native platforms can surface recoverable SSL errors when their engine exposes them. The safe default is always:

```dart
onSslAuthError: (SslAuthError error) async {
  await error.cancel();
}
```

Proceeding through a certificate error can expose users to interception. Keep `proceed()` for local development, test labs, or private certificate pinning experiments where you fully control the network.

## JavaScript Dialog Limits

On web, `confirm` and `prompt` callbacks must complete synchronously because browser JavaScript expects a synchronous return value:

```dart
await controller.setOnJavaScriptConfirmDialog((request) {
  return SynchronousFuture<bool>(true);
});
```

If the callback completes later, the web implementation throws `UnsupportedError`.

## Web Same-Origin Limits

The web platform cannot inspect or script cross-origin iframe content. This affects:

- JavaScript execution
- JavaScript channels
- console hooks
- dialog hooks
- scroll APIs
- title reads
- resource error detail

Use same-origin content, `loadHtmlString`, or fetch-backed requests when those features are required.

## Native Runtime Limits

| Platform | Limit |
| --- | --- |
| Windows | WebView2 Runtime must be installed. |
| Linux | WebKitGTK 4.1 must be installed and the runner must use `GtkOverlay`. |
| OHOS | Requires OHOS Flutter SDK and ArkWeb behavior can vary by API level. |
| Android | WebView features depend on the installed Android System WebView/Chrome version. |
| iOS/macOS | WebKit feature availability depends on OS version and app entitlements. |

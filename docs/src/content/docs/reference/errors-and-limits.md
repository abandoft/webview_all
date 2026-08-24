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
| `callAsyncJavaScript` | Throws `ArgumentError` for an empty body, invalid/reserved argument names, non-JSON arguments, non-finite numbers, or a non-positive timeout; rejected Promises and runtime errors produce `JavaScriptExecutionException`, and expiration produces `TimeoutException`. |
| `addUserScript` | Throws `ArgumentError` for empty source and `UnsupportedError` when the requested injection point is unavailable. Check `isUserScriptInjectionSupported` first. |
| `addJavaScriptChannel` | Throws for duplicate names. Some platforms also require valid JavaScript identifiers. |
| `setCookie` | Throws for invalid cookie names, domains, or paths. |

## Unsupported Operations

| Platform | API | Behavior |
| --- | --- | --- |
| Android | `loadRequest` with `POST` and custom headers | Throws because Android WebView `postUrl` cannot attach custom headers. |
| OHOS | `loadRequest` with `POST` and custom headers | Throws `UnsupportedError` because ArkWeb `postUrl` cannot attach custom headers. |
| Web | `loadFile` | Throws `UnsupportedError`; browsers cannot read arbitrary host files. |
| Web | `setUserAgent(nonNull)` | Logs once and ignores the override; iframe network user agent cannot be changed by page JavaScript. |
| Web | recoverable SSL decisions | `WebPlatformSslAuthError.proceed()` and `cancel()` throw `UnsupportedError`. |
| Web | cross-origin JavaScript and scroll APIs | Throws `UnsupportedError` or silently cannot install hooks when browser policy blocks access. |
| Web | cookie request for another origin | Returns an empty list and logs once; browser JavaScript cannot inspect that cookie jar. |
| Web | document-start user scripts | Capability returns false because iframe APIs cannot guarantee execution before page scripts. |
| Web | `WebViewDataManager.clearAllWebsiteData` | Returns every category as unsupported; a page cannot clear arbitrary iframe storage or `HttpOnly` cookies. |
| OHOS | document-start user scripts | Capability returns false because the current ArkWeb bridge has no deterministic document-start API. |
| Android | document-start user scripts on an older System WebView | Capability returns false; the app can continue without registering the script. |
| Windows | website-data clearing | Session storage and service worker registrations are unsupported by the WebView2 profile API. Older runtimes without that API report every category as unsupported. |
| macOS | scroll position, scroll callbacks, scrollbar visibility, and overscroll | The fork logs the missing public WKWebView API and safely no-ops; position reads return `Offset.zero`. |
| macOS | version-gated WebKit properties | Background color requires macOS 12 and inspection requires macOS 13.3. Earlier versions log and safely no-op. |

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

On web, custom `confirm` and `prompt` callbacks for same-origin content must
complete synchronously because browser JavaScript expects a synchronous return
value:

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

Use same-origin content, `loadHtmlString`, or fetch-backed requests when those
features are required. Plugin-managed isolated HTML uses a controlled message
bridge. Direct cross-origin iframe URLs remain inaccessible, and isolated HTML
keeps browser-native `confirm` and `prompt` dialogs.

## Website-Data Clearing Results

`clearAllWebsiteData` is intentionally result-based so production logout code can distinguish a complete wipe from an engine limitation or native failure. Check `result.isComplete`; inspect `unsupportedDataTypes` and `failures` otherwise. The API does not fall back to clearing browsing history, passwords, autofill, or profile settings.

Web fetch-backed navigation keeps at most 100 typed history entries. Back and
forward restore the stored response snapshot and never replay a mutating
request; `reload()` is the explicit operation that refetches it. A navigation
delegate denial leaves the current history index unchanged.

## Callback Failure Safety

On Linux, navigation, HTTP authentication, TLS, permission, and JavaScript
dialog decisions use a safe deny/cancel result if the application callback
throws or returns an error. Native pending decisions also expire after 30
seconds. The failure is logged on one line so an application bug remains
diagnosable without blocking WebKitGTK.

Windows initialization failures are shown in the widget and may be retried with
**Refresh**. **Install Webview2** is offered only for
`webview2_runtime_unavailable` and opens the official WebView2 Runtime download
page. Partial initialization state is released before a retry.

### Windows initialization errors

| Code | Stage | Meaning |
| --- | --- | --- |
| `webview2_runtime_unavailable` | `webview2_runtime` | No compatible Runtime was found for the requested browser path. |
| `environment_creation_failed` | `webview2_environment` | WebView2 could not create the requested profile environment. |
| `winrt_runtime_unavailable` / `winrt_initialization_failed` | `winrt_runtime` / `winrt_initialization` | The Windows Runtime needed by the renderer could not be loaded or initialized. |
| `graphics_capture_unavailable` / `graphics_capture_initialization_failed` | `graphics_capture` | Graphics capture is unavailable in the current OS, device, policy, or session. |
| `dispatcher_queue_initialization_failed` | `dispatcher_queue` | The UI thread's composition queue could not be reused or created. |
| `d3d_device_creation_failed` | `d3d_device` | Neither a hardware Direct3D device nor the WARP fallback could be created. |
| `dxgi_device_initialization_failed` | `dxgi_device` | The Direct3D device does not expose the required DXGI interface. |
| `d3d_interop_initialization_failed` | `d3d_interop` | Windows Runtime Direct3D interop initialization failed. |
| `composition_initialization_failed` | `composition` | The Windows Composition compositor could not be created. |
| `webview_creation_failed` | `webview2_controller` / `graphics_capture_texture` | Controller or capture-texture creation failed after environment setup. |

Initialization error details include `stage`, hexadecimal `hresult`, signed
`hresultValue`, `remoteSession`, and `webView2RuntimeVersion` when detected.
Equivalent concurrent `ensureEnvironment` calls share one native creation
operation; conflicting configurations fail without replacing active or pending
state.

## Native Runtime Limits

| Platform | Limit |
| --- | --- |
| Windows | WebView2 Runtime must be installed. |
| Linux | WebKitGTK 4.1 must be installed. The plugin installs its `GtkOverlay` automatically for the standard Flutter runner. |
| OHOS | Requires OHOS Flutter SDK and ArkWeb behavior can vary by API level. |
| Android | WebView features depend on the installed Android System WebView/Chrome version. |
| iOS/macOS | WebKit feature availability depends on OS version and app entitlements. |

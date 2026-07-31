---
title: Navigation
description: Handle page events, URL changes, HTTP errors, auth challenges, SSL errors, and request decisions.
---

`NavigationDelegate` collects navigation callbacks and installs them into the platform implementation through `WebViewController.setNavigationDelegate`.

```dart
await controller.setNavigationDelegate(
  NavigationDelegate(
    onNavigationRequest: (NavigationRequest request) {
      if (request.url.startsWith('myapp://')) {
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    },
    onPageStarted: (String url) {},
    onProgress: (int progress) {},
    onPageFinished: (String url) {},
    onUrlChange: (UrlChange change) {},
    onWebResourceError: (WebResourceError error) {},
    onHttpError: (HttpResponseError error) {},
    onHttpAuthRequest: (HttpAuthRequest request) {},
    onSslAuthError: (SslAuthError error) {},
  ),
);
```

## Request Decisions

`onNavigationRequest` can prevent main-frame and sub-frame navigations when the engine reports them. The callback may return synchronously or as a `Future`.

```dart
onNavigationRequest: (NavigationRequest request) async {
  final uri = Uri.tryParse(request.url);
  if (uri == null) {
    return NavigationDecision.prevent;
  }
  return uri.host.endsWith('example.com')
      ? NavigationDecision.navigate
      : NavigationDecision.prevent;
}
```

Some platforms also invoke the callback for controller-initiated loads. Treat it as a central policy hook.

## Page Lifecycle

| Callback | Meaning |
| --- | --- |
| `onPageStarted` | Main-frame load started. |
| `onProgress` | Engine-reported load progress from `0` to `100` when available. |
| `onPageFinished` | Main-frame load completed. |
| `onUrlChange` | Visible or logical URL changed. |

The web implementation reports logical URLs for `loadHtmlString` and fetch-backed `loadRequest`, because those loads are rendered through `srcdoc` or `data:` URLs internally.

## Resource Errors

`onWebResourceError` reports network, TLS, file, policy, and engine failures:

```dart
onWebResourceError: (WebResourceError error) {
  debugPrint('code=${error.errorCode}');
  debugPrint('type=${error.errorType}');
  debugPrint('mainFrame=${error.isForMainFrame}');
  debugPrint('url=${error.url}');
}
```

Platform-specific subclasses add detail:

| Platform | Subclass | Extra fields |
| --- | --- | --- |
| Android | `AndroidWebResourceError` | `failingUrl` is deprecated; use `url`. |
| iOS/macOS | `WebKitWebResourceError` | Wraps WebKit/NSError mapping. |
| Windows | `WindowsWebResourceError` | Maps WebView2 `WebErrorStatus`. |
| Linux | `LinuxWebResourceError` | Maps WebKitGTK error types. |
| OHOS | `OhosWebResourceError` | Maps ArkWeb error codes. |
| Web | `WebResourceError` | Used for fetch failures. |

## HTTP Errors

`onHttpError` reports HTTP responses with status code `400` or greater when the engine exposes the response:

```dart
onHttpError: (HttpResponseError error) {
  final status = error.response?.statusCode;
  final headers = error.response?.headers;
}
```

Windows, Linux, OHOS, iOS, macOS, and web report HTTP errors. Android reports them through the official Android implementation.

On web, `onHttpError` only fires for fetch-backed loads. A simple cross-origin iframe navigation is owned by the browser and does not expose response headers to the host page.

## HTTP Authentication

```dart
onHttpAuthRequest: (HttpAuthRequest request) {
  request.onProceed(
    const WebViewCredential(user: 'demo', password: 'secret'),
  );
}
```

Call exactly one response path. If you do not intend to continue, call `request.onCancel()`.

## SSL Authentication

```dart
onSslAuthError: (SslAuthError error) async {
  debugPrint(error.platform.description);
  await error.cancel();
}
```

Only call `proceed()` for controlled test environments. In production, a recoverable certificate error means the connection is not trustworthy.

The web platform cannot expose recoverable TLS decisions. Browser iframe APIs do not allow an embedded Flutter app to proceed past or cancel certificate errors, so `WebPlatformSslAuthError.proceed()` and `cancel()` throw `UnsupportedError`.

## Platform Notes

| Platform | Notes |
| --- | --- |
| Android | Navigation, HTTP auth, SSL auth, HTTP errors, URL changes, and resource errors are handled by the official Android package. |
| iOS/macOS | HTTP auth supports Basic and NTLM challenges. Recoverable server trust errors can be surfaced through `onSslAuthError`. |
| Windows | WebView2 reports HTTP response errors, HTTP auth, SSL auth, and load errors through the native bridge. |
| Linux | WebKitGTK reports navigation requests, HTTP auth, SSL auth, permission requests, and JavaScript dialogs through an event channel. |
| OHOS | ArkWeb reports HTTP errors, HTTP auth, SSL auth, visited history updates, and request details including method and headers where available. |
| Web | Navigation decisions are enforced for controller-initiated loads. Browser iframe navigations inside cross-origin pages are not fully observable. |

---
title: Security
description: Production guidance for navigation policy, JavaScript, cookies, TLS, and platform permissions.
---

WebViews execute remote content inside your app. Treat them as a privileged integration point.

## Navigation Policy

Use `onNavigationRequest` to restrict untrusted destinations:

```dart
NavigationDelegate(
  onNavigationRequest: (NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) {
      return NavigationDecision.prevent;
    }

    const allowedHosts = {'example.com', 'accounts.example.com'};
    return allowedHosts.contains(uri.host)
        ? NavigationDecision.navigate
        : NavigationDecision.prevent;
  },
);
```

Use the app router for custom schemes such as `myapp://` and prevent the WebView from navigating to them.

## JavaScript Channels

JavaScript channels are an app-to-page bridge. Validate every message:

```dart
await controller.addJavaScriptChannel(
  'AppBridge',
  onMessageReceived: (JavaScriptMessage message) {
    final Object? decoded = jsonDecode(message.message);
    if (decoded is! Map<String, Object?>) {
      return;
    }
    if (decoded['type'] != 'expected-event') {
      return;
    }
  },
);
```

Do not expose secrets, access tokens, file paths, or privileged commands directly to page JavaScript.

## TLS Decisions

Use `SslAuthError.cancel()` in production:

```dart
onSslAuthError: (SslAuthError error) async {
  await error.cancel();
}
```

`proceed()` should be reserved for internal testing against controlled endpoints.

## Cookies

Use `Secure`, `HttpOnly`, and `SameSite` attributes from your server for authentication cookies. Client-side cookie setters in `WebViewCookieManager` cannot mark every attribute on every platform. Windows exposes more local metadata through `WindowsWebViewCookie`, but server-set cookies remain the safest source of truth.

## Mixed Content

On Android, explicitly set mixed content behavior:

```dart
await (controller.platform as AndroidWebViewController)
    .setMixedContentMode(MixedContentMode.neverAllow);
```

For other platforms, prefer HTTPS-only content and block unknown hosts through `onNavigationRequest`.

## File Access

Disable file access unless your product requires it:

```dart
await (controller.platform as AndroidWebViewController)
    .setAllowFileAccess(false);

await (controller.platform as OhosWebViewController)
    .setAllowFileAccess(false);
```

On Linux, avoid `setAllowUniversalAccessFromFileUrls(true)` for untrusted files. It allows file documents to access all origins.

## Web Platform

The web implementation benefits from browser sandboxing but also inherits browser restrictions. Configure iframe attributes deliberately:

```dart
final params = WebWebViewControllerCreationParams(
  iFrameSandbox: 'allow-same-origin allow-scripts allow-forms',
  iFrameReferrerPolicy: 'no-referrer',
);
```

Do not add broad sandbox permissions such as `allow-top-navigation` unless the embedded content must control the top-level browser tab.

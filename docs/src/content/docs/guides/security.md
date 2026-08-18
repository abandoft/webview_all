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

## Web Authentication and Passkeys

WebAuthn must preserve the platform engine's origin and authenticator security
model. `webview_all` exposes an enable switch only on Android, where AndroidX
WebKit requires one; it does not emulate credentials or add a common switch
that other engines cannot honor.

| Platform | Production requirement |
| --- | --- |
| Android | Check `WebViewFeatureType.webAuthentication`, use `forApp` for an ordinary app, and configure Digital Asset Links. `forBrowser` is restricted to eligible privileged browser apps. |
| iOS/macOS | Let `WKWebView` handle the request and configure the relying party in Associated Domains. |
| Windows | Let WebView2 and Windows handle the request; validate the exact desktop, Server, or virtualized deployment environment. |
| Linux | WebKitGTK does not currently implement WebAuthn; use a supported external browser or another sign-in method. |
| OHOS | ArkWeb does not document a supported host integration; do not assume passkey availability without target-device validation. |
| Web | For a cross-origin iframe, delegate `publickey-credentials-get` and, only when registration is needed, `publickey-credentials-create` through `iFrameAllow`. |

Keep a non-passkey sign-in path whenever the authenticator availability check
fails. Never replace WebAuthn with a JavaScript bridge that accepts raw
credentials or bypasses relying-party validation.

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
  iFrameSandbox: 'allow-scripts allow-forms',
  iFrameReferrerPolicy: 'no-referrer',
);
```

Avoid combining `allow-scripts` and `allow-same-origin` for untrusted
same-origin or `srcdoc` content. That combination can let the document remove
its own sandbox. Strictly sandboxed `loadHtmlString` content and fetch-backed
HTML use the plugin's isolated message bridge for supported controller APIs.

Do not add broad sandbox permissions such as `allow-top-navigation` unless the embedded content must control the top-level browser tab.

---
title: Cookies
description: Manage shared WebView cookies and platform-specific cookie metadata.
---

`WebViewCookieManager` manages cookies for WebViews owned by the underlying engine.

```dart
final cookies = WebViewCookieManager();

await cookies.setCookie(
  const WebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
  ),
);

final list = await cookies.getCookies(domain: Uri.parse('https://example.com'));
final hadCookies = await cookies.clearCookies();
```

## Common API

| Method | Behavior |
| --- | --- |
| `setCookie(WebViewCookie cookie)` | Sets a cookie with name, value, domain, and path. |
| `getCookies({required Uri domain})` | Returns cookies visible for the provided domain or URL. |
| `clearCookies()` | Removes cookies and returns whether cookies were present when the platform can report it. |

Cookie validation rejects empty names, browser-rejected characters, and invalid paths. A non-empty path must start with `/`.

## Platform Behavior

| Platform | Storage | Notes |
| --- | --- | --- |
| Android | Android WebView `CookieManager`. | Supports third-party cookie policy through platform API. |
| iOS/macOS | `WKWebsiteDataStore.defaultDataStore`. | Filters `getCookies` by RFC-style domain matching. |
| Windows | WebView2 cookie manager. | Exposes extended cookie metadata through `WindowsWebViewCookie`. |
| Linux | WebKitGTK cookie manager bridge. | Common cookie fields are supported. |
| OHOS | ArkWeb `CookieManager`. | Supports third-party cookie policy through `setAcceptThirdPartyCookies`. |
| Web | `document.cookie`. | Limited to cookies visible to the host page origin. `HttpOnly` cookies are not readable from JavaScript. |

## Windows Full Cookie API

Windows exposes WebView2 cookie metadata:

```dart
final manager = WebViewCookieManager().platform
    as WindowsWebViewCookieManager;

await manager.setWindowsCookie(
  WindowsWebViewCookie(
    name: 'session',
    value: 'abc',
    domain: 'example.com',
    path: '/',
    isHttpOnly: true,
    isSecure: true,
    sameSite: WindowsWebViewCookieSameSite.lax,
    expires: DateTime.now().add(const Duration(days: 7)),
  ),
);

final cookies = await manager.getWindowsCookies(
  Uri.parse('https://example.com'),
);

await manager.deleteCookiesWithNameAndUrl(
  name: 'session',
  url: Uri.parse('https://example.com'),
);
```

## Android Third-Party Cookies

```dart
final manager = WebViewCookieManager().platform
    as AndroidWebViewCookieManager;
final androidController = controller.platform as AndroidWebViewController;

await manager.setAcceptThirdPartyCookies(androidController, true);
```

## OHOS Third-Party Cookies

```dart
final manager = WebViewCookieManager().platform
    as OhosWebViewCookieManager;
final ohosController = controller.platform as OhosWebViewController;

await manager.setAcceptThirdPartyCookies(ohosController, true);
```

## Web Cookie Limits

The web implementation uses `document.cookie`, so it follows browser JavaScript cookie limits:

- It cannot read `HttpOnly` cookies.
- It cannot clear cookies for unrelated domains.
- It cannot bypass `SameSite`, `Secure`, partitioning, or browser privacy rules.
- `getCookies` returns cookies visible to the host document, using the provided URL host as the returned cookie domain.

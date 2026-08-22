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

## Clear All Website Data

Use `WebViewDataManager` for logout cleanup when no controller is mounted:

```dart
final result = await WebViewDataManager().clearAllWebsiteData();

if (!result.isComplete) {
  debugPrint('Unsupported: ${result.unsupportedDataTypes}');
  debugPrint('Failed: ${result.failures}');
}
```

The manager targets the default persistent data store shared by normal WebViews. It clears the website-data categories exposed by the platform—cookies, cache, local/session storage, IndexedDB, WebSQL, Cache Storage, and service workers—and reports every category as cleared, unsupported, or failed. Always inspect `isComplete` before treating logout cleanup as successful. Passwords, autofill data, download history, browsing history, and engine settings are outside this API.

On Windows, this operation creates a temporary controller and may initialize
the shared WebView2 environment. When custom options are required, construct
the manager with `WindowsWebViewDataManagerCreationParams`; equivalent options
reuse an existing environment and conflicting options fail explicitly.

| Platform | Behavior |
| --- | --- |
| Android | Uses AndroidX WebKit's complete browsing-data operation when supported; older System WebView versions clear cookies, cache, local storage, and WebSQL, and report the remaining categories as unsupported. |
| iOS/macOS | Clears the corresponding types from `WKWebsiteDataStore.default()`. |
| Windows | Clears the cookies, DOM storage types, and disk cache exposed by WebView2. Session storage and service worker registrations are reported as unsupported; runtimes without the profile clearing API report every category as unsupported. |
| Linux | Clears all website data from the default WebKitGTK context. |
| OHOS | Clears cookies and ArkWeb-exposed local/session storage and WebSQL; other categories are reported as unsupported. |
| Web | Reports all categories as unsupported because a host page cannot clear arbitrary iframe origins or `HttpOnly` cookies. |

## Platform Behavior

| Platform | Storage | Notes |
| --- | --- | --- |
| Android | Android WebView `CookieManager`. | Preserves encoded names/values and values containing `=`; supports third-party cookie policy. |
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
- `getCookies` returns data only for the exact current document scheme, host,
  and path; other URL contexts return an empty list.
- Returned cookies use the current document host and `/` because
  `document.cookie` does not expose their original domain/path attributes.
- `clearCookies` is best effort across visible parent domain/path candidates
  and returns true only when at least one visible cookie disappears.

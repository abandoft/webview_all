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
| `setCookie(WebViewCookie cookie)` | Sets a cookie with optional expiry, security, and SameSite attributes. |
| `getCookies({required Uri domain})` | Returns cookies visible for the provided URL. |
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

The manager targets the website-data store shared by normal WebViews. On Windows and Linux, this follows the selected shared environment; other platforms use their default store. It clears the website-data categories exposed by the platform—cookies, cache, local/session storage, IndexedDB, WebSQL, Cache Storage, and service workers—and reports every category as cleared, unsupported, or failed. Always inspect `isComplete` before treating logout cleanup as successful. Passwords, autofill data, download history, browsing history, and engine settings are outside this API.

On Windows and Linux, configure custom directories before the first WebView,
cookie operation, or website-data cleanup. From 1.4.7, a default manager reuses
the selected environment without repeating its options. When cleanup is the
first operation, `WindowsWebViewDataManagerCreationParams` or
`LinuxWebViewDataManagerCreationParams` can select the environment. Explicit
options must match an existing configuration; conflicts are reported in
`result.failures`. Windows uses a temporary native controller without graphics
capture or a Flutter texture; Linux does not create a WebView for cleanup.

| Platform | Behavior |
| --- | --- |
| Android | Uses AndroidX WebKit's complete browsing-data operation when supported; older System WebView versions clear cookies, cache, local storage, and WebSQL, and report the remaining categories as unsupported. |
| iOS/macOS | Clears the corresponding types from `WKWebsiteDataStore.default()`. |
| Windows | Clears the cookies, DOM storage types, and disk cache exposed by WebView2. Session storage and service worker registrations are reported as unsupported; runtimes without the profile clearing API report every category as unsupported. |
| Linux | Clears all website data from the selected shared WebKitGTK environment. |
| OHOS | Clears cookies, shared resource cache, local storage, and WebSQL without creating a WebView. Session storage, IndexedDB, Cache Storage, and service worker registrations are reported as unsupported. |
| Web | Reports all categories as unsupported because a host page cannot clear arbitrary iframe origins or `HttpOnly` cookies. |

## Capability checks

`getCapabilities()` reports readable attributes and individual-deletion support.
`deleteCookie(name: ..., domain: ..., path: ...)` deletes a known cookie identity.

## Platform Behavior

| Platform | Storage | Notes |
| --- | --- | --- |
| Android | Android WebView `CookieManager`. | Preserves encoded names/values and values containing `=`; supports third-party cookie policy. |
| iOS/macOS | `WKWebsiteDataStore.defaultDataStore`. | Filters reads by domain, path, scheme, and expiry. |
| Windows | WebView2 cookie manager. | Supports common attributes and existing Windows extensions. |
| Linux | WebKitGTK cookie manager bridge. | Supports common attributes and individual deletion. |
| OHOS | ArkWeb `CookieManager`. | Supports third-party cookie policy through `setAcceptThirdPartyCookies`. |
| Web | `document.cookie`. | Limited to cookies visible to the host page origin. `HttpOnly` cookies are not readable from JavaScript. |

## Cookie attributes and individual deletion

```dart
final capabilities = await cookies.getCapabilities();
await cookies.setCookie(WebViewCookie(
  name: 'session', value: 'abc', domain: '.example.com', path: '/',
  expires: DateTime.now().toUtc().add(const Duration(days: 7)),
  isSecure: true,
  isHttpOnly: true,
  sameSite: WebViewCookieSameSite.lax,
));
await cookies.deleteCookie(name: 'session', domain: '.example.com', path: '/');
```

Set `expires`, `isSecure`, `isHttpOnly`, and `sameSite` when writing. `isSession` is
read-only metadata. `SameSite=None` requires `isSecure: true`. Deletion needs the
stored name, domain, and path. A `true` result means the operation completed,
including when no matching cookie existed.

Android reads native attributes when System WebView supports `GET_COOKIE_INFO`,
including distinct paths, HttpOnly, expiry and available SameSite values. Omitted
SameSite stays unknown. Older Android providers and OHOS expose only names and
values. Other attributes remain `null`; returned domain/path values
are compatibility placeholders and cannot establish the stored cookie identity.
iOS, macOS, Windows, and Linux expose native metadata; check `readableAttributes`.
Web can access host-document cookies only and cannot handle `HttpOnly` cookies.
An attempt to create an `HttpOnly` cookie is skipped with a diagnostic.

On Windows, the global cookie API keeps session cookies available during the
app's browser session, including before the first page loads. Set an expiry for
persistence across app launches. A session-scoped manager follows its profile's
lifetime. Existing Windows-specific cookie APIs remain available.

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


## Clear selected website data

```dart
final manager = WebViewDataManager(); // Use session.dataManager inside a session.
final types = {WebViewDataType.cookies, WebViewDataType.cache};
final capabilities = await manager.getCapabilities();
final result = await manager.clearWebsiteData(dataTypes: types);
if (!result.isComplete) {
  debugPrint('${result.unsupportedDataTypes}: ${result.failures}');
}
```

Only the requested categories are cleared. Categories that cannot be cleared
independently are reported as unsupported; the operation never broadens the
requested scope. `isComplete` covers the requested categories only. An empty set
is a successful no-op. Check `capabilities.canClear(types)` for a combination;
`clearingGroups` lists categories that must be requested together. Session
managers address their session's store.

iOS, macOS and Linux can clear each listed category separately. Windows supports
cookies, disk cache, local storage, IndexedDB, WebSQL and Cache Storage, depending
on the installed Runtime. Android and OHOS can clear cookies and available
caches separately. Newer Android WebViews also support a full clear, which does
not make other storage categories individually clearable. OHOS session managers
do not clear shared caches. Web cannot clear arbitrary website stores. Pages
can write new data afterwards; stop relevant page activity before clearing.

For individual deletion, use the stored domain/path, including any leading `.`.
Compatibility placeholders cannot establish cookie identity. Android, OHOS and
Web distinguish host-only and domain cookies when expiring them, and preserve
the flags required by secure cookie prefixes.

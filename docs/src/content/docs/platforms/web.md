---
title: Web
description: Browser iframe implementation, iframe attributes, fetch-backed requests, and security limits.
---

Web is provided by `webview_all_web 1.3.3` and renders an HTML `iframe`.

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_web` |
| Main platform class | `WebWebViewPlatform` |
| Controller | `WebWebViewController` |
| Widget | `WebWebViewWidget` |
| Navigation delegate | `WebNavigationDelegate` |
| Cookie manager | `WebWebViewCookieManager` |
| Engine | Browser iframe plus Dart JS interop |

## Creation Params

```dart
final params = WebWebViewControllerCreationParams(
  iFrameAllow: 'camera; microphone; fullscreen',
  iFrameSandbox: 'allow-scripts allow-forms',
  iFrameReferrerPolicy: 'strict-origin-when-cross-origin',
  iFrameAttributes: const <String, String?>{
    'loading': 'lazy',
  },
);

final controller = WebViewController.fromPlatformCreationParams(params);
```

| Param | Meaning |
| --- | --- |
| `iFrameAllow` | Sets iframe `allow`. |
| `iFrameSandbox` | Sets iframe `sandbox` when JavaScript is unrestricted. |
| `iFrameReferrerPolicy` | Sets iframe `referrerpolicy`. |
| `iFrameAttributes` | Additional iframe attributes. `null` removes an attribute. |
| `httpRequestFactory` | Test hook for fetch-backed loads. |

Attribute names are validated before they reach the DOM. Empty or malformed
names are rejected, and `id`, `src`, and `srcdoc` are reserved because the
controller owns iframe identity and document loading.

## Controller API

| API | Purpose |
| --- | --- |
| `setIFrameAttribute(String name, String? value)` | Sets or removes any iframe attribute. |
| `setIFrameAllow(String? allow)` | Sets or removes `allow`. |
| `setIFrameSandbox(String? sandbox)` | Sets or removes `sandbox`. |
| `setIFrameReferrerPolicy(String? referrerPolicy)` | Sets or removes `referrerpolicy`. |

## Loading Model

Simple GET loads with no body and no headers set the iframe `src` directly:

```dart
await controller.loadRequest(Uri.parse('https://example.com'));
```

Requests with method, headers, or body use browser `fetch`, read the response, and render it as a `data:` URL:

```dart
await controller.loadRequest(
  Uri.parse('https://api.example.com/page'),
  headers: const <String, String>{'X-App': 'demo'},
);
```

Fetch-backed loads require server CORS approval for cross-origin requests.
HTML response bytes are decoded using the declared `Content-Type` charset,
including quoted and extension parameters. A `<base>` element preserves
relative URL resolution.

## History

The controller keeps up to 100 typed history entries for direct URLs, inline
HTML, and fetch-backed responses. Back/forward navigation restores the matching
content type and removes stale `src` or `srcdoc` state.

For fetch-backed POST or custom-header requests, history stores the decoded
response snapshot. Going back and forward does not replay the request. An
explicit `reload()` performs the request again and replaces the active
snapshot. Concurrent fetches are generation-checked, so an older response
cannot overwrite a newer navigation.

This history covers loads initiated through the controller. Browser-owned
navigation inside a cross-origin iframe cannot be inspected reliably because
of the same-origin policy.

## Controllable Content

The implementation supports these APIs through either direct same-origin
access or a source-validated message bridge injected into isolated,
plugin-managed HTML:

- `runJavaScript`
- `runJavaScriptReturningResult`
- `addJavaScriptChannel`
- `removeJavaScriptChannel`
- console message hooks
- JavaScript dialog hooks
- scroll reads and writes
- `getTitle`

This covers same-origin URLs, ordinary `loadHtmlString`, fetch-backed HTML, and
`loadHtmlString` used with a strict sandbox that contains `allow-scripts` but
not `allow-same-origin`. Fetch-backed HTML remains in an opaque `data:` origin;
it is not granted the host application's origin.

A simple URL loaded directly into a cross-origin iframe remains browser-owned
and cannot be controlled by these APIs. Fetch-backed non-HTML responses are
also rendered without injecting a JavaScript bridge.

## Cookies

`WebWebViewCookieManager` uses `document.cookie`:

```dart
await WebViewCookieManager().setCookie(
  const WebViewCookie(
    name: 'theme',
    value: 'dark',
    domain: '',
    path: '/',
  ),
);
```

Browser JavaScript exposes only cookies visible to the host document. Therefore:

- `getCookies` returns data only when the requested scheme, host, and path
  exactly match the current host document; other URLs return an empty list and
  log the browser limitation once.
- `setCookie` rejects a domain that is not visible from the host document.
- `clearCookies` expires visible cookie names across matching parent
  domain/path candidates and reports whether at least one visible cookie was
  removed.
- `HttpOnly` and unrelated-origin cookies remain inaccessible. The browser does
  not expose cookie path/domain attributes on reads, so returned entries use
  the current host and `/`.

## Unsupported or Limited APIs

| API | Behavior |
| --- | --- |
| `loadFile` | Throws `UnsupportedError`. |
| `setUserAgent(nonNull)` | Logs once and ignores the value. Browsers do not let page JavaScript override iframe network user agent. |
| SSL auth decisions | Not available. Browser TLS errors are controlled by the browser. |
| HTTP auth callback | Not available as a WebView callback. |
| Cross-origin JavaScript | Blocked by browser same-origin policy. |

## Permission Mediation

For controllable HTML, the implementation wraps
`navigator.mediaDevices.getUserMedia` and reports camera/microphone requests to
`onPermissionRequest`. The browser may still show its own permission prompt
after your app grants the WebView request.

Custom `confirm` and `prompt` callbacks require synchronous same-origin access.
For isolated HTML the native browser dialogs remain active because a
synchronous browser API cannot safely wait for an asynchronous cross-frame
decision.

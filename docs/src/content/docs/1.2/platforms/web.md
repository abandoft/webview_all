---
title: Web
description: Browser iframe implementation, iframe attributes, fetch-backed requests, and security limits.
---

Web is provided by `webview_all_web 1.2.1` and renders an HTML `iframe`.

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
  iFrameSandbox: 'allow-same-origin allow-scripts allow-forms',
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

## Same-Origin Features

These APIs require same-origin iframe access:

- `runJavaScript`
- `runJavaScriptReturningResult`
- `addJavaScriptChannel`
- `removeJavaScriptChannel`
- console message hooks
- JavaScript dialog hooks
- scroll reads and writes
- `getTitle`

They work well with `loadHtmlString`, same-origin URLs, and fetch-backed loads whose response becomes same-origin `data:` content.

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

It cannot read `HttpOnly` cookies or manage cookies for unrelated domains.

## Unsupported or Limited APIs

| API | Behavior |
| --- | --- |
| `loadFile` | Throws `UnsupportedError`. |
| `setUserAgent(nonNull)` | Throws `UnsupportedError`. Browsers do not let page JavaScript override iframe network user agent. |
| SSL auth decisions | Not available. Browser TLS errors are controlled by the browser. |
| HTTP auth callback | Not available as a WebView callback. |
| Cross-origin JavaScript | Blocked by browser same-origin policy. |

## Permission Mediation

For same-origin content, the implementation wraps `navigator.mediaDevices.getUserMedia` and reports camera/microphone requests to `onPermissionRequest`. The browser may still show its own permission prompt after your app grants the WebView request.

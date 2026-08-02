---
title: Capability Matrix
description: Cross-platform feature support for webview_all 1.3.2.
---

Legend:

| Mark | Meaning |
| --- | --- |
| Full | Implemented by the platform engine or a typed bridge. |
| Limited | Implemented with documented engine, browser, or OS constraints. |
| No | Not available and expected to throw or no-op as documented. |

## Core WebView API

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `WebViewWidget` | Full | Full | Full | Full | Full | Full | Full |
| `loadRequest` GET | Full | Full | Full | Full | Full | Full | Full |
| `loadRequest` GET headers | Full | Full | Full | Full | Full | Full | Limited, CORS/fetch |
| `loadRequest` POST body | Full | Full | Full | Full | Full | Full | Limited, CORS/fetch |
| `loadRequest` POST headers | No | Full | Full | Full | Full | No | Limited, CORS/fetch |
| `loadFile` | Full | Full | Full | Full | Full | Full | No |
| `loadFlutterAsset` | Full | Full | Full | Full | Full | Full | Full |
| `loadHtmlString` | Full | Full | Full | Full | Full | Full | Full |
| `currentUrl` | Full | Full | Full | Full | Full | Full | Limited, logical URL for synthetic loads |
| History back/forward | Full | Full | Full | Full | Full | Full | Limited, controller-managed history |
| `reload` | Full | Full | Full | Full | Full | Full | Limited, reloads last controller load |
| `clearCache` | Full | Full | Full | Full | Full | Full | Limited, host-origin cache storage |
| `clearLocalStorage` | Full | Full | Full | Full | Full | Full | Limited, host-origin storage |

## Navigation and Errors

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `onNavigationRequest` | Full | Full | Full | Full | Full | Full | Limited, controller loads and observable iframe loads |
| `onPageStarted`/`onPageFinished` | Full | Full | Full | Full | Full | Full | Limited, iframe load events |
| `onProgress` | Full | Full | Full | Full | Full | Full | Limited, synthetic `0`/`100` plus load event |
| `onUrlChange` | Full | Full | Full | Full | Full | Full | Limited, logical URL where needed |
| `onWebResourceError` | Full | Full | Full | Full | Full | Full | Limited, fetch failures only for custom request path |
| `onHttpError` | Full | Full | Full | Full | Full | Full | Limited, fetch-backed loads expose response |
| HTTP auth callback | Full | Full | Full | Full | Full | Full | No browser iframe event |
| Recoverable SSL auth callback | Full | Full | Full | Full | Full | Full | No browser iframe event |

## JavaScript, UI, and Permissions

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| JavaScript enable/disable | Full | Full | Full | Full | Full | Full | Limited, iframe sandbox |
| `runJavaScript` | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| `runJavaScriptReturningResult` | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML; JSON-serializable |
| JavaScript channels | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| Console message callback | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| `alert` callback | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| `confirm` callback | Full | Full | Full | Full | Full | Full | Same-origin synchronous callback; isolated uses browser dialog |
| `prompt` callback | Full | Full | Full | Full | Full | Full | Same-origin synchronous callback; isolated uses browser dialog |
| Permission request callback | Full | Full | Full | Full | Full | Full | Controllable HTML media hook plus browser prompt |
| File selector callback | Full | No common callback | No common callback | No common callback | No common callback | Full | Browser-owned |
| Geolocation prompt callback | Full | No platform API | No platform API | Browser/engine-owned | Browser/engine-owned | Full | Browser-owned |
| Fullscreen custom widget | Full | Engine-owned | Engine-owned | Engine-owned | Engine-owned | Full | Browser-owned |

## View State and Styling

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `getTitle` | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| Scroll position read | Full | Full | No, logs and returns zero | Full | Full | Full | Same-origin or managed isolated HTML |
| Scroll position callback | Full | Full | No, logs and no-op | Full | Full | Full | Same-origin or managed isolated HTML |
| `scrollTo`/`scrollBy` | Full | Full | No, logs and no-op | Full | Full | Full | Same-origin or managed isolated HTML |
| Scrollbar visibility | Full | Full | No, logs and no-op | Full, CSS injection | Full | Full, CSS injection | Full, CSS injection |
| Background color | Full | Full | macOS 12+, logs and no-op earlier | Full | Full | Full | Full, iframe CSS |
| Zoom enable/disable | Full | Full | Full | Full | Full | Full | Limited, iframe touch action |
| User agent override | Full | Full | Full | Full | Full | Full | No; logs and ignores non-null override |
| Overscroll mode | Full | Limited | No, logs and no-op | Full, CSS injection | Full | Full, CSS injection | Full, iframe CSS |

## Platform API Highlights

| Platform | Important extra APIs |
| --- | --- |
| Android | debugging, media gesture, text zoom, wide viewport, content/file access, geolocation, file selector, custom fullscreen widget, console, JavaScript dialogs, scrollbars, overscroll, mixed content, Payment Request, insets. |
| iOS/macOS | inline media, media gesture policy, app-bound domains, JavaScript popup policy, back/forward gestures, link preview, inspectable, WebKit file read access, permission prompt forwarding. |
| Windows | WebView2 environment, runtime version, popup policy, DevTools, suspend/resume, zoom factor, cache disabled, virtual host mapping, extended cookies. |
| Linux | WebKitGTK developer extras, inspector, media settings, page cache, file URL access, font sizes, zoom factor, JavaScript dialogs, HTTP/SSL auth, permission requests. |
| OHOS | ArkWeb settings, debugging, file selector, geolocation prompts, custom fullscreen widget, third-party cookies, OHOS permission resource types. |
| Web | iframe attributes, sandbox/referrer policy, fetch-backed requests, isolated managed-HTML bridge, media permission mediation. |

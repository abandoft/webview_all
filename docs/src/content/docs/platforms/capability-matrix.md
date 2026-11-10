---
title: Capability Matrix
description: Compare WebView features and limitations across platforms.
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
| Controller use without `WebViewWidget` | Full | Full | Full | Full | Full | Page operations require an attached WebView; user scripts can be registered earlier | No, iframe must be attached |
| `loadRequest` GET | Full | Full | Full | Full | Full | Full | Full |
| `loadRequest` GET headers | Full | Full | Full | Full | Full | Full | Limited, CORS/fetch |
| `loadRequest` POST body | Full | Full | Full | Full | Full | Full | Limited, CORS/fetch |
| `loadRequest` POST headers | No | Full | Full | Full | Full | No | Limited, CORS/fetch |
| `loadFile` | Full | Full | Full | Full | Full | Full | No |
| `loadFlutterAsset` | Full | Full | Full | Full | Full | Full | Full |
| Application resource URLs, files and ranges | Supported; length and If-Range limits | Full | Full | Full | Full | Full | Unsupported; logs a diagnostic |
| Incremental application resource streams | Full | Full | Full | Unsupported; logs a diagnostic | Full | Full | Unsupported; logs a diagnostic |
| `loadHtmlString` | Full | Full | Full | Full | Full | Full | Full |
| `currentUrl` | Full | Full | Full | Full | Full | Full | Limited, logical URL for synthetic loads |
| History back/forward | Full | Full | Full | Full | Full | Full | Limited, controller-managed history |
| Stop loading | Full | Full | Full | Full | Full, including custom requests | Full | Cancels plugin requests; iframe stop is origin-limited |
| Query history / navigate to an index | Full | Full | Full | Full | Full | Full | Controller-managed logical history |
| `reload` | Full | Full | Full | Full | Full | Full | Limited, reloads last controller load |
| `clearCache` | Full | Full | Full | Full | Full | Full | Limited, host-origin cache storage |
| `clearLocalStorage` | Full | Full | Full | Full | Full | Full | Limited, host-origin storage |
| Controller-independent website-data clearing | Limited on older System WebView | Full | Full | Limited categories and older runtimes | Full | Limited categories | No, reports unsupported |
| Cookie expiry, Secure, HttpOnly and SameSite writes | Full | Full | Full | Full | Full | Full | Host cookies only; no HttpOnly |
| Cookie metadata reads | Native attributes on newer providers; names/values on older ones | Full | Full | Full | Full | Names/values only | Names/values only |
| Delete a cookie by identity | Full | Full | Full | Full | Full | Full | Visible host cookies only |
| Viewport PNG screenshots | Full | Full | Full | Full | Full | WebView surface | Unsupported, logs a limitation |
| PDF byte export | Unsupported, requires system print flow | Full | Full | Runtime-dependent | Requires GTK Print to File backend | Full | Unsupported |
| Selective website-data clearing | Cookies/cache; full native group on newer WebViews | Full | Full | Six native categories, Runtime-dependent | Full | Cookies and available shared cache | Unsupported |
| Native child-window attachment | Matching session; limited incognito shares data | Matching store, request factory | Matching store, request factory | Matching profile | Matching store, request factory | Unsupported | Unsupported |
| Native window.close notifications | Full | Full | Full | Full | Full | Unsupported | Unsupported |
| Fullscreen events and exit requests | Can supply a separate widget | iOS 16+; limited system video exit | macOS 13+; limited system video exit | Full | Full | Full | Iframe permissions and gestures |
| Renderer process failures | Android 8+; recreate | Reload | Reload | Recovery depends on process kind | Reload | Reload | Unsupported |

## Navigation and Errors

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `onNavigationRequest` | Full | Full | Full | Full | Full | Full | Limited, controller loads and observable iframe loads |
| `onPageStarted`/`onPageFinished` | Full | Full | Full | Full | Full | Full | Limited, iframe load events |
| `onProgress` | Full | Full | Full | Full | Full | Full | Limited, synthetic `0`/`100` plus load event |
| `onUrlChange` | Full | Full | Full | Full | Full | Full | Limited, logical URL where needed |
| `onTitleChange` | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
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
| `callAsyncJavaScript` with named arguments | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML; cross-origin iframe unavailable |
| Document-start user scripts | Runtime capability | Full | Full | Full | Full | Full | No, capability returns false |
| Document-end user scripts | Runtime capability; DOM-ready fallback | Full | Full | DOM-ready listener | Full | Full | Plugin-loaded HTML only |
| Promise handlers (`callHandler`) | Runtime capability | Main document | Main document | Main document | Main document | Main document | Same-origin or plugin-controlled HTML |
| Named isolated worlds | Runtime capability | Full | Full | No; logs and skips | Full | No; logs and skips | No; logs and skips |
| Handler origin restrictions | Runtime capability | Full | Full | No; registration skipped | Page world only | No; registration skipped | Full for controllable content |
| JavaScript channels | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| Console message callback | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| `alert` callback | Full | Full | Full | Full | Full | Full | Same-origin or managed isolated HTML |
| `confirm` callback | Full | Full | Full | Full | Full | Full | Same-origin synchronous callback; isolated uses browser dialog |
| `prompt` callback | Full | Full | Full | Full | Full | Full | Same-origin synchronous callback; isolated uses browser dialog |
| Permission request callback | Full | Full | Full | Full | Full | Full | Controllable HTML media hook plus browser prompt |
| WebAuthn/passkeys | Limited, explicit opt-in and app association | Limited, OS and Associated Domains | Limited, OS and Associated Domains | Limited, Runtime/OS/provider | No, WebKitGTK port | Not claimed; no documented ArkWeb host API | Limited, browser and iframe policy |
| Unified file selector callback | Full | iOS 18.4+ with a compatible build SDK | Full | No unified callback; logs | Full | Full | Browser-owned; logs |
| Text search | Case-insensitive, wrapping | No match count | No match count | Runtime capability, wrapping | Full, no active index | Case-insensitive, wrapping | Controllable HTML and browser support; no count |
| Unified popup policies | Default, deny, same view | Default, deny, same view | Default, deny, same view | Default, deny, same view | Default, deny, same view | Default, deny | No; logs |
| Creation-time media gesture policy | Full | Full | Full | No; logs | Full | Full | Browser-controlled; logs |
| Dynamic media gesture setting | Full | Requires a new view | Requires a new view | No; logs | Full | Full | Browser-controlled; logs |
| Geolocation prompt callback | Full | No platform API | No platform API | Browser/engine-owned | Browser/engine-owned | Full | Browser-owned |
| Separate fullscreen widget | Full | Engine-owned | Engine-owned | Engine-owned | Engine-owned | Engine-owned | Browser-owned |

See the [JavaScript guide](/webview_all/guides/javascript/) for registration order, access policies and runtime capability checks.

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
| Android | debugging, media gesture, text zoom, wide viewport, content/file access, geolocation, file selector, custom fullscreen widget, console, JavaScript dialogs, scrollbars, overscroll, mixed content, WebAuthn/passkeys, Payment Request, insets. |
| iOS/macOS | inline media, media gesture policy, app-bound domains, JavaScript popup policy, back/forward gestures, link preview, inspectable, WebKit file read access, permission prompt forwarding. |
| Windows | WebView2 environment, runtime version, popup policy, DevTools, suspend/resume, zoom factor, cache disabled, virtual host mapping, extended cookies. |
| Linux | WebKitGTK developer extras, inspector, media settings, page cache, file URL access, font sizes, zoom factor, JavaScript dialogs, HTTP/SSL auth, permission requests. |
| OHOS | ArkWeb settings, debugging, file selector, geolocation prompts, custom fullscreen widget, third-party cookies, OHOS permission resource types. |
| Web | iframe attributes, sandbox/referrer/permissions policy, fetch-backed requests, isolated managed-HTML bridge, media permission mediation. |


## Session modes (1.4.9)

| Mode | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `shared` | Full | Full | Full | Full | Full | Full | Full, iframe must be attached |
| `incognito` | Limited, shared website data | Full | Full | Runtime capability | Full | Shared native private store | No |
| `isolatedIncognito` | No | Full | Full | Runtime capability | Full | No | No |

Query `WebViewSession.getCapabilities()` for the running environment. Unsupported
creation requests print a diagnostic and return `null`.

## Profiles, network and page tools (1.5.x)

| Feature | Android | iOS | macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Named persistent profiles | Runtime MULTI_PROFILE | 17+ | 14+ | Runtime profile options | Full | No | No |
| List/delete named profiles | New providers; loaded profiles require restart | 17+, release native references | 14+, release native references | 120+; pending until browser exit | Supported; checks occupancy | Unsupported | Unsupported |
| Explicitly related private pages | Limited, ordinary data | Full | Full | Full | Full | Shared native private store | No |
| Native navigation state | Full | 15+ | 12+ | No | Full | Bounded native state | No |
| Clear native history | Full | No | No | Full | No | Full | No |
| Native full-document screenshots | Unsupported | Unsupported | Unsupported | Supported | Supported | Unsupported | Unsupported |
| Screenshot crop/scale | Full | Full | Full | Full | Full | Full | No |
| PDF paper/margins/orientation | No | Full | Full | Runtime-dependent | GTK Print to File | Full | No |
| System printing | Query/cancel job | Query/cancel job | Query; ambiguous cancel/failure | UI presented only | Query job | Query job | Same-origin, request only |
| Page archive | MHTML | WebArchive | WebArchive | MHTML | MHTML | MHTML | No |
| Scoped website data | Whole site group on newer WebViews | Domain records | Domain records | Exact origin | Domain records | No | No |
| Static content rules | URL only | Types, site conditions, CSS hiding, HTTPS upgrade | Types, site conditions, CSS hiding, HTTPS upgrade | Native types | Types, site conditions, CSS hiding, HTTPS upgrade | URL only | No |
| HTTP allow/block/respond | Limited | No | No | Full | No | No | No |
| Declared custom schemes | Limited bodies | Available native bodies | Available native bodies | At environment creation, file/bytes | Streaming; body 2.40+ | Before engine initialization | No |
| Native context menu toggle | No | No | Full | Full | Full | No | No |
| Mute audio | No | No | No | Full | Full | Full | No |
| Pause media / suspend playback | No | 15+ / 15+ | 12+ / 12+ | No | No | Pause only | No |

See [Profiles and Page Tools](/webview_all/guides/profiles-and-tools/) and
[Network Control](/webview_all/guides/network/) for scope, lifecycle and engine limitations.

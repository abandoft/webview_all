---
title: OHOS
description: ArkWeb implementation, APIs, and HarmonyOS/OpenHarmony limits.
---

OHOS is provided by `webview_all_ohos` and uses ArkWeb through the OHOS Flutter SDK. Starting with 1.4.5, the host application's minimum compatible SDK must be API 22 or newer; see [platform setup](/getting-started/platform-setup/#ohos).

## Engine

| Item | Value |
| --- | --- |
| Package | `webview_all_ohos` |
| Main platform class | `OhosWebViewPlatform` |
| Controller | `OhosWebViewController` |
| Widget | `OhosWebViewWidget` |
| Navigation delegate | `OhosNavigationDelegate` |
| Cookie manager | `OhosWebViewCookieManager` |
| Engine | ArkWeb |
| Minimum target | OHOS API 22+ |

## Creation Params

```dart
final params = OhosWebViewControllerCreationParams(
  isAllowFullScreenRotate: false,
  domStorageEnabled: true,
  javaScriptCanOpenWindowsAutomatically: true,
  supportMultipleWindows: true,
  loadWithOverviewMode: true,
  useWideViewPort: true,
  displayZoomControls: false,
  builtInZoomControls: true,
  allowFileAccess: true,
  mixedContentMode: OhosMixedContentMode.neverAllow,
  mediaPlaybackRequiresUserGesture: false,
  supportZoom: true,
  textZoom: 100,
);
```

## Controller API

| API | Purpose |
| --- | --- |
| `OhosWebViewController.enableDebugging(bool enabled)` | Enables ArkWeb debugging globally. |
| `webViewIdentifier` | Native WebView instance identifier for interop. |
| `setAllowFullScreenRotate(bool enabled)` | Controls fullscreen rotation behavior. |
| `setDomStorageEnabled(bool enabled)` | Enables DOM storage. |
| `setJavaScriptCanOpenWindowsAutomatically(bool enabled)` | Controls JavaScript popups. |
| `setSupportMultipleWindows(bool support)` | Retained for compatibility; requested windows continue in the current WebView. |
| `setLoadWithOverviewMode(bool overview)` | Controls overview mode. |
| `setUseWideViewPort(bool use)` | Enables wide viewport behavior. |
| `setDisplayZoomControls(bool enabled)` | Compatibility flag; does not provide native zoom buttons. |
| `setBuiltInZoomControls(bool enabled)` | Compatibility flag; use `setSupportZoom` to control page zoom. |
| `setAllowFileAccess(bool enabled)` | Controls file access. |
| `setMixedContentMode(OhosMixedContentMode mode)` | Controls mixed HTTP/HTTPS content. |
| `setSupportZoom(bool support)` | Controls page zoom, including Ctrl shortcuts and Ctrl with the mouse wheel. |
| `setMediaPlaybackRequiresUserGesture(bool require)` | Controls media autoplay policy. |
| `setTextZoom(int textZoom)` | Sets text zoom percentage. |
| `setOnShowFileSelector(callback)` | Handles file chooser requests. |
| `setGeolocationPermissionsPromptCallbacks(...)` | Handles geolocation permission prompts. |
| `setCustomWidgetCallbacks(...)` | Handles fullscreen custom views. |

## Runtime Settings and Scrolling

Settings such as JavaScript access, DOM storage, file access, media gesture policy, zoom, viewport, background color, text size, and mixed content can be configured before widget creation and updated while the WebView is displayed.

Changing the user agent or adding/removing JavaScript channels does not force a page reload. User-agent changes affect subsequent requests; newly registered channels normally become available in the next document. Reload explicitly when the current page needs the new channel.

`scrollTo` and `scrollBy` are supported. Position reads and scroll callbacks reflect the page's actual scroll offset, including clamping at the page edges.

The plugin keeps page-requested windows in the current WebView. `supportMultipleWindows` is retained for compatibility and does not create separate windows or tabs. `displayZoomControls` and `builtInZoomControls` do not guarantee native zoom controls. Use `supportZoom` to control page zoom, including `Ctrl` + `+`/`-` and `Ctrl` with the mouse wheel on API 22+.

## Document-Start Scripts

ArkWeb runs user scripts before page JavaScript, in registration order. Scripts can be registered before `WebViewWidget` is attached. Await `addUserScript` before starting navigation so the first page receives them.

Registration and removal apply to future documents and reloads. They neither execute scripts in the current document nor undo effects from scripts that already ran. See the [JavaScript guide](/guides/javascript/#document-start-user-scripts).

Navigation cancels pending `callAsyncJavaScript` invocations with `JavaScriptExecutionException` instead of returning a result from the previous document. Operations waiting for the view to become ready fail if the view is removed.

## Website Data

`WebViewDataManager.clearAllWebsiteData()` works without creating a WebView. It clears cookies, the resource cache shared by all WebViews, local storage, and WebSQL. Session storage, IndexedDB, Cache Storage, and service worker registrations are reported as unsupported. Inspect the returned clearing result; see [website data cleanup](/guides/cookies/#clear-all-website-data).

## Mixed Content

Starting with 1.4.4, HTTPS pages cannot load insecure HTTP resources by default. Serve these resources over HTTPS where possible. If legacy content requires a different policy, explicitly select `OhosMixedContentMode.compatibilityMode` or `OhosMixedContentMode.alwaysAllow` through creation parameters or `setMixedContentMode` before loading the page. Changing the policy does not remove resources already loaded. This setting does not block navigation to HTTP pages.

## `loadRequest` Behavior

| Request | Support |
| --- | --- |
| GET without headers | Supported through ArkWeb `loadUrl`. |
| GET with headers | Supported through ArkWeb `loadUrl`. |
| POST without custom headers | Supported through ArkWeb `postUrl`. |
| POST with custom headers | Not supported. Throws `UnsupportedError`. |

ArkWeb's `postUrl` API accepts a URL and body data, but not a custom header map. `webview_all_ohos` fails explicitly so applications do not assume headers were sent.

## Permissions

OHOS supports common `camera` and `microphone` resources, plus:

| Type | Meaning |
| --- | --- |
| `OhosWebViewPermissionResourceType.midiSysex` | MIDI sysex. |
| `OhosWebViewPermissionResourceType.protectedMediaId` | Protected media identifier. |

## File Selector

```dart
await (controller.platform as OhosWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  return <String>['/data/storage/el2/base/files/upload.png'];
});
```

## Cookie API

```dart
final cookieManager = WebViewCookieManager().platform
    as OhosWebViewCookieManager;

await cookieManager.setAcceptThirdPartyCookies(
  controller.platform as OhosWebViewController,
  true,
);
```

## Navigation Detail

OHOS-specific types add native request and response detail:

| Type | Extra fields |
| --- | --- |
| `OhosUrlChange` | `isReload`. |
| `OhosWebResourceRequest` | `isForMainFrame`, `isRedirect`, `hasGesture`, `method`, `headers`. |
| `OhosWebResourceResponse` | `reasonPhrase`, `mimeType`. |
| `OhosPlatformSslAuthError` | `url`, `errorCode`, `description`, `proceed()`, `cancel()`. |

## Web Authentication and Passkeys

The supported ArkWeb SDK surface does not currently document a host API for
enabling or brokering WebAuthn/passkeys. `webview_all_ohos` therefore does not
claim this capability or add an Android-shaped setting with no native
equivalent. Applications should test the standard web capability on every
target API level and device, keep another authentication method, and use a
supported external browser when passkeys are mandatory. No JavaScript
credential shim is installed.

## Known Limits

- POST with custom headers is not available through current ArkWeb `postUrl` APIs.
- Web content permission approval still requires the host app to hold the matching OHOS permission.
- WebAuthn/passkey behavior is not guaranteed by the documented ArkWeb host
  APIs and must not be assumed from ArkWeb's browser engine alone.
- ArkWeb behavior can vary across HarmonyOS/OpenHarmony versions, especially for media, file picker, and permission surfaces. Test on the target API level.

## Isolated Toolchain

Do not run stock Flutter and the OHOS Flutter SDK in the same package
directory: both write `.dart_tool/package_config.json`, but their SDK package
sets are incompatible. Use the repository helper to run OHOS commands in a
temporary copy that also includes current uncommitted changes:

```sh
OHOS_FLUTTER=/absolute/path/to/ohos/flutter \
  ./tool/run_ohos_flutter.sh -- analyze

OHOS_FLUTTER=/absolute/path/to/ohos/flutter \
  ./tool/run_ohos_flutter.sh --workdir webview_all/example -- build hap
```

The helper requires an explicit absolute SDK path, excludes generated/cache
directories while copying, and always removes the temporary workspace. The
real repository's `.dart_tool` directories are untouched.

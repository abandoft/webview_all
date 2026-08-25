---
title: OHOS
description: ArkWeb implementation, APIs, and HarmonyOS/OpenHarmony limits.
---

OHOS is provided by `webview_all_ohos 1.3.10` and uses ArkWeb through the OHOS Flutter SDK.

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
| Minimum target | OHOS API 12+ |

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
| `setSupportMultipleWindows(bool support)` | Enables multiple window support. |
| `setLoadWithOverviewMode(bool overview)` | Controls overview mode. |
| `setUseWideViewPort(bool use)` | Enables wide viewport behavior. |
| `setDisplayZoomControls(bool enabled)` | Shows or hides zoom controls. |
| `setBuiltInZoomControls(bool enabled)` | Enables built-in zoom controls. |
| `setAllowFileAccess(bool enabled)` | Controls file access. |
| `setSupportZoom(bool support)` | Enables zoom support. |
| `setMediaPlaybackRequiresUserGesture(bool require)` | Controls media autoplay policy. |
| `setTextZoom(int textZoom)` | Sets text zoom percentage. |
| `setOnShowFileSelector(callback)` | Handles file chooser requests. |
| `setGeolocationPermissionsPromptCallbacks(...)` | Handles geolocation permission prompts. |
| `setCustomWidgetCallbacks(...)` | Handles fullscreen custom views. |

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

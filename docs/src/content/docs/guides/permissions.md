---
title: Permissions
description: Handle camera, microphone, geolocation, media, and file selector permission flows.
---

Web content permission flow has two layers:

1. The app must have the operating system permission.
2. The WebView must approve the web page request.

`WebViewController(onPermissionRequest: ...)` or `setOnPlatformPermissionRequest` handles the WebView layer.

```dart
final controller = WebViewController(
  onPermissionRequest: (WebViewPermissionRequest request) async {
    if (request.types.contains(WebViewPermissionResourceType.camera)) {
      await request.grant();
    } else {
      await request.deny();
    }
  },
);
```

Call `grant()` or `deny()` once. Platform request objects ignore duplicate decisions where possible.

## Common Resource Types

| Type | Meaning |
| --- | --- |
| `WebViewPermissionResourceType.camera` | Camera capture. |
| `WebViewPermissionResourceType.microphone` | Audio capture. |

## Platform-Specific Resource Types

| Platform | Type | Meaning |
| --- | --- | --- |
| Android | `AndroidWebViewPermissionResourceType.midiSysex` | MIDI sysex access. |
| Android | `AndroidWebViewPermissionResourceType.protectedMediaId` | Protected media identifier. |
| OHOS | `OhosWebViewPermissionResourceType.midiSysex` | MIDI sysex access. |
| OHOS | `OhosWebViewPermissionResourceType.protectedMediaId` | Protected media identifier. |

## Geolocation

Android and OHOS expose geolocation prompt callbacks:

```dart
final android = controller.platform as AndroidWebViewController;

await android.setGeolocationPermissionsPromptCallbacks(
  onShowPrompt: (GeolocationPermissionsRequestParams request) async {
    return const GeolocationPermissionsResponse(
      allow: true,
      retain: false,
    );
  },
  onHidePrompt: () {
    debugPrint('Geolocation prompt hidden');
  },
);
```

Use the OHOS controller the same way:

```dart
final ohos = controller.platform as OhosWebViewController;
await ohos.setGeolocationPermissionsPromptCallbacks(
  onShowPrompt: (request) async {
    return const GeolocationPermissionsResponse(
      allow: true,
      retain: false,
    );
  },
);
```

Geolocation generally requires secure origins (`https`) in modern engines.

## File Selector

Android and OHOS expose file chooser callbacks:

```dart
await (controller.platform as AndroidWebViewController)
    .setOnShowFileSelector((FileSelectorParams params) async {
  debugPrint('accept=${params.acceptTypes}');
  return <String>['/path/to/file.png'];
});
```

`FileSelectorParams` includes:

| Field | Meaning |
| --- | --- |
| `isCaptureEnabled` | The page prefers live capture such as camera or microphone. |
| `acceptTypes` | MIME types accepted by the page. |
| `filenameHint` | Suggested filename when the mode allows saving. |
| `mode` | `open`, `openMultiple`, or `save`. |

## Fullscreen Custom Widgets

Android and OHOS can request a custom widget for fullscreen content such as video:

```dart
await (controller.platform as OhosWebViewController)
    .setCustomWidgetCallbacks(
  onShowCustomWidget: (Widget widget, VoidCallback onHidden) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => widget,
      ),
    );
  },
  onHideCustomWidget: () {
    Navigator.of(context).pop();
  },
);
```

If a callback is not set, Android and OHOS widgets install a default fullscreen route handler.

## Web Permissions

The web implementation can mediate `navigator.mediaDevices.getUserMedia` for
same-origin content and plugin-managed isolated HTML by wrapping the page API.
It can report camera and microphone requests to `onPermissionRequest`.

The browser still owns the final permission prompt. `request.grant()` only allows the page call to continue to the browser permission layer.

## Unified file selection

```dart
final capabilities = await controller.getBrowserCapabilities();
if (capabilities.fileSelector) {
  await controller.setFileSelector((request) async {
    // Use your application's picker. Return paths; Android also accepts content URIs.
    // request.mode, acceptTypes, and isCaptureEnabled describe this request.
    return <String>[]; // An empty list cancels.
  });
}
await controller.setFileSelector(null); // Restore the engine's default behavior.
```

Android, Linux, OHOS, and macOS support custom selection. iOS requires 18.4+ and a
compatible build SDK; earlier systems retain native selection. Windows and Web
currently print a diagnostic when a custom callback is requested. Apple does not
expose MIME or capture hints. Missing hints are `null` or empty lists. Picker
exceptions cancel the selection.

## Popup policies

```dart
await controller.setPopupPolicy(WebViewPopupWindowPolicy.deny);
await controller.setPopupPolicy(WebViewPopupWindowPolicy.platformDefault);
```

`platformDefault` restores the platform's existing policy, `deny` rejects popups,
and `sameView` loads the target in the current view. Query
`getBrowserCapabilities().popupWindowPolicies` for available policies. OHOS supports
default and deny; Web has no unified override. `sameView` does not create a child
window and cannot guarantee `window.opener` or form POST semantics. Retain platform
defaults when those semantics are required.

## Media playback policy

Choose a policy before creating the view:

```dart
final controller = WebViewController(
  mediaPlaybackPolicy: WebViewMediaPlaybackPolicy.requireUserGesture,
);
```

Android, iOS, macOS, Linux, and OHOS support creation-time configuration. Omitting
the option keeps defaults. Android, Linux, and OHOS also support dynamic changes
with `setMediaPlaybackRequiresUserGesture`. Apple requires a new WebView to change
this configuration. Windows and Web print a diagnostic and retain engine policy
when per-view configuration is unavailable. Allowing autoplay remains subject to
engine, site, and system policies.

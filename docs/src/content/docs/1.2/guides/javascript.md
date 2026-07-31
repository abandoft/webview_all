---
title: JavaScript
description: Execute JavaScript, receive messages, handle dialogs, and capture console output.
---

JavaScript support is split into four areas: execution, return values, channels, and browser-style dialogs.

## Enable or Disable JavaScript

```dart
await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
```

Disable JavaScript for untrusted content when your app does not need page scripting:

```dart
await controller.setJavaScriptMode(JavaScriptMode.disabled);
```

The web implementation applies a restrictive iframe sandbox when JavaScript is disabled and restores the configured sandbox when JavaScript is unrestricted.

## Execute Scripts

```dart
await controller.runJavaScript('document.body.classList.add("ready")');

final value = await controller.runJavaScriptReturningResult(
  'JSON.stringify({title: document.title})',
);
```

Return-value behavior:

| Platform | Return behavior |
| --- | --- |
| Android | Uses Android WebView evaluation result. |
| iOS/macOS | Uses WebKit evaluation; unsupported native values may throw. |
| Windows | Uses WebView2 script execution and decodes returned values. |
| Linux | Uses WebKitGTK and decodes JSON-marked results where needed. |
| OHOS | Uses ArkWeb `evaluateJavascript`; JSON is decoded when possible. |
| Web | Uses iframe `eval` for same-origin content and JSON serialization. |

`null` and `undefined` are rejected by `runJavaScriptReturningResult`.

## JavaScript Channels

```dart
await controller.addJavaScriptChannel(
  'Checkout',
  onMessageReceived: (JavaScriptMessage message) {
    debugPrint('Checkout event: ${message.message}');
  },
);
```

Page JavaScript:

```js
Checkout.postMessage(JSON.stringify({ type: 'loaded' }));
```

Remove a channel when it is no longer needed:

```dart
await controller.removeJavaScriptChannel('Checkout');
```

## Console Messages

```dart
await controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
  debugPrint('[${message.level.name}] ${message.message}');
});
```

Android, iOS, macOS, Windows, Linux, OHOS, and same-origin web content support console message callbacks.

## JavaScript Dialogs

```dart
await controller.setOnJavaScriptAlertDialog((request) async {
  debugPrint('alert from ${request.url}: ${request.message}');
});

await controller.setOnJavaScriptConfirmDialog((request) async {
  return request.message == 'Continue?';
});

await controller.setOnJavaScriptTextInputDialog((request) async {
  return request.defaultText ?? '';
});
```

Dialog support by platform:

| Platform | `alert` | `confirm` | `prompt` | Notes |
| --- | --- | --- | --- | --- |
| Android | Supported | Supported | Supported | Native WebChromeClient bridge. |
| iOS/macOS | Supported | Supported | Supported | WebKit UI delegate bridge. |
| Windows | Supported | Supported | Supported | WebView2 JavaScript dialog bridge. |
| Linux | Supported | Supported | Supported | WebKitGTK dialog events. |
| OHOS | Supported | Supported | Supported | ArkWeb WebChromeClient bridge. |
| Web | Same-origin only | Same-origin only | Same-origin only | `confirm` and `prompt` callbacks must complete synchronously. |

On web, `confirm` and `prompt` are browser-synchronous APIs. Return a `SynchronousFuture` from those callbacks if you need deterministic behavior:

```dart
await controller.setOnJavaScriptConfirmDialog((request) {
  return SynchronousFuture<bool>(true);
});
```

## Web Same-Origin Rule

Browser iframes block direct scripting of cross-origin pages. On web, these APIs require content that the host page can access:

- `runJavaScript`
- `runJavaScriptReturningResult`
- `addJavaScriptChannel`
- `setOnConsoleMessage`
- JavaScript dialog hooks
- scroll position reads and writes

Use `loadHtmlString`, same-origin URLs, or fetch-backed `loadRequest` when you need those features in Flutter Web.

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
| Web | Uses direct iframe `eval` for same-origin content and a source-validated message bridge for plugin-managed isolated HTML. Results must be JSON-serializable. |

`null` and `undefined` are rejected by `runJavaScriptReturningResult`.

## Await Promises

Use `callAsyncJavaScript` when the function body returns a Promise or needs structured named arguments:

```dart
final result = await controller.callAsyncJavaScript(
  '''
  const response = await fetch(endpoint);
  return {status: response.status, body: await response.text()};
  ''',
  arguments: <String, Object?>{
    'endpoint': 'https://example.com/api',
  },
  timeout: const Duration(seconds: 15),
);
```

Argument names must be valid non-reserved JavaScript identifiers. Values are defensively copied and must contain only finite numbers, strings, booleans, null, lists, and string-keyed maps. Fulfilled values must be JSON-serializable; a thrown error or rejected Promise produces `JavaScriptExecutionException`, while expiration produces `TimeoutException`.

Android, iOS, macOS, Windows, Linux, and OHOS support this API. Web supports same-origin content and plugin-managed isolated HTML; direct cross-origin iframe pages remain inaccessible.

## Document-Start User Scripts

Register a provider or compatibility shim before loading the first page:

```dart
if (await controller.isUserScriptInjectionSupported(
  WebViewUserScriptInjectionTime.documentStart,
)) {
  final scriptId = await controller.addUserScript(
    const WebViewUserScript(
      source: 'globalThis.appProvider = Object.freeze({version: 1});',
      forMainFrameOnly: true,
    ),
  );

  await controller.loadRequest(Uri.parse('https://example.com'));
  // Later: await controller.removeUserScript(scriptId);
}
```

`addUserScript` must finish before navigation begins. Scripts execute in the same private function scope on every supported platform, so values intended for page code or another user script must be assigned explicitly to `globalThis`. This lexical scope is not a separate browser content world. Scripts apply to future documents and reloads; they do not retroactively run in the current document. `removeAllUserScripts` removes only scripts registered through this API and preserves plugin-managed channels and hooks.

| Platform | Document-start support |
| --- | --- |
| Android | Supported when the installed Android System WebView exposes `DOCUMENT_START_SCRIPT`; check the capability at runtime. |
| iOS/macOS | Supported by `WKUserScript`. |
| Windows | Supported by WebView2. |
| Linux | Supported by WebKitGTK. |
| OHOS | Not exposed by the current ArkWeb bridge; capability returns false. |
| Web | Browser iframe APIs cannot guarantee execution before page scripts; capability returns false. |

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

Android, iOS, macOS, Windows, Linux, OHOS, and controllable Web content
support console message callbacks.

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
| Web | Same-origin or managed isolated HTML | Same-origin callback; isolated HTML keeps the browser dialog | Same-origin callback; isolated HTML keeps the browser dialog | Custom `confirm` and `prompt` callbacks must complete synchronously. |

On web, `confirm` and `prompt` are browser-synchronous APIs. Return a
`SynchronousFuture` from those callbacks if you need deterministic behavior
for same-origin content:

```dart
await controller.setOnJavaScriptConfirmDialog((request) {
  return SynchronousFuture<bool>(true);
});
```

## Web Same-Origin Rule

Browser iframes block direct scripting of cross-origin pages. On web, these APIs require content that the host page can access:

- `runJavaScript`
- `runJavaScriptReturningResult`
- `callAsyncJavaScript`
- `addJavaScriptChannel`
- `setOnConsoleMessage`
- JavaScript dialog hooks
- scroll position reads and writes

Use `loadHtmlString`, same-origin URLs, or fetch-backed `loadRequest` when you
need those features in Flutter Web. Direct cross-origin iframe URLs remain
inaccessible. Isolated HTML keeps browser-native `confirm` and `prompt`
dialogs because synchronous callbacks cannot cross the frame boundary.

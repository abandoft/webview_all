---
title: JavaScript
description: Execute JavaScript, receive messages, handle dialogs, and capture console output.
---

Execute JavaScript, exchange asynchronous calls with Dart, install user scripts, and handle console output and dialogs.

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
| OHOS | Supported by ArkWeb; scripts run in registration order and can be registered before the widget is attached. |
| Web | Browser iframe APIs cannot guarantee execution before page scripts; capability returns false. |

## Document-End Scripts and Isolated Worlds

Use `tryAddUserScript` to warn and return `null` when a requested feature is unavailable:

```dart
const world = WebViewJavaScriptWorld.isolated('app');
final scriptId = await controller.tryAddUserScript(
  const WebViewUserScript(
    source: 'globalThis.appReady = document.body != null;',
    injectionTime: WebViewUserScriptInjectionTime.documentEnd,
    world: world,
  ),
);
```

`documentEnd` runs when the DOM is ready, without waiting for all subresources. Its order relative to the website's `DOMContentLoaded` listeners can differ between engines. Windows and older supported Android WebViews install an early DOM-ready listener. Web supports this timing only in HTML loaded by the plugin, rather than ordinary URL loads.

Android (with a supporting System WebView), iOS, macOS and Linux support named isolated worlds. They separate JavaScript globals while sharing the DOM; cookies and website storage are not isolated. Windows, OHOS and Web skip isolated-world operations with a warning. Register Android worlds before loading the document.

Pass the same `world` to `callAsyncJavaScript` to execute in that environment. Unsupported worlds return `null` with a warning and never execute in the page world. The existing `addUserScript` keeps its strict failure contract; use `tryAddUserScript` for optional features.

## JavaScript Calls with Dart Return Values

Register handlers before user scripts and before loading the document:

```dart
final registered = await controller.addJavaScriptHandler(
  'appInfo',
  accessPolicy: WebViewJavaScriptAccessPolicy.origins(
    {'https://app.example.com'},
    mainFrameOnly: true,
  ),
  onCall: (call) async => {'name': 'Example', 'arguments': call.arguments},
);
```

Page JavaScript can await the result:

```js
async function callApp() {
  await window.webviewAll.ready;
  return await window.webviewAll.callHandler('appInfo', {language: 'en'});
}
if (window.webviewAll) {
  callApp().catch(console.warn);
} else {
  window.addEventListener('webviewAllReady', () => callApp().catch(console.warn), {once: true});
}
```

Arguments and return values accept only JSON-compatible values. Requests and result values are limited to 1 MiB of UTF-8 JSON, with up to 128 pending calls per controller.

Handler failures, invalid results, removal and timeouts reject the Promise with a `code`, such as `handler_error`, `serialization_error`, `aborted` or `timeout`. The default handler timeout is 30 seconds, configurable up to five minutes. Dart errors do not expose private exception details to the page.

Origin policies match exact HTTP(S) security origins, including ports, using engine-verified information. Unknown and opaque origins are rejected. Windows and OHOS cannot enforce these origin policies; Linux isolated-world handlers also lack verified sender metadata. Registration returns `false` and prints a warning when a policy cannot be enforced. For content you control, explicitly select `const WebViewJavaScriptAccessPolicy.unrestricted()` when no origin/frame restriction is needed; the plugin never weakens a restricted policy automatically.

Promise handlers currently run in the main document. Web requires same-origin pages or plugin-controlled HTML, and cannot inject into arbitrary cross-origin URLs. `getJavaScriptCapabilities(world: world)` reports the supported timing, worlds, metadata and content restrictions. World-aware handlers use the optional `world` argument.

Use `removeJavaScriptHandler(name, world: world)` or `removeAllJavaScriptHandlers()` to unregister callbacks. Navigation and disposal cancel pending calls; late results cannot enter a replacement document. Same-document history changes keep calls alive. A callback can await `call.cancelled` to stop its own work; the plugin cannot undo Dart side effects. Removing user scripts preserves the internal Promise bridge and existing string channels.

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

`JavaScriptMessage` reports the sending document URL (`sourceUrl`), browser security origin (`sourceOrigin`), and main-frame flag (`isMainFrame`) separately. Each field is nullable when the platform cannot reliably determine it. The string `"null"` in `sourceOrigin` means an opaque origin; Dart `null` means unknown.

| Platform | sourceUrl | sourceOrigin | isMainFrame |
| --- | --- | --- | --- |
| Android | — | When supported | When supported |
| iOS / macOS | Available | Available | Available |
| Windows | Available | — | true (main document only) |
| Linux | Available | Available | Available |
| OHOS | Available | — | — |
| Web | — | Available | true (WebView main document only) |

Android selects the implementation using the WebView's message-listener and document-start script capabilities; older WebViews still deliver messages with unknown sender fields. Linux reads metadata in an isolated script world, so messages after `pushState` reflect the new URL. If the isolated relay is not ready, or the page calls a low-level message handler directly, delivery continues with unknown metadata. OHOS captures the document URL at the native proxy entry, but cannot reliably determine the security origin or frame identity.

Reject unknown senders for sensitive operations. Never substitute `controller.currentUrl()` for missing metadata or derive a security origin from `sourceUrl`: a sandboxed document can have an HTTPS URL and an opaque origin. This example accepts main-document messages from an allowed security origin; platforms without reliable origin information reject them:

```dart
await controller.addJavaScriptChannel(
  'Checkout',
  onMessageReceived: (JavaScriptMessage message) {
    if (message.isMainFrame != true ||
        message.sourceOrigin != 'https://shop.example.com') {
      return;
    }
    debugPrint('Accepted checkout event: ${message.message}');
  },
);
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

---
title: Network Control
description: Native content rules, HTTP decisions and declared custom schemes.
---

## Query native capabilities

`getNetworkCapabilities()` reports native features independently. Unsupported
configuration logs the reason and returns `false`; the app continues running.
This API does not inject fetch/XHR hooks or replay an allowed request through Dart.

| Feature | Android | iOS / macOS | Windows | Linux | OHOS | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Static block/allow rules | URL only | Native resource types | Native resource types | Native resource types | URL only | Unsupported |
| HTTP(S) allow/block/respond | Limited WebView interception | Unsupported | WebView2 interception | Unsupported | Unsupported | Unsupported |
| HTTP request body | Unavailable | — | Cloneable bounded bodies | — | — | — |
| Declared custom schemes | Supported | Non-engine schemes | At environment creation | WebKit context registration | Before WebEngine initialization | Unsupported |
| Custom request body | Unavailable | Available body only | Cloneable bounded bodies | WebKitGTK 2.40+ | Non-chunked bounded bodies | — |
| Incremental responses | Supported | Supported | Files/bytes only | Supported | Supported | — |

Native engines differ in redirects, worker requests and resource classification.
Check `resourceTypes`, `requestBodies`, `customSchemeRequestBodies` and `limitation`.
Bodies above 4 MiB or inaccessible native streams are marked `bodyAvailable: false`,
with `body == null`; this does not mean the request had an empty body.
`isForMainFrame` is nullable where the native engine provides no reliable value.
Do not use these delegates as a universal firewall for every browser request.

Android can navigate to custom-scheme pages, but Chromium rejects custom-scheme fetch/XHR before interception. Check `customSchemeFetch`; use plugin resource URLs when JavaScript needs to fetch local data.

## Static rules

```dart
await controller.setContentRules([
  WebViewContentRule(urlPattern: 'https://ads.example/*'),
  WebViewContentRule(
    urlPattern: 'https://ads.example/required.js',
    action: WebViewContentRuleAction.allow,
  ),
]);
await controller.setContentRules([]); // Remove this controller's rules.
```

Patterns match the complete URL; `*` matches any character sequence. Matching is
case-insensitive by default, and the last matching block/allow rule wins. At most 256 rules
are accepted. `resourceTypes` is optional; requesting an unsupported type rejects
the update instead of broadening it. A rejected compilation retains the old rules.
Rules run before resource delegates. An `allow` rule permits later delegates to
handle the request; it does not bypass browser security or other app policies.

## HTTP request decisions

```dart
await controller.setRequestDelegate(WebViewRequestDelegate(
  urlPatterns: ['https://example.com/api/*'],
  onRequest: (request) async {
    if (request.uri.path.endsWith('/blocked')) {
      return const WebViewRequestDecision.block();
    }
    return const WebViewRequestDecision.allow();
  },
));
await controller.setRequestDelegate(null);
```

Use `WebViewRequestDecision.respond(WebViewResourceResponse.bytes(...))` to provide
a response. Allow resumes the original native request with its body, cookies and
headers; it never starts a second HTTP request. Android's callback cannot expose
POST bodies and does not cover every redirect or worker request. Apple has no
public general HTTP interception API. Linux/OHOS cannot safely resume an already
claimed asynchronous request, so this delegate remains unsupported there.
Replacing or removing a delegate cancels its pending decisions; a late `allow`
does not retry a cancelled request. Complete decisions promptly; native requests
have bounded lifetimes.

## Custom schemes

Declare schemes **before creating the first native environment**, then attach a
per-controller delegate. The declaration is creation-time configuration:

```dart
final controller = WebViewController.fromPlatformCreationParams(
  const PlatformWebViewControllerCreationParams(customSchemes: ['appdata']),
);
await controller.setCustomSchemeDelegate(WebViewResourceDelegate(
  onRequest: (request) => WebViewResourceResponse.bytes(
    Uint8List.fromList(utf8.encode('<h1>Local page</h1>')),
    mimeType: 'text/html',
  ),
));
await controller.loadRequest(Uri.parse('appdata://assets/index.html'));
```

Import `dart:convert` and `dart:typed_data` for this example. Use lowercase ASCII
scheme names; reserved engine schemes cannot be replaced. Windows requires the
`scheme://host/path` form and reuses the process's existing environment. Additional
schemes cannot be added after that environment starts. OHOS allows at most 10
registered schemes per process and requires registration before WebEngine starts;
other declarations are bounded to 16 per configuration. Failed registration does
not stop ordinary page loading.

Schemes are not marked secure/local and do not bypass CSP or CORS. Supply suitable
response headers for cross-origin use; browser fetch restrictions still apply.
Delegates remain per controller even when native registration belongs to an
engine/context. Removing one delegate does not remove another page's handler.
Application resource URLs (`setResourceDelegate` / `getResourceUri`) remain
separate and are preferable when arbitrary scheme names are unnecessary.

Responses use the same bounded file/bytes/stream and range handling as application
resources. Windows supports file and byte responses. Stream cancellation is
forwarded when the page or delegate closes; release your own producer resources
in response to cancellation.

## Site conditions and native actions

On Apple and Linux, rules also support `ifDomains`, `unlessDomains`, `ifTopUrls`,
`unlessTopUrls`, and `loadTypes` (`firstParty` / `thirdParty`). Domains are lowercase
ASCII; a leading `*` includes subdomains. Supply at most one nonempty domain or
top-URL condition list in a rule. Top-URL values use the same bounded wildcard
syntax as `urlPattern` and refer to the main document.

`hideElements` uses a native CSS selector (`selector: '.advertisement'`), and
`upgradeToHttps` uses the engine's HTTPS-upgrade rule. These actions may accumulate;
`allow` ignores preceding matching rules. Native CSS syntax and HTTPS/port rules
apply; invalid CSS selectors may be ignored by WebKit. Query `ruleActions` and
`ruleConditions`. Unsupported combinations reject the whole update and retain
existing rules, without silently applying a broader URL-only rule.

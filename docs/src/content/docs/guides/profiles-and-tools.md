---
title: Profiles and Page Tools
description: Share selected website data, restore native navigation state, export pages, and print.
---

## Profiles and related pages

`WebViewProfile` owns a website-data store and creates related `WebViewSession`s.
Unnamed profiles default to `isolatedIncognito`; named profiles default to persistent
`shared` storage. Unsupported requests log the reason and return `null`.

```dart
final profile = await WebViewProfile.create(name: 'account_1');
if (profile == null) return;
final first = await profile.createSession();
final second = await profile.createSession();
// These pages share this profile's cookies and persistent website data.
// Display each session.controller with its own WebViewWidget.
await profile.close(); // Stop creating pages; existing pages remain usable.
// Remove the widgets before closing their sessions.
await first?.close();
await second?.close();
await profile.whenReleased;
```

Named profiles require Android's runtime `MULTI_PROFILE` feature, iOS 17 / macOS 14,
WebView2 profile options, or Linux WebKitGTK. Names contain 1–64 ASCII letters,
digits, underscores or hyphens. Use a stable name to reopen persistent data.
Closing a profile does not delete that data; clear it explicitly through its managers.
OHOS and Web do not expose independent named stores.

Private profiles on Apple, Windows and Linux share one temporary store among their
explicitly related pages. Closing one page does not clear another page's data.
Android `incognito` remains limited and shares ordinary data; request it explicitly
with `mode: WebViewSessionMode.incognito` only if that behavior is acceptable.
OHOS private pages share the engine's private store. Check `getCapabilities()`.
Native popup children created with `request.createController()` retain the opener's
profile; the app still owns each child's UI and closure.


## Manage saved profiles

```dart
final manager = WebViewProfileManager();
final profiles = await manager.listProfiles();
final result = await manager.requestDeletion('account_1');
if (result.isDeleted) {
  // The native store has been removed.
}
```

Only plugin-owned **named persistent profiles** are listed or deleted. Default
and private stores are excluded. Close their sessions, remove their widgets, and
dispose saved navigation states first. Deletion invalidates old managers and
configuration handles for that profile; create new ones after deletion.

Inspect `result.status`: `busy` means native references still use the store;
`pending` means deletion is still running or native disk cleanup is unfinished;
`requiresRestart` means retry before loading the profile in a subsequent app
process. Android cannot delete profiles loaded in the current process. Windows
removes pending files after its browser process exits; the pending name cannot
be reopened. Windows profile names are case-insensitive. Apple requires iOS 17/macOS 14 and can report a busy native store
while WebKit releases it. Linux rejects deletion while views, navigation snapshots,
or another process hold the profile. `unknown` does not mean no deletion occurred:
query again before retrying. Unsupported platforms warn and return `null` or
`unsupported`; they never clear the ordinary store as a fallback.


## Native navigation state

```dart
final state = await controller.saveNavigationState();
if (state != null) {
  final target = await profile.createSession(); // A fresh page in the same store.
  final accepted = await target?.controller.restoreNavigationState(state);
  // Observe navigation callbacks before interacting with the restored page.
  await state.dispose();
}
await controller.clearNavigationHistory();
```

State is an opaque, memory-only native handle. It cannot be serialized and must
be restored in a compatible store in the same Flutter engine. Android, Apple and
Linux use their native state APIs; OHOS stores bounded native state. Windows and
Web do not expose this restore operation. Engine state does not guarantee saving
JavaScript memory or resuming network requests. Dispose unused handles; at most
16 may be retained per engine. History clearing is supported on Android, Windows
and OHOS; unsupported engines return `false` without reloading the current URL.

Android requires a fresh target WebView for `restoreState`. Check `navigationStateRequiresNewView` and create a new related session in the same profile; attempting to restore into a page that has navigated returns `false` and retains it.

## Screenshots, PDF and archives

```dart
final png = await controller.takeScreenshot(
  options: const WebViewScreenshotOptions(
    region: Rect.fromLTWH(0, 0, 200, 100), scale: 2,
  ),
);
final pdf = await controller.createPdf(
  options: const WebViewPdfOptions(
    paperSize: Size(595.28, 841.89),
    margins: EdgeInsets.all(28.35), landscape: false,
  ),
);
final archive = await controller.createArchive(format: WebViewArchiveFormat.mhtml);
```

Set `WebViewScreenshotOptions(fullDocument: true)` for a native whole-document
PNG on Windows or Linux. Query `fullDocumentScreenshot` first. Other engines
warn and return `null`; the plugin does not scroll or stitch the page. Lazy-loaded
or protected content may be absent. The same pixel/output limits apply.

Screenshot regions use **source PNG pixels**, not Flutter logical pixels. Captures
exclude Flutter overlays and may omit protected video. The source/output limit is
16 megapixels; invalid or out-of-bounds regions return `null` with a diagnostic.
PDF paper sizes and margins use **points (72 per inch)**. Passing no PDF options
preserves the engine's default layout. Android offers system printing instead of
PDF bytes. OHOS captures the WebView surface and exports PDFs with ArkWeb.
Web has neither screenshot nor PDF export.

Query `getBrowserCapabilities()` before choosing an archive format: Apple exports
WebArchive; Android, Windows, Linux and OHOS export MHTML. Archives are engine
snapshots, not a guarantee of a complete offline application or saved login state.
Export bytes are bounded to 64 MiB. The app chooses where to save or share them.
Linux PDF export requires GTK's Print to File backend.

On macOS, configured PDF export fits the engine’s vector page layout to the printable width and splits it across sheets; it does not reflow HTML at the paper width.

## System printing

```dart
final job = await controller.printPage(jobName: 'Receipt');
if (job != null) {
  final state = await job.getState();
  if (job.canCancel) await job.cancel();
  await job.dispose();
}
```

Printing opens platform-owned UI. On Android an Activity is required; other native
views must be attached to a window. Android, Apple, Linux and OHOS expose available
job events. Windows reports that the native UI was presented; same-origin Web
reports `requested`, because browsers cannot confirm whether print UI opened.
A completed job means native processing/spooling completed, not that paper was
physically printed. macOS cannot distinguish cancellation from every print error;
it reports `cancelledOrFailed`. Programmatic cancellation is available on Android
and iOS. Releasing a handle does not cancel an OS-owned job. Do not assume a print
dialog will finish within a fixed time.

On Android, cancelling a job does not guarantee dismissing the system print Activity; the user may still need to close it.


`jobName` is a hint on engines that accept it; Windows, Linux and Web retain their native page/browser title.

## Website data scopes

```dart
final manager = session.dataManager;
final caps = await manager.getCapabilities();
final origin = WebViewDataTarget.origin(Uri.parse('https://example.com'));
final records = await manager.getWebsiteDataRecords(target: origin);
final result = await manager.clearWebsiteDataFor(
  origin, dataTypes: {WebViewDataType.localStorage},
);
// Check result.clearedDataTypes, unsupportedDataTypes and failures.
```

Scope is explicit: Windows uses an exact HTTP(S) **origin**; Apple and Linux list
engine-defined **domain** records; Android's newer WebStorage API clears a whole
registrable **site** group. A request for one origin is never widened to a domain
or site. Use the targets returned by native records, and inspect
`scopedClearingGroups` before selecting categories. Apple/Linux record names need
not be registrable domains. Windows requires a target and reports native quota
estimates, which are not a complete inventory of every storage category.
Android cannot selectively clear one category within its site group; request the
whole supported group. OHOS and Web lack a suitable modern scoped store API.
Default managers address ordinary data; session/profile managers address their
selected stores. Clearing a store affects all pages sharing it.

## Native menus and media

`setContextMenuEnabled` controls the native menu on Windows, Linux and macOS.
Android/iOS do not suppress every long press because that would also alter text
selection. `setAudioMuted` is available on Windows, Linux and OHOS;
`pauseMedia` on Apple and OHOS; Apple also offers
`setMediaPlaybackSuspended`. These operations use native engine APIs and do not
pretend main-frame JavaScript can control every cross-origin frame. Inspect the
individual flags in `getBrowserCapabilities()`; unsupported operations log and
return `false`.

## Browser routes and authentication

Build an in-app browser route with `WebViewWidget`, navigation/title callbacks and
an owned session. The app chooses its toolbar, tabs, address field and routes.
For a system browser or Custom Tabs/Safari view, use a dedicated URL-launching
integration. Those windows do not expose this controller's scripts, profiles or
resource delegates.

OAuth system authentication is a separate session: use an authentication library
that handles OS callbacks, cancellation and PKCE. Apple provides
[ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession);
Android uses a browser-based flow such as Custom Tabs. Embedded WebView private
mode does not provide the system browser's SSO or authentication-session guarantees.

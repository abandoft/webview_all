---
title: Downloads
description: Handle WebView downloads with application-owned save UI.
---

From 1.4.8, `WebViewController.setDownloadDelegate` lets your app handle downloads
separately from navigation. It does not create a download window or a background
download manager. Your app decides whether to ask the user and where to save.

```dart
await controller.setDownloadDelegate(
  WebViewDownloadDelegate(
    onDownloadRequest: (request) async {
      if (!request.supportedActions.contains(WebViewDownloadAction.saveToFile)) {
        return const WebViewDownloadDecision.cancel();
      }
      // Application code: use your own UI or file selection component.
      final path = await chooseDownloadPath(request.suggestedFilename);
      return path == null
          ? const WebViewDownloadDecision.cancel()
          : WebViewDownloadDecision.saveToFile(path);
    },
    onDownloadProgress: (progress) {
      debugPrint('${progress.id}: ${progress.bytesReceived} bytes');
    },
    onDownloadResult: (result) {
      debugPrint('${result.id}: ${result.status}, ${result.path}');
    },
  ),
);
```

`chooseDownloadPath` above is supplied by your application. A file target must
be an absolute path in an existing directory the app can write. Suggested names
are untrusted metadata; validate them in application UI. Existing files are not
overwritten. Download files are separate from `userDataPath`, cache directories,
and website-data cleanup.

On Linux, native WebViews render above ordinary Flutter overlays. Present save
confirmation on an opaque route without a WebView, or use a native file picker
provided by the application.

| Decision | Meaning |
| --- | --- |
| `cancel()` | Decline this download. |
| `platformDefault()` | Use the supported platform default. |
| `saveToFile(path)` | Save the original engine download to a file, when advertised. |
| `handledExternally()` | The application has taken responsibility; do not also run the old download/navigation handler. |

Check `request.supportedActions`: unsupported decisions fail instead of being
silently replaced. Unknown metadata is `null`. Decisions have a 30-second timeout;
an exception, timeout, or invalid decision does not cause an automatic retry of
the URL. Progress is independent of page `onProgress`. `handedOff` means that
processing was handed over; it does **not** mean that a file was saved.

## Platform behavior

| Platform | Behavior |
| --- | --- |
| Windows | Keeps the original WebView2 task. Supports file targets, progress, and results. No delegate preserves automatic saving to the default download directory. Its offscreen WebView does not provide a usable default download panel; choose UI in the app. |
| Linux | Keeps WebKit downloads or the fetched response for custom requests, and saves through private temporary files before publishing without replacing an existing target. Supports file targets, progress, and results; the default download directory remains available without a delegate. |
| Android | Reports the native download notification and metadata. Supports cancellation or application handoff, not continuing a native task or selecting a native file target. Without a delegate, the existing `onNavigationRequest` behavior remains. |
| iOS/macOS | Supports explicit file targets, progress, and results on iOS 14.5+/macOS 11.3+; `platformDefault()` is not offered. Older systems report the new delegate as unsupported; minimum OS support and existing navigation behavior are unchanged. |
| OHOS | Uses ArkWeb native download tasks when a delegate is installed. `platformDefault()` saves to the app's `filesDir/Downloads`; file targets must be app-writable paths, not document-provider URIs. Without a delegate, the existing navigation fallback remains. |
| Web | The delegate covers attachment responses fetched by the plugin, including custom-header and POST requests. Ordinary iframe downloads are browser-managed and cannot all be observed. Browser handoff has no reliable final file path or completion notification. |

On Windows, `controller.loadRequest` preserves the supplied method, headers,
and body. With `onNavigationRequest`, page-initiated form submissions can be
replayed as GET requests before they reach download handling. A download delegate
cannot recover a POST body lost at that earlier navigation step. See
[navigation behavior](/webview_all/guides/navigation/).

On Android, application handoff does not include the original POST body, custom
request headers, or automatic authentication transfer. The app must supply any
context needed by its own downloader; replaying the URL as a GET is not equivalent
to continuing the original request.

Web attachments preserve the original response rather than fetching the URL
again. They do not replace the current page or enter its history. Browser
permissions, iframe sandbox download restrictions, and CORS still apply;
cross-origin servers must expose `Content-Disposition` to make it readable by
the fetch path. Fetched browser downloads may need to retain the response while
it is handed to the browser; this is not a streaming large-file downloader.

Linux custom-header and POST requests retain the fetched response in memory;
progress for this path may arrive only after the response has been received.

Updating or removing a delegate cancels unanswered requests. Accepted
downloads continue reporting to the delegate that accepted them until they end.
Pass `null` to remove the delegate. On Windows/Linux, `downloadsEnabled: false`
takes precedence and blocks new downloads. Temporarily hiding or detaching a
widget is not permanent controller disposal. This API does not promise downloads
that survive a closed controller, app exit, or process restart.

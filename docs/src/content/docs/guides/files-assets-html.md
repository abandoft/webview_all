---
title: Files, Assets, HTML
description: Load local files, Flutter assets, inline HTML, and custom requests safely.
---

## Local Files

```dart
await controller.loadFile('/Users/me/Documents/page.html');
```

Platform behavior:

| Platform | Behavior |
| --- | --- |
| Android | Uses file URL loading. `AndroidLoadFileParams` can add headers. |
| iOS/macOS | Uses WebKit local file loading. `WebKitLoadFileParams` controls read access scope. |
| Windows | Maps the file's directory to a virtual HTTPS host. |
| Linux | Loads the absolute file through WebKitGTK. |
| OHOS | Enables file access and loads the file URL. |
| Web | Unsupported; browsers do not allow arbitrary file reads from a hosted app. |

## Android File Headers

```dart
await controller.platform.loadFileWithParams(
  AndroidLoadFileParams(
    absoluteFilePath: '/sdcard/Download/page.html',
    headers: const <String, String>{'X-Source': 'app'},
  ),
);
```

## WebKit Read Access

```dart
await controller.platform.loadFileWithParams(
  WebKitLoadFileParams(
    absoluteFilePath: '/Users/me/site/index.html',
    readAccessPath: '/Users/me/site',
  ),
);
```

`readAccessPath` must include any images, scripts, and styles referenced by the HTML file.

## Flutter Assets

Declare the asset:

```yaml
flutter:
  assets:
    - assets/help/index.html
```

Load it:

```dart
await controller.loadFlutterAsset('assets/help/index.html');
```

On Windows, each controller maps the canonical asset directory to a private randomized HTTPS host with cross-origin access denied. Mappings are replaced or cleared as navigation changes. Linux requires absolute file paths and canonicalizes them before loading. Both implementations reject traversal and symlink escapes outside the Flutter asset bundle. On web, assets resolve under the app's generated `assets/` path.

## Application Resource URLs

Use a resource delegate to let a page reference application-owned files without Base64:

```dart
await controller.setResourceDelegate(
  WebViewResourceDelegate(onRequest: (request) {
    if (request.path != '/video.mp4') return null;
    return WebViewResourceResponse.file(videoPath, mimeType: 'video/mp4');
  }),
);

final url = controller.getResourceUri('video.mp4');
if (url != null) {
  await controller.loadHtmlString(
    '<video controls src="$url"></video>',
    baseUrl: controller.getResourceUri('/')!.toString(),
  );
}
```

`videoPath` is an absolute file path the application has authorized. Pass resource paths as plain names without URL-encoding them first. Pages can reference resources using relative paths or complete URLs from `getResourceUri`. Handling is disabled by default and applies only to resource URLs issued by this controller. Returning `null` produces a 404 for that resource; ordinary network requests retain their existing behavior. Use the returned URL without hardcoding its scheme or host.

`WebViewResourceResponse.bytes` serves bytes and `.file` reads a file on demand. Both automatically support HEAD and single byte ranges, including partial responses used for media seeking. `.stream` delivers incremental data and cancels its subscription when the request is cancelled or the delegate changes. Seekable stream producers must inspect request headers and return the appropriate 206 response themselves.

Set `WebViewResourceDelegate.requestTimeout` to allow slower application callbacks or stream reads, for example `requestTimeout: const Duration(seconds: 60)`. The default remains 30 seconds. This deadline applies separately to `onRequest` and to each subsequent stream read; it does not limit the total duration of a progressing stream or change ordinary network timeouts. Use a whole number of milliseconds between 1 and 2,147,483,647. Invalid values are rejected without replacing the active delegate. Removing or replacing the delegate still cancels pending requests.

Android, iOS, macOS, Linux, and OHOS support files, bytes, and streams. Windows supports files and bytes; check `controller.resourceCapabilities.supportsStreaming` before returning an incremental stream. An unsupported stream logs a diagnostic and fails that resource without stopping the application. Web is unsupported: setting a delegate logs a diagnostic and `getResourceUri` returns `null`.

Call `setResourceDelegate(null)` to remove the delegate. Resource URLs are owned by their controller and expire when it is closed; normal CORS, CSP, and media format restrictions still apply. Validate requests and return only files the application permits the page to read.

Linux uses a loopback HTTP server with a random access path to support WebKitGTK media loading. It listens only on the local machine and closes with the controller. Share resource URLs only with pages authorized to read those resources.

With `loadHtmlString`, use the resource URL's root as `baseUrl` to keep the page and resources on the same origin.

Android WebView cannot reliably ignore Range after an If-Range mismatch, and known-length resources cannot exceed 2,147,483,647 bytes. These cases log a diagnostic and return 501. Retry the former without Range or If-Range; larger content can use a stream without a declared length for sequential reads.

## Inline HTML

```dart
await controller.loadHtmlString(
  '<html><body><a href="details.html">Details</a></body></html>',
  baseUrl: 'https://docs.example.com/help/',
);
```

Use `baseUrl` when the document contains relative URLs.

## Custom Requests

```dart
await controller.loadRequest(
  Uri.parse('https://api.example.com/form'),
  method: LoadRequestMethod.post,
  headers: const <String, String>{'Content-Type': 'application/json'},
  body: Uint8List.fromList(utf8.encode('{"ok":true}')),
);
```

Check platform support before relying on custom requests:

| Platform | Notes |
| --- | --- |
| Android | POST with custom headers is not supported by Android WebView `postUrl`. |
| OHOS | POST with custom headers is not supported by ArkWeb `postUrl`; `webview_all_ohos` throws `UnsupportedError`. |
| Web | Non-simple requests use `fetch`, require CORS approval, preserve binary response bytes, and use the final redirect URL as the logical URL. |
| Windows/Linux/iOS/macOS | Support method, headers, and body through native request APIs. |

## Recommended Fallback for Unsupported POST Headers

When a platform cannot submit a POST with custom headers directly, send the request with your app's HTTP client and load the resulting HTML:

```dart
final response = await http.post(
  Uri.parse('https://api.example.com/form'),
  headers: const <String, String>{'Authorization': 'Bearer token'},
  body: '{"ok":true}',
);

await controller.loadHtmlString(
  response.body,
  baseUrl: 'https://api.example.com/form',
);
```

This fallback is appropriate for HTML responses. It is not equivalent to browser navigation for cookies, redirects, service workers, or streaming responses.

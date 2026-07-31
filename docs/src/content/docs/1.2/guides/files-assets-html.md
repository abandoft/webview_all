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

On Windows, the implementation maps the asset directory to an internal HTTPS host. On web, it resolves the asset under the app's generated `assets/` path.

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
| Web | Non-simple requests use `fetch` and require CORS approval from the server. |
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

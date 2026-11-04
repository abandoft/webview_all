import 'dart:async';

import 'package:flutter/foundation.dart';

/// Resource response features available on the current platform.
@immutable
class WebViewResourceCapabilities {
  const WebViewResourceCapabilities({
    this.supportsResources = false,
    this.supportsStreaming = false,
  });

  /// Whether application resources can be loaded through controller-issued URLs.
  final bool supportsResources;

  /// Whether a response can be delivered before its stream has finished.
  ///
  /// Windows supports files and bytes, but not incremental stream responses.
  final bool supportsStreaming;
}

/// A request for an application resource URL issued by a WebView controller.
///
/// Ordinary network requests are handled by the WebView and do not reach this
/// callback. Header names are lowercase. Use [path] to route resources.
@immutable
class WebViewResourceRequest {
  WebViewResourceRequest({
    required this.uri,
    required this.method,
    required Map<String, String> headers,
    String? path,
  }) : headers = Map<String, String>.unmodifiable(headers),
       path = path ?? Uri.decodeComponent(uri.path);

  final Uri uri;

  /// Decoded resource path, including its leading slash.
  ///
  /// This is relative to the controller's resource URL base.
  final String path;

  final String method;
  final Map<String, String> headers;
}

/// An application-supplied resource. This does not modify HTTP error callbacks.
///
/// File and byte responses support HEAD and single byte-range requests
/// automatically. Stream producers that support seeking must inspect request
/// headers and return the requested portion with status 206 and Content-Range.
/// The caller is responsible for authorizing any file it returns.
///
/// Android limits known-length resources to 2,147,483,647 bytes and cannot
/// reliably serve the full response after an If-Range mismatch. Unsupported
/// requests log a diagnostic and return 501.
@immutable
class WebViewResourceResponse {
  WebViewResourceResponse.bytes(
    Uint8List data, {
    required this.mimeType,
    this.statusCode = 200,
    Map<String, String> headers = const <String, String>{},
  }) : bytes = data,
       filePath = null,
       stream = null,
       contentLength = data.length,
       headers = Map<String, String>.unmodifiable(headers);

  /// Reads an absolute file path without loading the entire file into memory.
  WebViewResourceResponse.file(
    String absoluteFilePath, {
    required this.mimeType,
    this.statusCode = 200,
    Map<String, String> headers = const <String, String>{},
  }) : bytes = null,
       filePath = absoluteFilePath,
       stream = null,
       contentLength = null,
       headers = Map<String, String>.unmodifiable(headers);

  /// Delivers data incrementally on supported platforms.
  ///
  /// The subscription is cancelled when no longer needed. Prefer file responses
  /// for media that must seek. Windows logs a diagnostic and fails this resource;
  /// use [WebViewResourceResponse.file] or [WebViewResourceResponse.bytes] there.
  WebViewResourceResponse.stream(
    Stream<List<int>> data, {
    required this.mimeType,
    this.contentLength,
    this.statusCode = 200,
    Map<String, String> headers = const <String, String>{},
  }) : bytes = null,
       filePath = null,
       stream = data,
       headers = Map<String, String>.unmodifiable(headers);

  final String mimeType;

  /// Final response status. Supported ranges are 200–299 and 400–599.
  /// Redirect responses are not supported.
  final int statusCode;
  final Map<String, String> headers;
  final int? contentLength;
  final Uint8List? bytes;
  final String? filePath;
  final Stream<List<int>>? stream;
}

/// Supplies resources for URLs returned by a controller's getResourceUri.
///
/// Returning null produces a 404 for that resource. Other URLs retain normal
/// WebView behavior. Replacing or removing the delegate cancels pending work.
@immutable
class WebViewResourceDelegate {
  const WebViewResourceDelegate({required this.onRequest, this.requestTimeout});

  /// Time allowed for [onRequest] and for each subsequent stream read.
  ///
  /// Null uses the platform default of 30 seconds. This is a per-operation
  /// timeout, not a limit on the total duration of a progressing stream.
  /// Must be a whole number of milliseconds between 1 and 2147483647.
  final Duration? requestTimeout;

  final FutureOr<WebViewResourceResponse?> Function(
    WebViewResourceRequest request,
  )
  onRequest;
}

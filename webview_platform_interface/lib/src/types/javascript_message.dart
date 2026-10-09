// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// A message that was sent by JavaScript code running in a [WebView].
///
/// Platform specific implementations can add additional fields by extending
/// this class and providing a factory method that takes the
/// [JavaScriptMessage] as a parameter.
///
/// This example demonstrates how to extend the [JavaScriptMessage] to
/// provide additional platform specific parameters.
///
/// When extending [JavaScriptMessage] additional parameters should always
/// accept `null` or have a default value to prevent breaking changes.
///
/// ```dart
/// @immutable
/// class WKWebViewScriptMessage extends JavaScriptMessage {
///   WKWebViewScriptMessage._(
///     JavaScriptMessage javaScriptMessage,
///     this.extraData,
///   ) : super(javaScriptMessage.message);
///
///   factory WKWebViewScriptMessage.fromJavaScripMessage(
///     JavaScriptMessage javaScripMessage, {
///     String? extraData,
///   }) {
///     return WKWebViewScriptMessage._(
///       javaScriptMessage,
///       extraData: extraData,
///     );
///   }
///
///   final String? extraData;
/// }
/// ```
@immutable
class JavaScriptMessage {
  /// Creates a new JavaScript message object.
  const JavaScriptMessage({
    required this.message,
    this.sourceUrl,
    this.isMainFrame,
  });

  /// The contents of the message that was sent by the JavaScript code.
  final String message;

  /// The URL of the document that sent the message, or `null` when the
  /// platform names none.
  ///
  /// - On Windows this is the URL WebView2 names for the sending document, a
  ///   sandboxed document's included: a sandboxed document reports the URL it
  ///   was served from, not an opaque origin.
  /// - On Linux this is the URL of the document whose window holds the
  ///   channel object, captured when that document started; it is `null` for
  ///   an opaque origin (a sandboxed document, HTML loaded with no base URL),
  ///   while [isMainFrame] is still reported.
  /// - `null` means the sender is unknown: never substitute the web view's
  ///   current URL. A URL with no http(s) origin, such as `about:srcdoc` or
  ///   `blob:`, names no origin either, and [Uri.origin] throws for it.
  final String? sourceUrl;

  /// Whether the main frame's document sent the message, when the platform
  /// reports it; `null` otherwise.
  final bool? isMainFrame;
}

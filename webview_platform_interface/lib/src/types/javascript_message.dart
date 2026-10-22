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
///   ) : super(
///         message: javaScriptMessage.message,
///         sourceUrl: javaScriptMessage.sourceUrl,
///         sourceOrigin: javaScriptMessage.sourceOrigin,
///         isMainFrame: javaScriptMessage.isMainFrame,
///       );
///
///   factory WKWebViewScriptMessage.fromJavaScriptMessage(
///     JavaScriptMessage javaScriptMessage, {
///     String? extraData,
///   }) {
///     return WKWebViewScriptMessage._(
///       javaScriptMessage,
///       extraData,
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
    this.sourceOrigin,
    this.isMainFrame,
  });

  /// The contents of the message that was sent by the JavaScript code.
  final String message;

  /// The URL of the document that sent the message, or `null` when unavailable.
  ///
  /// This can differ from the web view's current URL
  /// if navigation has started since the message was sent. Never substitute
  /// the current URL when this field is null.
  ///
  /// This is a document URL, not its security origin. In particular, a sandboxed
  /// document can report its served URL despite having an opaque origin. URLs
  /// such as `about:blank` also cannot be treated as HTTP(S) origins.
  final String? sourceUrl;

  /// The browser security origin of the sending document, when available.
  ///
  /// A serialized origin includes the scheme, host, and non-default port.
  /// The string `"null"` represents an opaque origin; Dart `null` means the
  /// platform could not determine the origin. Neither grants a trusted origin.
  /// This field is never derived solely from [sourceUrl], since a document's
  /// URL does not establish its security origin.
  final String? sourceOrigin;

  /// Whether the main frame's document sent the message, when the platform
  /// reports it; `null` otherwise.
  ///
  /// Windows and Web receive main-document messages only. Android, iOS, macOS,
  /// and Linux can distinguish messages sent by child frames. A document's URL
  /// alone cannot establish whether it belongs to the main frame.
  final bool? isMainFrame;
}

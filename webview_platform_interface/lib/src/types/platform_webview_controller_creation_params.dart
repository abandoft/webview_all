// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'webview_session.dart';

/// Object specifying creation parameters for creating a [PlatformWebViewController].
///
/// Platform specific implementations can add additional fields by extending
/// this class.
///
/// This example demonstrates how to extend the [PlatformWebViewControllerCreationParams] to
/// provide additional platform specific parameters.
///
/// When extending [PlatformWebViewControllerCreationParams] additional parameters
/// should always accept `null` or have a default value to prevent breaking
/// changes.
///
/// ```dart
/// class WKWebViewControllerCreationParams
///     extends PlatformWebViewControllerCreationParams {
///   WKWebViewControllerCreationParams._(
///     PlatformWebViewControllerCreationParams params, {
///     this.domain,
///   }) : super.fromPlatformWebViewControllerCreationParams(params);
///
///   factory WKWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
///     PlatformWebViewControllerCreationParams params, {
///     String? domain,
///   }) {
///     return WKWebViewControllerCreationParams._(params, domain: domain);
///   }
///
///   final String? domain;
/// }
/// ```
@immutable
class PlatformWebViewControllerCreationParams {
  /// Used by the platform implementation to create a new [PlatformWebViewController].
  const PlatformWebViewControllerCreationParams({
    WebViewSessionMode sessionMode = WebViewSessionMode.shared,
  }) : _sessionMode = sessionMode,
       _sourceParams = null;

  /// Preserves generic policies in const platform-specific converters.
  const PlatformWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params, {
    WebViewSessionMode? sessionMode,
  }) : _sessionMode = sessionMode,
       _sourceParams = params;

  final WebViewSessionMode? _sessionMode;
  final PlatformWebViewControllerCreationParams? _sourceParams;

  /// Immutable website-data policy. Unsupported modes must never fall back to
  /// an ordinary profile, because that could expose existing login state.
  WebViewSessionMode get sessionMode =>
      _sessionMode ?? _sourceParams!.sessionMode;
}

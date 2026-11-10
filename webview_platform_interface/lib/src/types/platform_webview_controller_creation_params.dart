// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'webview_session.dart';
import 'webview_browser.dart';

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
    WebViewMediaPlaybackPolicy? mediaPlaybackPolicy,
    String? profileName,
    List<String> customSchemes = const [],
  }) : _sessionMode = sessionMode,
       _mediaPlaybackPolicy = mediaPlaybackPolicy,
       _profileName = profileName,
       _customSchemes = customSchemes,
       _sourceParams = null;

  /// Preserves generic policies in const platform-specific converters.
  const PlatformWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params, {
    WebViewSessionMode? sessionMode,
    WebViewMediaPlaybackPolicy? mediaPlaybackPolicy,
    String? profileName,
    List<String>? customSchemes,
  }) : _sessionMode = sessionMode,
       _mediaPlaybackPolicy = mediaPlaybackPolicy,
       _profileName = profileName,
       _customSchemes = customSchemes,
       _sourceParams = params;

  final WebViewSessionMode? _sessionMode;
  final WebViewMediaPlaybackPolicy? _mediaPlaybackPolicy;
  final String? _profileName;
  final List<String>? _customSchemes;

  /// Non-engine URL schemes declared before native view/environment creation.
  /// Names must be lowercase and must not name engine-owned protocols.
  List<String> get customSchemes => List.unmodifiable(
    _customSchemes ?? _sourceParams?.customSchemes ?? const [],
  );

  /// A persistent named store. Query namedProfiles support before requesting it;
  /// private modes never silently become persistent named profiles.
  String? get profileName => _profileName ?? _sourceParams?.profileName;
  final PlatformWebViewControllerCreationParams? _sourceParams;

  /// Immutable website-data policy. Unsupported modes must never fall back to
  /// an ordinary profile, because that could expose existing login state.
  WebViewSessionMode get sessionMode =>
      _sessionMode ?? _sourceParams!.sessionMode;

  /// Applied before view creation where supported. Null retains engine defaults.
  WebViewMediaPlaybackPolicy? get mediaPlaybackPolicy =>
      _mediaPlaybackPolicy ?? _sourceParams?.mediaPlaybackPolicy;
}

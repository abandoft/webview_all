// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'web_webview_platform.dart';

/// Internal Flutter entry point for registering the web implementation.
///
/// This class intentionally has a package-specific name so that Flutter's
/// generated web registrant can import this plugin alongside other WebView
/// implementations without creating an ambiguous top-level symbol.
final class WebviewAllWebPlugin {
  WebviewAllWebPlugin._();

  /// Registers the web implementation with Flutter.
  static void registerWith(Registrar registrar) {
    WebWebViewPlatform.registerWith(registrar);
  }
}

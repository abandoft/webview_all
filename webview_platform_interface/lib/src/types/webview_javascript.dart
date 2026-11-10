import 'dart:async';

import 'package:flutter/foundation.dart';

import 'webview_user_script.dart';

/// The JavaScript globals shared by scripts in one WebView document.
///
/// Isolated worlds have separate JavaScript globals, but share the page DOM.
@immutable
class WebViewJavaScriptWorld {
  const WebViewJavaScriptWorld._(this.name);

  /// The execution environment used by the website itself.
  static const page = WebViewJavaScriptWorld._(null);

  /// A named environment separate from the website's JavaScript globals.
  const WebViewJavaScriptWorld.isolated(String name)
    : assert(name != ''),
      name = name;

  /// Null identifies the page world.
  final String? name;

  bool get isPage => name == null;

  @override
  bool operator ==(Object other) =>
      other is WebViewJavaScriptWorld && other.name == name;

  @override
  int get hashCode => name.hashCode;
}

/// JavaScript features offered by the current engine and content mode.
@immutable
class WebViewJavaScriptCapabilities {
  const WebViewJavaScriptCapabilities({
    this.userScriptInjectionTimes = const {},
    this.supportsPromiseHandlers = false,
    this.supportsIsolatedWorlds = false,
    this.supportsTrustedOrigins = false,
    this.supportsTrustedFrameInformation = false,
    this.supportsSubframeHandlers = false,
    this.documentEndIsEmulated = false,
    this.requiresControlledContent = false,
    this.limitation,
  });

  final Set<WebViewUserScriptInjectionTime> userScriptInjectionTimes;
  final bool supportsPromiseHandlers;
  final bool supportsIsolatedWorlds;
  final bool supportsTrustedOrigins;
  final bool supportsTrustedFrameInformation;
  final bool supportsSubframeHandlers;
  final bool documentEndIsEmulated;
  final bool requiresControlledContent;
  final String? limitation;

  bool supportsWorld(WebViewJavaScriptWorld world) =>
      world.isPage || supportsIsolatedWorlds;
}

/// Native-verified restrictions on callers of a Dart handler.
@immutable
class WebViewJavaScriptAccessPolicy {
  /// Explicitly permits callers without origin or frame restrictions.
  const WebViewJavaScriptAccessPolicy.unrestricted()
    : allowedOrigins = null,
      mainFrameOnly = false;

  /// Allows only exact HTTP(S) security origins (scheme, host and port).
  ///
  /// Unknown and opaque origins never match. URL paths and wildcard patterns
  /// are not accepted. A platform unable to enforce this policy skips handler
  /// registration with a warning.
  WebViewJavaScriptAccessPolicy.origins(
    Set<String> origins, {
    this.mainFrameOnly = true,
  }) : allowedOrigins = Set<String>.unmodifiable(
         origins.map(_normalizeOrigin),
       ) {
    if (origins.isEmpty) {
      throw ArgumentError.value(
        origins,
        'origins',
        'Provide an allowed origin.',
      );
    }
  }

  final Set<String>? allowedOrigins;
  final bool mainFrameOnly;

  bool allows({required String? origin, required bool? isMainFrame}) {
    if (mainFrameOnly && isMainFrame != true) return false;
    final allowed = allowedOrigins;
    if (allowed == null) return true;
    if (origin == null || origin == 'null') return false;
    try {
      return allowed.contains(_normalizeOrigin(origin));
    } on ArgumentError {
      return false;
    }
  }

  static String _normalizeOrigin(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.host.contains('*') ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError.value(
        value,
        'origin',
        'Use an exact HTTP(S) origin.',
      );
    }
    return uri.origin;
  }
}

/// A call originating in a JavaScript document.
class WebViewJavaScriptCall {
  WebViewJavaScriptCall({
    required this.arguments,
    required this.world,
    required this.cancelled,
    this.sourceUrl,
    this.sourceOrigin,
    this.isMainFrame,
  });

  final List<Object?> arguments;
  final WebViewJavaScriptWorld world;
  final String? sourceUrl;
  final String? sourceOrigin;
  final bool? isMainFrame;

  /// Completes when navigation, timeout, removal or disposal invalidates a call.
  /// Dart callback side effects cannot be cancelled automatically.
  final Future<void> cancelled;
}

typedef WebViewJavaScriptHandler =
    FutureOr<Object?> Function(WebViewJavaScriptCall call);

/// Registration data passed to platform controllers.
@immutable
class WebViewJavaScriptHandlerParams {
  const WebViewJavaScriptHandlerParams({
    required this.name,
    required this.onCall,
    required this.accessPolicy,
    this.world = WebViewJavaScriptWorld.page,
    this.timeout = const Duration(seconds: 30),
  });

  final String name;
  final WebViewJavaScriptHandler onCall;
  final WebViewJavaScriptAccessPolicy accessPolicy;
  final WebViewJavaScriptWorld world;
  final Duration timeout;
}

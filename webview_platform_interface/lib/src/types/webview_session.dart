import 'package:flutter/foundation.dart';

/// Website-data policy selected before a native WebView is created.
enum WebViewSessionMode {
  /// Uses the platform's ordinary shared, persistent website-data store.
  shared,

  /// Uses platform private browsing, which may be limited as reported by capabilities.
  /// Stores may be shared; Android limited mode shares ordinary website data.
  incognito,

  /// Uses private browsing with a store isolated from every other session.
  isolatedIncognito,
}

/// How an engine implements [WebViewSessionMode.incognito].
enum WebViewIncognitoSupport {
  /// No private browsing handling is available.
  none,

  /// Applies per-view privacy settings but may still share persistent data.
  limited,

  /// Uses a native nonpersistent store. Private stores may still be shared.
  nativeStore,
}

/// Runtime capabilities for owned WebView sessions.
@immutable
class WebViewSessionCapabilities {
  WebViewSessionCapabilities({
    Set<WebViewSessionMode> supportedModes = const {WebViewSessionMode.shared},
    this.canClose = false,
    this.privateSessionRestriction,
    this.incognitoSupport = WebViewIncognitoSupport.none,
    this.scopedCookies = false,
    this.scopedWebsiteData = false,
  }) : supportedModes = Set.unmodifiable(supportedModes);

  final Set<WebViewSessionMode> supportedModes;
  final bool canClose;

  /// Explains any native private-session limitation for diagnostic messages.
  final String? privateSessionRestriction;

  final WebViewIncognitoSupport incognitoSupport;

  /// Cookie operations address the selected data store, not a default manager.
  /// In shared/incognito modes, other views may intentionally share that store.
  final bool scopedCookies;

  /// Website-data operations address the selected store. Individual categories
  /// can still be unsupported, as reported by the clearing result.
  final bool scopedWebsiteData;

  bool supports(WebViewSessionMode mode) => supportedModes.contains(mode);
}

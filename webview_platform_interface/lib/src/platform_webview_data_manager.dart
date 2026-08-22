import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types/types.dart';
import 'webview_platform.dart' show WebViewPlatform;

/// Interface for managing a platform WebView website data store.
///
/// Platform implementations should extend this class so newly added methods
/// can retain backward-compatible default behavior.
abstract class PlatformWebViewDataManager extends PlatformInterface {
  /// Creates the platform data manager registered for the current platform.
  factory PlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    assert(
      WebViewPlatform.instance != null,
      'A platform implementation for `webview_all` has not been set. Please '
      'ensure that an implementation of `WebViewPlatform` has been set to '
      '`WebViewPlatform.instance` before use.',
    );
    final PlatformWebViewDataManager manager = WebViewPlatform.instance!
        .createPlatformWebViewDataManager(params);
    PlatformInterface.verify(manager, _token);
    return manager;
  }

  /// Constructor for platform implementations.
  @protected
  PlatformWebViewDataManager.implementation(this.params) : super(token: _token);

  static final Object _token = Object();

  /// The parameters used to create this manager.
  final PlatformWebViewDataManagerCreationParams params;

  /// Clears website data from the data store used by normal WebViews.
  ///
  /// The default implementation reports every category as unsupported so that
  /// older platform implementations fail safely without deleting a broader
  /// data scope than requested.
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    return WebViewDataClearingResult(
      unsupportedDataTypes: WebViewDataType.values.toSet(),
    );
  }
}

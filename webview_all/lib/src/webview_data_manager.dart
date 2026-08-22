import 'package:webview_platform_interface/webview_platform_interface.dart';

/// Manages website data shared by WebViews in the current platform data store.
class WebViewDataManager {
  /// Creates a manager for the default persistent WebView data store.
  WebViewDataManager()
    : this.fromPlatformCreationParams(
        const PlatformWebViewDataManagerCreationParams(),
      );

  /// Creates a manager from platform-specific creation parameters.
  WebViewDataManager.fromPlatformCreationParams(
    PlatformWebViewDataManagerCreationParams params,
  ) : this.fromPlatform(PlatformWebViewDataManager(params));

  /// Creates a manager backed by [platform].
  WebViewDataManager.fromPlatform(this.platform);

  /// The platform implementation used by this manager.
  final PlatformWebViewDataManager platform;

  /// Clears website data from the store used by normal WebViews.
  ///
  /// The result identifies categories that were cleared, unsupported, or
  /// failed. The operation never broadens its scope to passwords, autofill, or
  /// browsing history.
  Future<WebViewDataClearingResult> clearAllWebsiteData() {
    return platform.clearAllWebsiteData();
  }
}

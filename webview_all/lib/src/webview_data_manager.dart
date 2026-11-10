import 'package:webview_platform_interface/webview_platform_interface.dart';

/// Manages website data in the selected platform data store.
class WebViewDataManager {
  Future<List<WebViewDataRecord>?> getWebsiteDataRecords({
    WebViewDataTarget? target,
    Set<WebViewDataType> dataTypes = const {...WebViewDataType.values},
  }) => platform.getWebsiteDataRecords(
    target: target,
    dataTypes: Set.unmodifiable(dataTypes),
  );
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) => platform.clearWebsiteDataFor(
    target,
    dataTypes: Set.unmodifiable(dataTypes),
  );

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

  /// Queries categories that can be cleared independently or as a native group.
  Future<WebViewDataCapabilities> getCapabilities() =>
      platform.getCapabilities();

  /// Clears the requested categories without deleting additional website data.
  /// Session managers address their selected store, including private stores.
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) => platform.clearWebsiteData(dataTypes: Set.unmodifiable(dataTypes));

  /// Clears website data in this manager's store.
  /// Default managers use ordinary shared storage; session managers use the selected store.
  ///
  /// The result identifies categories that were cleared, unsupported, or
  /// failed. The operation never broadens its scope to passwords, autofill, or
  /// browsing history.
  Future<WebViewDataClearingResult> clearAllWebsiteData() {
    return platform.clearAllWebsiteData();
  }
}

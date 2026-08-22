import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'common/web_kit.g.dart';

/// WebKit creation parameters for [WebKitWebViewDataManager].
@immutable
class WebKitWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  /// Creates WebKit data manager parameters using the default data store.
  WebKitWebViewDataManagerCreationParams._(
    PlatformWebViewDataManagerCreationParams params, {
    WKWebsiteDataStore? websiteDataStore,
  }) : websiteDataStore =
           websiteDataStore ?? WKWebsiteDataStore.defaultDataStore,
       super();

  /// Converts generic parameters to WebKit parameters.
  factory WebKitWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params, {
    WKWebsiteDataStore? websiteDataStore,
  }) {
    return WebKitWebViewDataManagerCreationParams._(
      params,
      websiteDataStore: websiteDataStore,
    );
  }

  /// The data store whose website data will be cleared.
  @visibleForTesting
  final WKWebsiteDataStore websiteDataStore;
}

/// Clears website data stored by WKWebView.
class WebKitWebViewDataManager extends PlatformWebViewDataManager {
  /// Creates a WebKit website data manager.
  WebKitWebViewDataManager(PlatformWebViewDataManagerCreationParams params)
    : super.implementation(
        params is WebKitWebViewDataManagerCreationParams
            ? params
            : WebKitWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                params,
              ),
      );

  WebKitWebViewDataManagerCreationParams get _webkitParams =>
      params as WebKitWebViewDataManagerCreationParams;

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    try {
      await _webkitParams.websiteDataStore.removeDataOfTypes(<WebsiteDataType>[
        WebsiteDataType.cookies,
        WebsiteDataType.memoryCache,
        WebsiteDataType.diskCache,
        WebsiteDataType.offlineWebApplicationCache,
        WebsiteDataType.localStorage,
        WebsiteDataType.sessionStorage,
        WebsiteDataType.webSQLDatabases,
        WebsiteDataType.indexedDBDatabases,
        WebsiteDataType.fetchCache,
        WebsiteDataType.serviceWorkerRegistrations,
      ], 0);
      return WebViewDataClearingResult(
        clearedDataTypes: WebViewDataType.values.toSet(),
      );
    } catch (error) {
      final String diagnostic = error.toString().replaceAll(
        RegExp(r'[\r\n]+'),
        ' ',
      );
      return WebViewDataClearingResult(
        failures: <WebViewDataType, String>{
          for (final WebViewDataType type in WebViewDataType.values)
            type: diagnostic,
        },
      );
    }
  }
}

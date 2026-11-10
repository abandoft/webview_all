import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'common/web_kit.g.dart';
import 'common/platform_webview.dart';

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

  /// Uses the actual store configured on this WebView, including private stores.
  WebKitWebViewDataManager.forController(PlatformWebView controller)
    : _sessionController = controller,
      super.implementation(
        WebKitWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
          const PlatformWebViewDataManagerCreationParams(),
        ),
      );

  PlatformWebView? _sessionController;

  Future<WKWebsiteDataStore> get _store async => _sessionController == null
      ? _webkitParams.websiteDataStore
      : await _sessionController!.configuration.getWebsiteDataStore();

  WebKitWebViewDataManagerCreationParams get _webkitParams =>
      params as WebKitWebViewDataManagerCreationParams;

  static const _nativeTypes = <WebViewDataType, List<WebsiteDataType>>{
    WebViewDataType.cookies: [WebsiteDataType.cookies],
    WebViewDataType.cache: [
      WebsiteDataType.memoryCache,
      WebsiteDataType.diskCache,
      WebsiteDataType.offlineWebApplicationCache,
    ],
    WebViewDataType.localStorage: [WebsiteDataType.localStorage],
    WebViewDataType.sessionStorage: [WebsiteDataType.sessionStorage],
    WebViewDataType.indexedDb: [WebsiteDataType.indexedDBDatabases],
    WebViewDataType.webSql: [WebsiteDataType.webSQLDatabases],
    WebViewDataType.cacheStorage: [WebsiteDataType.fetchCache],
    WebViewDataType.serviceWorkers: [
      WebsiteDataType.serviceWorkerRegistrations,
    ],
  };

  static const _channel = MethodChannel(
    'com.abandoft.webview_all_wkwebview/browser',
  );
  Future<T?> _scoped<T>(
    String method,
    WebViewDataTarget? target,
    Set<WebViewDataType> types,
  ) async {
    final store = await _store;
    return _channel.invokeMethod<T>(method, {
      'storeId': PigeonInstanceManager.instance.getIdentifier(store),
      'target': target?.toMap(),
      'dataTypes': types.map((v) => v.index).toList(),
    });
  }

  @override
  Future<List<WebViewDataRecord>?> getWebsiteDataRecords({
    WebViewDataTarget? target,
    Set<WebViewDataType> dataTypes = const {...WebViewDataType.values},
  }) => readNativeDataRecords(target, dataTypes, () async {
    if (target != null && target.scope != WebViewDataScope.domain) {
      debugPrint(
        'webview_all_wkwebview: records use domain scope; an exact origin cannot be listed.',
      );
      return null;
    }
    return _scoped<List<Object?>>('getWebsiteDataRecords', target, dataTypes);
  });
  @override
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) => clearScopedData(target, dataTypes, (types) async {
    await _scoped<void>('clearWebsiteDataFor', target, types);
  });

  @override
  Future<WebViewDataCapabilities> getCapabilities() async =>
      WebViewDataCapabilities(
        clearingGroups: WebViewDataType.values.map((type) => {type}),
        records: true,
        scopedClearingGroups: {
          WebViewDataScope.domain: WebViewDataType.values.map((v) => {v}),
        },
      );

  @override
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) => clearDataCategories(dataTypes, {
    for (final entry in _nativeTypes.entries)
      entry.key: () async => (await _store).removeDataOfTypes(entry.value, 0),
  });

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    try {
      await (await _store).removeDataOfTypes(<WebsiteDataType>[
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

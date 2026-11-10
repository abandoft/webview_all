import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'android_webkit.g.dart';

/// Android creation parameters for [AndroidWebViewDataManager].
@immutable
class AndroidWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  /// Creates Android WebView data manager parameters.
  const AndroidWebViewDataManagerCreationParams._(
    // Kept for forward-compatible conversion from the platform parameters.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewDataManagerCreationParams params,
  );

  /// Converts generic creation parameters to Android parameters.
  factory AndroidWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    return AndroidWebViewDataManagerCreationParams._(params);
  }
}

/// Clears website data stored by Android System WebView.
class AndroidWebViewDataManager extends PlatformWebViewDataManager {
  /// Creates an Android WebView data manager.
  AndroidWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params, {
    WebStorage? webStorage,
    CookieManager? cookieManager,
    WebView Function()? webViewFactory,
  }) : _webStorage = webStorage ?? WebStorage.instance,
       _cookieManager = cookieManager ?? CookieManager.instance,
       _webViewFactory = webViewFactory ?? WebView.new,
       super.implementation(
         params is AndroidWebViewDataManagerCreationParams
             ? params
             : AndroidWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                 params,
               ),
       );

  final WebStorage _webStorage;
  final CookieManager _cookieManager;
  final WebView Function() _webViewFactory;

  static const Set<WebViewDataType> _legacyStorageTypes = <WebViewDataType>{
    WebViewDataType.localStorage,
    WebViewDataType.webSql,
  };

  @override
  Future<WebViewDataCapabilities> getCapabilities() async {
    var complete = false;
    try {
      complete =
          await const MethodChannel(
            'com.abandoft.webview_all_android/browser',
          ).invokeMethod<bool>('supportsCompleteDataClearing') ??
          false;
    } catch (error) {
      debugPrint(
        'webview_all_android: full data-clearing capability could not be queried: $error',
      );
    }
    return WebViewDataCapabilities(
      scopedClearingGroups: {
        if (complete) WebViewDataScope.site: [WebViewDataType.values.toSet()],
      },
      clearingGroups: [
        {WebViewDataType.cookies},
        {WebViewDataType.cache},
        if (complete) WebViewDataType.values.toSet(),
      ],
      limitation:
          'Android supports independent cookie/cache clearing. Other categories require a full clear on WebViews with DELETE_BROWSING_DATA support.',
    );
  }

  @override
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) => clearScopedData(target, dataTypes, (types) async {
    final site = await _webStorage.deleteBrowsingDataForSite(target.value);
    if (site == null) {
      throw UnsupportedError(
        'The provider does not support site-wide data removal.',
      );
    }
    debugPrint(
      'webview_all_android: removed browsing data for site $site, including site-owned and embedded partitioned data.',
    );
  });

  @override
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) {
    if (dataTypes.containsAll(WebViewDataType.values)) {
      return clearAllWebsiteData();
    }
    return clearDataCategories(dataTypes, {
      WebViewDataType.cookies: () async {
        await _cookieManager.removeAllCookies();
      },
      WebViewDataType.cache: () async {
        final view = _webViewFactory();
        try {
          await view.clearCache(true);
        } finally {
          await view.destroy();
        }
      },
    });
  }

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    late final bool usedModernApi;
    try {
      usedModernApi = await _webStorage.deleteBrowsingData();
    } catch (error) {
      return _failedResult(WebViewDataType.values.toSet(), error);
    }
    if (usedModernApi) {
      return WebViewDataClearingResult(
        clearedDataTypes: WebViewDataType.values.toSet(),
      );
    }

    final Set<WebViewDataType> cleared = <WebViewDataType>{};
    final Map<WebViewDataType, String> failures = <WebViewDataType, String>{};

    try {
      await _cookieManager.removeAllCookies();
      cleared.add(WebViewDataType.cookies);
    } catch (error) {
      failures[WebViewDataType.cookies] = _diagnostic(error);
    }

    try {
      await _webStorage.deleteAllData();
      cleared.addAll(_legacyStorageTypes);
    } catch (error) {
      for (final WebViewDataType type in _legacyStorageTypes) {
        failures[type] = _diagnostic(error);
      }
    }

    WebView? temporaryWebView;
    Object? cacheFailure;
    try {
      temporaryWebView = _webViewFactory();
      await temporaryWebView.clearCache(true);
    } catch (error) {
      cacheFailure = error;
    } finally {
      if (temporaryWebView != null) {
        try {
          await temporaryWebView.destroy();
        } catch (error) {
          cacheFailure ??= error;
        }
      }
    }
    if (cacheFailure == null) {
      cleared.add(WebViewDataType.cache);
    } else {
      failures[WebViewDataType.cache] = _diagnostic(cacheFailure);
    }

    return WebViewDataClearingResult(
      clearedDataTypes: cleared,
      unsupportedDataTypes: WebViewDataType.values
          .where(
            (WebViewDataType type) =>
                !cleared.contains(type) && !failures.containsKey(type),
          )
          .toSet(),
      failures: failures,
    );
  }

  WebViewDataClearingResult _failedResult(
    Set<WebViewDataType> dataTypes,
    Object error,
  ) {
    return WebViewDataClearingResult(
      failures: <WebViewDataType, String>{
        for (final WebViewDataType type in dataTypes) type: _diagnostic(error),
      },
    );
  }

  String _diagnostic(Object error) =>
      error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
}

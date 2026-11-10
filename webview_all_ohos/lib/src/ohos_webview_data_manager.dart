import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'ohos_webview_native.dart';
import 'channels/host_api.dart';
import 'ohos_website_data_store.dart';

class OhosWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  const OhosWebViewDataManagerCreationParams();

  const OhosWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params,
  );
}

/// Clears website data exposed by the OpenHarmony ArkWeb global stores.
class OhosWebViewDataManager extends PlatformWebViewDataManager {
  OhosWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params, {
    CookieManager? cookieManager,
    bool incognito = false,
    bool sessionScoped = false,
    WebStorage? webStorage,
    OhosWebsiteDataStore? websiteDataStore,
  }) : _incognito = incognito,
       _sessionScoped = sessionScoped,
       _cookieManager = cookieManager ?? CookieManager.instance,
       _webStorage = webStorage ?? WebStorage.instance,
       _websiteDataStore = websiteDataStore ?? OhosWebsiteDataStore(),
       super.implementation(
         params is OhosWebViewDataManagerCreationParams
             ? params
             : OhosWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                 params,
               ),
       );

  final bool _incognito;
  final bool _sessionScoped;
  final CookieManager _cookieManager;
  final WebStorage _webStorage;
  final OhosWebsiteDataStore _websiteDataStore;

  @override
  Future<WebViewDataCapabilities>
  getCapabilities() async => WebViewDataCapabilities(
    clearingGroups: [
      {WebViewDataType.cookies},
      if (!_incognito && !_sessionScoped) {WebViewDataType.cache},
    ],
    limitation:
        'ArkWeb storage categories cannot be independently cleared by this API; shared cache clearing is unavailable for private/session-scoped managers.',
  );

  @override
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) {
    if (dataTypes.containsAll(WebViewDataType.values)) {
      return clearAllWebsiteData();
    }
    return clearDataCategories(dataTypes, {
      WebViewDataType.cookies: () async {
        if (_incognito) {
          await CookieManagerHostApi().removeAllCookies(0, incognito: true);
        } else {
          await _cookieManager.removeAllCookies();
        }
      },
      if (!_incognito && !_sessionScoped)
        WebViewDataType.cache: () =>
            _websiteDataStore.clearAllCache(includeDiskFiles: true),
    });
  }

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    final Set<WebViewDataType> cleared = <WebViewDataType>{};
    final Map<WebViewDataType, String> failures = <WebViewDataType, String>{};

    try {
      if (_incognito) {
        await CookieManagerHostApi().removeAllCookies(0, incognito: true);
      } else {
        await _cookieManager.removeAllCookies();
      }
      cleared.add(WebViewDataType.cookies);
    } catch (error) {
      failures[WebViewDataType.cookies] = _diagnostic(error);
    }

    if (!_incognito && !_sessionScoped) {
      try {
        await _websiteDataStore.clearAllCache(includeDiskFiles: true);
        cleared.add(WebViewDataType.cache);
      } catch (error) {
        failures[WebViewDataType.cache] = _diagnostic(error);
      }
    }

    const Set<WebViewDataType> storageTypes = <WebViewDataType>{
      WebViewDataType.localStorage,
      WebViewDataType.webSql,
    };
    try {
      if (_incognito) {
        await _websiteDataStore.clearPrivateStorage();
      } else {
        await _webStorage.deleteAllData();
      }
      cleared.addAll(storageTypes);
    } catch (error) {
      for (final WebViewDataType type in storageTypes) {
        failures[type] = _diagnostic(error);
      }
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

  String _diagnostic(Object error) =>
      error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
}

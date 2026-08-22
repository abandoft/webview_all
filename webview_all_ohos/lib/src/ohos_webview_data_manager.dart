import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'ohos_webview_native.dart';

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
    WebStorage? webStorage,
  }) : _cookieManager = cookieManager ?? CookieManager.instance,
       _webStorage = webStorage ?? WebStorage.instance,
       super.implementation(
         params is OhosWebViewDataManagerCreationParams
             ? params
             : OhosWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                 params,
               ),
       );

  final CookieManager _cookieManager;
  final WebStorage _webStorage;

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    final Set<WebViewDataType> cleared = <WebViewDataType>{};
    final Map<WebViewDataType, String> failures = <WebViewDataType, String>{};

    try {
      await _cookieManager.removeAllCookies();
      cleared.add(WebViewDataType.cookies);
    } catch (error) {
      failures[WebViewDataType.cookies] = _diagnostic(error);
    }

    const Set<WebViewDataType> storageTypes = <WebViewDataType>{
      WebViewDataType.localStorage,
      WebViewDataType.sessionStorage,
      WebViewDataType.webSql,
    };
    try {
      await _webStorage.deleteAllData();
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

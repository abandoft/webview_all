import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

class WebWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  const WebWebViewDataManagerCreationParams();

  const WebWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params,
  );
}

/// Reports browser-enforced limitations for global iframe website data.
class WebWebViewDataManager extends PlatformWebViewDataManager {
  WebWebViewDataManager(PlatformWebViewDataManagerCreationParams params)
    : super.implementation(
        params is WebWebViewDataManagerCreationParams
            ? params
            : WebWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                params,
              ),
      );

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    debugPrint(
      'webview_all_web: browser pages cannot clear arbitrary iframe origins or HttpOnly cookies. No website data was cleared.',
    );
    // A browser page cannot erase HttpOnly cookies or storage belonging to
    // arbitrary iframe origins. Reporting the limitation avoids claiming a
    // successful logout while cross-origin credentials remain.
    return WebViewDataClearingResult(
      unsupportedDataTypes: WebViewDataType.values.toSet(),
    );
  }
}

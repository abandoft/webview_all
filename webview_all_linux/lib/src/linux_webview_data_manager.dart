import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_controller.dart';

class LinuxWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  const LinuxWebViewDataManagerCreationParams();

  const LinuxWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params,
  );
}

/// Clears website data from the default WebKitGTK context.
class LinuxWebViewDataManager extends PlatformWebViewDataManager {
  LinuxWebViewDataManager(PlatformWebViewDataManagerCreationParams params)
    : super.implementation(
        params is LinuxWebViewDataManagerCreationParams
            ? params
            : LinuxWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                params,
              ),
      );

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    try {
      await LinuxWebViewController.rootChannel.invokeMethod<void>(
        'clearAllWebsiteData',
      );
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

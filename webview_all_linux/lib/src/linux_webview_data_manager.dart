import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_controller.dart';

class LinuxWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  const LinuxWebViewDataManagerCreationParams({
    this.webViewId,
    this.userDataPath,
    this.cachePath,
  });

  const LinuxWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params, {
    this.webViewId,
    this.userDataPath,
    this.cachePath,
  });

  final int? webViewId;

  /// The persistent website-data directory used by the shared environment.
  final String? userDataPath;

  /// The cache directory used by the shared environment.
  final String? cachePath;
}

/// Clears website data from the shared WebKitGTK environment.
///
/// With no options, this reuses the active environment or initializes defaults.
/// Explicit paths configure the environment before its first use, or must match
/// its active configuration. No WebView is created by this operation.
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
    final linuxParams = params as LinuxWebViewDataManagerCreationParams;
    try {
      if (linuxParams.webViewId == null) {
        await LinuxWebViewController.ensureEnvironment(
          userDataPath: linuxParams.userDataPath,
          cachePath: linuxParams.cachePath,
        );
      }
      await LinuxWebViewController.rootChannel.invokeMethod<void>(
        'clearAllWebsiteData',
        linuxParams.webViewId == null
            ? null
            : <String, Object?>{'webViewId': linuxParams.webViewId},
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

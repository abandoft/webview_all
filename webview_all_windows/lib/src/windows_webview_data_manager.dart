import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'windows_webview_native.dart' as native_webview;

class WindowsWebViewDataManagerCreationParams
    extends PlatformWebViewDataManagerCreationParams {
  const WindowsWebViewDataManagerCreationParams({
    this.userDataPath,
    this.browserExePath,
    this.additionalArguments,
  });

  const WindowsWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
    PlatformWebViewDataManagerCreationParams params, {
    this.userDataPath,
    this.browserExePath,
    this.additionalArguments,
  });

  /// The WebView2 user-data directory used by the shared environment.
  final String? userDataPath;

  /// The fixed WebView2 Runtime directory, when one is bundled by the app.
  final String? browserExePath;

  /// Additional Chromium command-line arguments for WebView2.
  final String? additionalArguments;
}

/// Clears website data in the shared WebView2 profile.
///
/// This operation does not initialize the Flutter texture renderer. Supply
/// [WindowsWebViewDataManagerCreationParams] when the application requires
/// custom environment options. Equivalent options reuse an existing shared
/// environment; conflicting options fail without replacing it.
class WindowsWebViewDataManager extends PlatformWebViewDataManager {
  WindowsWebViewDataManager(PlatformWebViewDataManagerCreationParams params)
    : super.implementation(
        params is WindowsWebViewDataManagerCreationParams
            ? params
            : WindowsWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                params,
              ),
      );

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    final WindowsWebViewDataManagerCreationParams windowsParams =
        params as WindowsWebViewDataManagerCreationParams;
    Object? failure;
    var supported = false;
    try {
      await native_webview.WebviewController.ensureEnvironment(
        userDataPath: windowsParams.userDataPath,
        browserExePath: windowsParams.browserExePath,
        additionalArguments: windowsParams.additionalArguments,
      );
      supported = await native_webview
          .WebviewController.clearAllWebsiteDataForEnvironment();
    } catch (error) {
      failure = error;
    }
    if (failure != null) {
      final String diagnostic = failure.toString().replaceAll(
        RegExp(r'[\r\n]+'),
        ' ',
      );
      return WebViewDataClearingResult(
        unsupportedDataTypes: _unsupportedWebsiteDataTypes,
        failures: <WebViewDataType, String>{
          for (final WebViewDataType type in _clearableWebsiteDataTypes)
            type: diagnostic,
        },
      );
    }
    if (!supported) {
      return WebViewDataClearingResult(
        unsupportedDataTypes: WebViewDataType.values.toSet(),
      );
    }
    return WebViewDataClearingResult(
      clearedDataTypes: _clearableWebsiteDataTypes,
      unsupportedDataTypes: _unsupportedWebsiteDataTypes,
    );
  }
}

const Set<WebViewDataType> _unsupportedWebsiteDataTypes = <WebViewDataType>{
  WebViewDataType.sessionStorage,
  WebViewDataType.serviceWorkers,
};

const Set<WebViewDataType> _clearableWebsiteDataTypes = <WebViewDataType>{
  WebViewDataType.cookies,
  WebViewDataType.cache,
  WebViewDataType.localStorage,
  WebViewDataType.indexedDb,
  WebViewDataType.webSql,
  WebViewDataType.cacheStorage,
};

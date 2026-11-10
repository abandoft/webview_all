import 'package:flutter/foundation.dart';
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

  Future<T?> _scoped<T>(
    String method,
    WebViewDataTarget? target,
    Set<WebViewDataType> types,
  ) async {
    final options = params as LinuxWebViewDataManagerCreationParams;
    if (options.webViewId == null) {
      await LinuxWebViewController.ensureEnvironment(
        userDataPath: options.userDataPath,
        cachePath: options.cachePath,
      );
    }
    return LinuxWebViewController.rootChannel.invokeMethod<T>(method, {
      if (options.webViewId != null) 'webViewId': options.webViewId,
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
        'webview_all_linux: website-data records use domain scope. An exact origin cannot be listed.',
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
  }) async {
    final requested = Set<WebViewDataType>.of(dataTypes);
    if (requested.isEmpty) {
      return WebViewDataClearingResult(requestedDataTypes: requested);
    }
    final options = params as LinuxWebViewDataManagerCreationParams;
    try {
      if (options.webViewId == null) {
        await LinuxWebViewController.ensureEnvironment(
          userDataPath: options.userDataPath,
          cachePath: options.cachePath,
        );
      }
      await LinuxWebViewController.rootChannel
          .invokeMethod<void>('clearWebsiteData', {
            if (options.webViewId != null) 'webViewId': options.webViewId,
            'dataTypes': requested.map((type) => type.index).toList(),
          });
      return WebViewDataClearingResult(
        requestedDataTypes: requested,
        clearedDataTypes: requested,
      );
    } catch (error) {
      return WebViewDataClearingResult(
        requestedDataTypes: requested,
        failures: {
          for (final type in requested)
            type: error.toString().replaceAll(RegExp(r'[\r\n]+'), ' '),
        },
      );
    }
  }

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

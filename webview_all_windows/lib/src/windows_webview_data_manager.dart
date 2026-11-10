import 'dart:convert';
import 'package:flutter/foundation.dart';
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
/// This operation does not initialize the Flutter texture renderer. With all
/// environment options null, it uses the active or initializing shared
/// environment, including its custom data directory. If none exists, it creates
/// an environment with platform defaults.
///
/// Supply [WindowsWebViewDataManagerCreationParams] to initialize custom options
/// or validate a specific configuration. Any non-null option, including an empty
/// string, requests a complete configuration with defaults for omitted values.
/// Conflicting configurations fail without clearing data or replacing the
/// environment.
class WindowsWebViewDataManager extends PlatformWebViewDataManager {
  WindowsWebViewDataManager(PlatformWebViewDataManagerCreationParams params)
    : super.implementation(
        params is WindowsWebViewDataManagerCreationParams
            ? params
            : WindowsWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
                params,
              ),
      );

  /// Uses the profile selected when this controller was created.
  WindowsWebViewDataManager.forController(
    native_webview.WebviewController controller,
  ) : _sessionController = controller,
      super.implementation(const WindowsWebViewDataManagerCreationParams());

  native_webview.WebviewController? _sessionController;

  static const _categoryFlags = <WebViewDataType, int>{
    WebViewDataType.cookies: 0x40,
    WebViewDataType.cache: 0x100,
    WebViewDataType.localStorage: 0x4,
    WebViewDataType.indexedDb: 0x2,
    WebViewDataType.webSql: 0x8,
    WebViewDataType.cacheStorage: 0x10,
  };

  Future<bool> _clearNative(int kinds) async {
    if (_sessionController != null) {
      return _sessionController!.clearWebsiteData(kinds);
    }
    await _ensureEnvironment();
    return native_webview.WebviewController.clearWebsiteDataForEnvironment(
      kinds,
    );
  }

  Future<void> _ensureEnvironment() async {
    final options = params as WindowsWebViewDataManagerCreationParams;
    await native_webview.WebviewController.ensureEnvironment(
      userDataPath: options.userDataPath,
      browserExePath: options.browserExePath,
      additionalArguments: options.additionalArguments,
    );
  }

  static const _originTypes = <WebViewDataType, String>{
    WebViewDataType.localStorage: 'local_storage',
    WebViewDataType.indexedDb: 'indexeddb',
    WebViewDataType.webSql: 'websql',
    WebViewDataType.cacheStorage: 'cache_storage',
    WebViewDataType.serviceWorkers: 'service_workers',
  };
  Future<String> _originOperation(
    String method,
    Map<String, Object?> values,
  ) async {
    if (_sessionController == null) await _ensureEnvironment();
    final view = _sessionController ?? native_webview.WebviewController();
    try {
      if (_sessionController == null) await view.initialize();
      final result = await view.originDataOperation(method, jsonEncode(values));
      if (result == null) throw StateError('The data store is closed.');
      final decoded = jsonDecode(result);
      if (decoded is Map && decoded['error'] != null) {
        throw StateError('The Runtime rejected the origin-data operation.');
      }
      return result;
    } finally {
      if (_sessionController == null) await view.dispose();
    }
  }

  @override
  Future<List<WebViewDataRecord>?> getWebsiteDataRecords({
    WebViewDataTarget? target,
    Set<WebViewDataType> dataTypes = const {...WebViewDataType.values},
  }) => readNativeDataRecords(target, dataTypes, () async {
    if (target == null || target.scope != WebViewDataScope.origin) {
      debugPrint(
        'webview_all_windows: specify an exact HTTP(S) origin to query storage; the Runtime cannot enumerate all stored origins.',
      );
      return null;
    }
    final raw =
        jsonDecode(
              await _originOperation('queryOriginData', {
                'origin': target.value,
              }),
            )
            as Map;
    final breakdown = raw['usageBreakdown'] as List? ?? [];
    final types = <int>{};
    int size = 0;
    for (final item in breakdown.whereType<Map>()) {
      for (final entry in _originTypes.entries) {
        if (dataTypes.contains(entry.key) &&
            item['storageType'] == entry.value &&
            (item['usage'] as num? ?? 0) > 0) {
          types.add(entry.key.index);
          size += (item['usage'] as num).toInt();
        }
      }
    }
    return [
      {
        'scope': 'origin',
        'value': target.value,
        'dataTypes': types.toList(),
        'sizeBytes': size,
      },
    ];
  });
  @override
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) => clearScopedData(target, dataTypes, (types) async {
    await _originOperation('clearOriginData', {
      'origin': target.value,
      'storageTypes': types.map((t) => _originTypes[t]!).join(','),
    });
  });

  @override
  Future<WebViewDataCapabilities> getCapabilities() async {
    var supported = false;
    try {
      supported = await _clearNative(0);
    } catch (error) {
      debugPrint(
        'webview_all_windows: data-clearing capabilities are unavailable: $error',
      );
    }
    return WebViewDataCapabilities(
      records: true,
      recordsRequireTarget: true,
      scopedClearingGroups: {
        WebViewDataScope.origin: _originTypes.keys.map((v) => {v}),
      },
      clearingGroups: [
        if (supported)
          for (final type in _categoryFlags.keys) {type},
      ],
      limitation:
          'Whole-store session storage and service worker clearing are unavailable. Origin-scoped service worker clearing is supported; origin records report native quota estimates and may omit unmetered storage.',
    );
  }

  @override
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) async {
    final requested = Set<WebViewDataType>.of(dataTypes);
    if (requested.containsAll(WebViewDataType.values)) {
      return clearAllWebsiteData();
    }
    final supportedTypes = requested.intersection(_categoryFlags.keys.toSet());
    final unsupported = requested.difference(supportedTypes);
    if (unsupported.isNotEmpty) {
      debugPrint(
        'webview_all: WebView2 cannot selectively clear: ${unsupported.map((type) => type.name).join(', ')}.',
      );
    }
    try {
      final supported =
          supportedTypes.isEmpty ||
          await _clearNative(
            supportedTypes.fold(
              0,
              (int mask, type) => mask | _categoryFlags[type]!,
            ),
          );
      return WebViewDataClearingResult(
        requestedDataTypes: requested,
        clearedDataTypes: supported ? supportedTypes : {},
        unsupportedDataTypes: supported ? unsupported : requested,
      );
    } catch (error) {
      return WebViewDataClearingResult(
        requestedDataTypes: requested,
        unsupportedDataTypes: unsupported,
        failures: {
          for (final type in supportedTypes)
            type: error.toString().replaceAll(RegExp(r'[\r\n]+'), ' '),
        },
      );
    }
  }

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    Object? failure;
    var supported = false;
    try {
      if (_sessionController != null) {
        supported = await _sessionController!.clearAllWebsiteData();
      } else {
        await _ensureEnvironment();
        supported = await native_webview
            .WebviewController.clearAllWebsiteDataForEnvironment();
      }
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

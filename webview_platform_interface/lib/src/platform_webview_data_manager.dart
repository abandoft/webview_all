import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types/types.dart';
import 'webview_platform.dart' show WebViewPlatform;

/// Interface for managing a platform WebView website data store.
///
/// Platform implementations should extend this class so newly added methods
/// can retain backward-compatible default behavior.
abstract class PlatformWebViewDataManager extends PlatformInterface {
  @protected
  Future<List<WebViewDataRecord>?> readNativeDataRecords(
    WebViewDataTarget? target,
    Set<WebViewDataType> types,
    Future<List<Object?>?> Function() read,
  ) async {
    if (target != null && !target.isValid) {
      debugPrint('webview_all: invalid website-data target; no data was read.');
      return null;
    }
    if (types.isEmpty) return [];
    try {
      final values = await read().timeout(const Duration(seconds: 30));
      return values
          ?.whereType<Map<Object?, Object?>>()
          .map(WebViewDataRecord.fromMap)
          .toList();
    } catch (error) {
      debugPrint('webview_all: querying website-data records failed: $error');
      return null;
    }
  }

  @protected
  Future<WebViewDataClearingResult> clearScopedData(
    WebViewDataTarget target,
    Set<WebViewDataType> requestedDataTypes,
    Future<void> Function(Set<WebViewDataType>) clear,
  ) async {
    final types = Set<WebViewDataType>.of(requestedDataTypes);
    List<Set<WebViewDataType>> groups;
    try {
      groups =
          (await getCapabilities()).scopedClearingGroups[target.scope] ??
          const [];
    } catch (error) {
      debugPrint(
        'webview_all: scoped data capabilities could not be queried: $error. No data was cleared.',
      );
      return WebViewDataClearingResult(
        requestedDataTypes: types,
        failures: {for (final type in types) type: '$error'},
      );
    }
    final supported = <WebViewDataType>{
      for (final group in groups)
        if (types.containsAll(group)) ...group,
    };
    final unsupported = types.difference(supported);
    if (!target.isValid) {
      debugPrint(
        'webview_all: invalid website-data target; no data was cleared.',
      );
      return WebViewDataClearingResult(
        requestedDataTypes: types,
        failures: {for (final t in types) t: 'Invalid website-data target.'},
      );
    }
    if (unsupported.isNotEmpty) {
      debugPrint(
        'webview_all: ${target.scope.name}-scoped clearing cannot remove ${unsupported.map((t) => t.name).join(", ")} independently. No broader scope or additional categories were cleared.',
      );
    }
    try {
      if (supported.isNotEmpty) {
        await clear(supported).timeout(const Duration(seconds: 30));
      }
      return WebViewDataClearingResult(
        requestedDataTypes: types,
        clearedDataTypes: supported,
        unsupportedDataTypes: unsupported,
      );
    } catch (error) {
      return WebViewDataClearingResult(
        requestedDataTypes: types,
        unsupportedDataTypes: unsupported,
        failures: {for (final t in supported) t: '$error'},
      );
    }
  }

  Future<List<WebViewDataRecord>?> getWebsiteDataRecords({
    WebViewDataTarget? target,
    Set<WebViewDataType> dataTypes = const {...WebViewDataType.values},
  }) async {
    debugPrint(
      'webview_all: enumerating website data at the requested scope is unavailable on this platform.',
    );
    return null;
  }

  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) async {
    debugPrint(
      'webview_all: clearing website data for ${target.scope.name} is unavailable. No broader store or domain was cleared.',
    );
    return WebViewDataClearingResult(
      requestedDataTypes: dataTypes,
      unsupportedDataTypes: dataTypes,
    );
  }

  /// Creates the platform data manager registered for the current platform.
  factory PlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    assert(
      WebViewPlatform.instance != null,
      'A platform implementation for `webview_all` has not been set. Please '
      'ensure that an implementation of `WebViewPlatform` has been set to '
      '`WebViewPlatform.instance` before use.',
    );
    final PlatformWebViewDataManager manager = WebViewPlatform.instance!
        .createPlatformWebViewDataManager(params);
    PlatformInterface.verify(manager, _token);
    return manager;
  }

  /// Constructor for platform implementations.
  @protected
  PlatformWebViewDataManager.implementation(this.params) : super(token: _token);

  static final Object _token = Object();

  /// The parameters used to create this manager.
  final PlatformWebViewDataManagerCreationParams params;

  /// Groups the engine can clear without affecting unrequested categories.
  Future<WebViewDataCapabilities> getCapabilities() async =>
      WebViewDataCapabilities();

  /// Clears exactly the requested categories in this manager's store.
  /// Unsupported combinations are reported without broadening the operation.
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) async {
    final requested = Set<WebViewDataType>.of(dataTypes);
    if (requested.containsAll(WebViewDataType.values)) {
      return clearAllWebsiteData();
    }
    if (requested.isNotEmpty) {
      debugPrint(
        'webview_all: selective website-data clearing is unavailable on this platform.',
      );
    }
    return WebViewDataClearingResult(
      requestedDataTypes: requested,
      unsupportedDataTypes: requested,
    );
  }

  /// Executes independent native category operations and records each outcome.
  @protected
  Future<WebViewDataClearingResult> clearDataCategories(
    Set<WebViewDataType> dataTypes,
    Map<WebViewDataType, Future<void> Function()> operations,
  ) async {
    final requested = Set<WebViewDataType>.of(dataTypes);
    final cleared = <WebViewDataType>{};
    final failures = <WebViewDataType, String>{};
    final unsupported = requested.difference(operations.keys.toSet());
    for (final type in requested) {
      final operation = operations[type];
      if (operation == null) continue;
      try {
        await operation();
        cleared.add(type);
      } catch (error) {
        failures[type] = error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
      }
    }
    if (unsupported.isNotEmpty) {
      debugPrint(
        'webview_all: selective clearing is unavailable for: ${unsupported.map((type) => type.name).join(', ')}. No broader data operation was used.',
      );
    }
    return WebViewDataClearingResult(
      requestedDataTypes: requested,
      clearedDataTypes: cleared,
      unsupportedDataTypes: unsupported,
      failures: failures,
    );
  }

  /// Clears website data from the store selected by this manager.
  ///
  /// The default implementation reports every category as unsupported so that
  /// older platform implementations fail safely without deleting a broader
  /// data scope than requested.
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    debugPrint(
      'webview_all: website-data clearing is unavailable on this platform. No data was cleared.',
    );
    return WebViewDataClearingResult(
      unsupportedDataTypes: WebViewDataType.values.toSet(),
    );
  }
}

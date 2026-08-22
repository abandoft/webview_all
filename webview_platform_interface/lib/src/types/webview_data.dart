import 'dart:collection';

import 'package:flutter/foundation.dart';

/// A category of persistent or session website data used by WebViews.
enum WebViewDataType {
  /// HTTP cookies.
  cookies,

  /// Network and offline caches exposed by the platform website-data API.
  cache,

  /// HTML local storage.
  localStorage,

  /// HTML session storage.
  sessionStorage,

  /// IndexedDB databases.
  indexedDb,

  /// WebSQL databases on engines that still support them.
  webSql,

  /// Cache Storage entries not already included by the native cache category.
  cacheStorage,

  /// Service worker registrations.
  serviceWorkers,
}

/// The result of clearing website data from a WebView data store.
@immutable
class WebViewDataClearingResult {
  /// Creates a website data clearing result.
  WebViewDataClearingResult({
    Set<WebViewDataType> clearedDataTypes = const <WebViewDataType>{},
    Set<WebViewDataType> unsupportedDataTypes = const <WebViewDataType>{},
    Map<WebViewDataType, String> failures = const <WebViewDataType, String>{},
  }) : clearedDataTypes = UnmodifiableSetView<WebViewDataType>(
         Set<WebViewDataType>.of(clearedDataTypes),
       ),
       unsupportedDataTypes = UnmodifiableSetView<WebViewDataType>(
         Set<WebViewDataType>.of(unsupportedDataTypes),
       ),
       failures = UnmodifiableMapView<WebViewDataType, String>(
         Map<WebViewDataType, String>.of(failures),
       ) {
    final Set<WebViewDataType> classified = <WebViewDataType>{
      ...this.clearedDataTypes,
      ...this.unsupportedDataTypes,
      ...this.failures.keys,
    };
    final int classificationCount =
        this.clearedDataTypes.length +
        this.unsupportedDataTypes.length +
        this.failures.length;
    if (classified.length != classificationCount) {
      throw ArgumentError(
        'A website data type cannot have more than one clearing outcome.',
      );
    }
    if (!classified.containsAll(WebViewDataType.values)) {
      throw ArgumentError(
        'Every website data type must have exactly one clearing outcome.',
      );
    }
  }

  /// Data categories whose native clearing operation completed successfully.
  final Set<WebViewDataType> clearedDataTypes;

  /// Data categories that the current platform cannot clear through this API.
  final Set<WebViewDataType> unsupportedDataTypes;

  /// Data categories that could not be cleared and their diagnostic messages.
  final Map<WebViewDataType, String> failures;

  /// Whether every website data category was cleared successfully.
  bool get isComplete =>
      unsupportedDataTypes.isEmpty &&
      failures.isEmpty &&
      clearedDataTypes.containsAll(WebViewDataType.values);
}

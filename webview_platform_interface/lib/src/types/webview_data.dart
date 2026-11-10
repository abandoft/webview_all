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

/// Exact origin, engine-defined domain record, or registrable site. These
/// scopes are deliberately distinct; an origin is never widened to a site.
enum WebViewDataScope { origin, domain, site }

@immutable
class WebViewDataTarget {
  const WebViewDataTarget({required this.scope, required this.value});
  factory WebViewDataTarget.origin(Uri uri) {
    String value = uri.toString();
    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty) {
      try {
        value = uri.origin;
      } on StateError {
        /* Invalid targets are rejected before native calls. */
      }
    }
    return WebViewDataTarget(scope: WebViewDataScope.origin, value: value);
  }
  final WebViewDataScope scope;
  final String value;
  Map<String, Object?> toMap() => {'scope': scope.name, 'value': value};
  bool get isValid {
    if (value.isEmpty ||
        value.length > 2048 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      return false;
    }
    if (scope == WebViewDataScope.origin) {
      final uri = Uri.tryParse(value);
      return uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          uri.origin == value;
    }
    if (scope == WebViewDataScope.domain) return true;
    return !RegExp(r'\s').hasMatch(value) &&
        !value.contains('/') &&
        !value.contains('\\') &&
        !value.contains(':') &&
        !value.contains('@');
  }
}

@immutable
class WebViewDataRecord {
  WebViewDataRecord({
    required this.target,
    required Set<WebViewDataType> dataTypes,
    this.sizeBytes,
  }) : dataTypes = Set.unmodifiable(dataTypes);
  final WebViewDataTarget target;
  final Set<WebViewDataType> dataTypes;

  /// Native estimate; null means the engine does not expose a size.
  final int? sizeBytes;
  factory WebViewDataRecord.fromMap(Map<Object?, Object?> value) =>
      WebViewDataRecord(
        target: WebViewDataTarget(
          scope: WebViewDataScope.values.byName(value['scope']! as String),
          value: value['value']! as String,
        ),
        dataTypes: (value['dataTypes']! as List)
            .map((v) => WebViewDataType.values[(v as num).toInt()])
            .toSet(),
        sizeBytes: (value['sizeBytes'] as num?)?.toInt(),
      );
}

/// The result of clearing website data from a WebView data store.
@immutable
class WebViewDataClearingResult {
  /// Creates a website data clearing result.
  WebViewDataClearingResult({
    Set<WebViewDataType>? requestedDataTypes,
    Set<WebViewDataType> clearedDataTypes = const <WebViewDataType>{},
    Set<WebViewDataType> unsupportedDataTypes = const <WebViewDataType>{},
    Map<WebViewDataType, String> failures = const <WebViewDataType, String>{},
  }) : requestedDataTypes = Set.unmodifiable(
         requestedDataTypes ?? WebViewDataType.values.toSet(),
       ),
       clearedDataTypes = UnmodifiableSetView<WebViewDataType>(
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
    if (!classified.containsAll(this.requestedDataTypes) ||
        !this.requestedDataTypes.containsAll(classified)) {
      throw ArgumentError(
        'Every requested website data type must have exactly one clearing outcome.',
      );
    }
  }

  /// Categories requested by this operation; all categories for legacy calls.
  final Set<WebViewDataType> requestedDataTypes;

  /// Data categories whose native clearing operation completed successfully.
  final Set<WebViewDataType> clearedDataTypes;

  /// Data categories that the current platform cannot clear through this API.
  final Set<WebViewDataType> unsupportedDataTypes;

  /// Data categories that could not be cleared and their diagnostic messages.
  final Map<WebViewDataType, String> failures;

  /// Whether every requested category was cleared successfully.
  bool get isComplete =>
      unsupportedDataTypes.isEmpty &&
      failures.isEmpty &&
      clearedDataTypes.containsAll(requestedDataTypes);
}

/// Native clearing operations available without deleting additional categories.
@immutable
class WebViewDataCapabilities {
  WebViewDataCapabilities({
    Iterable<Set<WebViewDataType>> clearingGroups = const [],
    this.limitation,
    this.records = false,
    this.recordsRequireTarget = false,
    Map<WebViewDataScope, Iterable<Set<WebViewDataType>>> scopedClearingGroups =
        const {},
  }) : clearingGroups = List.unmodifiable(
         clearingGroups.map(
           (group) => Set<WebViewDataType>.unmodifiable(group),
         ),
       ),
       scopedClearingGroups = Map.unmodifiable({
         for (final entry in scopedClearingGroups.entries)
           entry.key: List<Set<WebViewDataType>>.unmodifiable(
             entry.value.map((v) => Set<WebViewDataType>.unmodifiable(v)),
           ),
       });

  /// Each group can be cleared in one operation. Every category in a group
  /// must be requested, because the engine cannot clear its members separately.
  final List<Set<WebViewDataType>> clearingGroups;
  final String? limitation;
  final bool records;
  final bool recordsRequireTarget;
  final Map<WebViewDataScope, List<Set<WebViewDataType>>> scopedClearingGroups;

  Set<WebViewDataType> clearableTypes(Set<WebViewDataType> requested) => {
    for (final group in clearingGroups)
      if (group.isNotEmpty && requested.containsAll(group)) ...group,
  };

  bool canClear(Set<WebViewDataType> requested) =>
      clearableTypes(requested).containsAll(requested);
}

import 'dart:collection';

Object? freezeJavaScriptJsonValue(Object? value, [Set<Object>? ancestors]) {
  if (value == null || value is bool || value is String) {
    return value;
  }
  if (value is num) {
    if (!value.isFinite) {
      throw ArgumentError.value(
        value,
        'arguments',
        'JavaScript numeric arguments must be finite.',
      );
    }
    return value;
  }
  if (value is List<Object?>) {
    final Set<Object> activeAncestors = ancestors ?? HashSet<Object>.identity();
    if (!activeAncestors.add(value)) {
      throw ArgumentError.value(
        value,
        'arguments',
        'JavaScript arguments must not contain cyclic values.',
      );
    }
    try {
      return List<Object?>.unmodifiable(
        value.map<Object?>(
          (Object? nestedValue) =>
              freezeJavaScriptJsonValue(nestedValue, activeAncestors),
        ),
      );
    } finally {
      activeAncestors.remove(value);
    }
  }
  if (value is Map<Object?, Object?>) {
    final Set<Object> activeAncestors = ancestors ?? HashSet<Object>.identity();
    if (!activeAncestors.add(value)) {
      throw ArgumentError.value(
        value,
        'arguments',
        'JavaScript arguments must not contain cyclic values.',
      );
    }
    final Map<String, Object?> result = <String, Object?>{};
    try {
      value.forEach((Object? key, Object? nestedValue) {
        if (key is! String) {
          throw ArgumentError.value(
            key,
            'arguments',
            'JavaScript object argument keys must be strings.',
          );
        }
        result[key] = freezeJavaScriptJsonValue(nestedValue, activeAncestors);
      });
      return Map<String, Object?>.unmodifiable(result);
    } finally {
      activeAncestors.remove(value);
    }
  }
  throw ArgumentError.value(
    value,
    'arguments',
    'JavaScript arguments must contain only JSON-compatible values.',
  );
}

import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Parameters for invoking an asynchronous JavaScript function.
@immutable
class JavaScriptInvocationParams {
  /// Creates parameters for an asynchronous JavaScript invocation.
  JavaScriptInvocationParams({
    required this.functionBody,
    Map<String, Object?> arguments = const <String, Object?>{},
    this.timeout = const Duration(seconds: 30),
  }) : arguments = UnmodifiableMapView<String, Object?>(
         arguments.map<String, Object?>((String key, Object? value) {
           if (!_javaScriptIdentifierPattern.hasMatch(key)) {
             throw ArgumentError.value(
               key,
               'arguments',
               'JavaScript argument names must be valid identifiers.',
             );
           }
           if (_reservedJavaScriptIdentifiers.contains(key)) {
             throw ArgumentError.value(
               key,
               'arguments',
               'JavaScript argument names must not be reserved words.',
             );
           }
           return MapEntry<String, Object?>(key, _freezeJsonValue(value));
         }),
       ) {
    if (functionBody.trim().isEmpty) {
      throw ArgumentError.value(
        functionBody,
        'functionBody',
        'The JavaScript function body must not be empty.',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'The JavaScript timeout must be greater than zero.',
      );
    }
  }

  static final RegExp _javaScriptIdentifierPattern = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*$',
  );
  static const Set<String> _reservedJavaScriptIdentifiers = <String>{
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'enum',
    'eval',
    'export',
    'extends',
    'false',
    'finally',
    'for',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'instanceof',
    'interface',
    'let',
    'new',
    'null',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'yield',
    'arguments',
  };

  /// The body of the anonymous asynchronous JavaScript function.
  final String functionBody;

  /// Named arguments exposed as local variables to [functionBody].
  ///
  /// Values are restricted to recursively JSON-compatible values. Mutable
  /// lists and maps are copied when this object is constructed.
  final Map<String, Object?> arguments;

  /// The maximum time allowed for the invocation to complete.
  final Duration timeout;
}

Object? _freezeJsonValue(Object? value, [Set<Object>? ancestors]) {
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
              _freezeJsonValue(nestedValue, activeAncestors),
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
        result[key] = _freezeJsonValue(nestedValue, activeAncestors);
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

import 'dart:collection';

import 'package:flutter/foundation.dart';

import 'webview_javascript.dart';
import 'javascript_json.dart';

/// Parameters for invoking an asynchronous JavaScript function.
@immutable
class JavaScriptInvocationParams {
  /// Creates parameters for an asynchronous JavaScript invocation.
  JavaScriptInvocationParams({
    required this.functionBody,
    Map<String, Object?> arguments = const <String, Object?>{},
    this.timeout = const Duration(seconds: 30),
    this.world = WebViewJavaScriptWorld.page,
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
           return MapEntry<String, Object?>(
             key,
             freezeJavaScriptJsonValue(value),
           );
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

  /// The execution environment. The default preserves page-world invocation.
  final WebViewJavaScriptWorld world;
}

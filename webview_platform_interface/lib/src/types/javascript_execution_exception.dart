/// An error thrown or rejected by an asynchronous JavaScript invocation.
class JavaScriptExecutionException implements Exception {
  /// Creates a JavaScript execution exception.
  const JavaScriptExecutionException({
    required this.message,
    this.name,
    this.javaScriptStackTrace,
  });

  /// The error message reported by the JavaScript engine.
  final String message;

  /// The JavaScript error name, such as `TypeError`, when available.
  final String? name;

  /// The JavaScript stack trace, when available.
  final String? javaScriptStackTrace;

  @override
  String toString() {
    final String prefix = name == null || name!.isEmpty
        ? 'JavaScriptExecutionException'
        : name!;
    return '$prefix: ${message.replaceAll(RegExp(r'[\r\n]+'), ' ')}';
  }
}

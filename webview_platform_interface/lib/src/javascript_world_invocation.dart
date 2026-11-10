import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'types/types.dart';

/// World-aware fallback for native engines without a Promise evaluation API.
Future<Object?> invokeJavaScriptInWorld(
  JavaScriptInvocationParams params, {
  required Future<Object?> Function(String) evaluate,
  required bool Function() isCurrentDocument,
}) async {
  final watch = Stopwatch()..start();
  final random = Random.secure();
  final identifier =
      '__webviewAllAsync_' +
      List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
  final key = jsonEncode(identifier);
  Future<Object?> run(String source) {
    if (!isCurrentDocument()) {
      throw const JavaScriptExecutionException(
        name: 'AbortError',
        message: 'The document was replaced or closed.',
      );
    }
    final remaining = params.timeout - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'The JavaScript invocation timed out.',
        params.timeout,
      );
    }
    return evaluate(source).timeout(remaining);
  }

  final names = params.arguments.keys.join(',');
  final values = params.arguments.keys
      .map((name) => 'args[${jsonEncode(name)}]')
      .join(',');
  await run('''
(function() {
  const slot = {result: null};
  globalThis[$key] = slot;
  const release = () => { if (globalThis[$key] === slot) delete globalThis[$key]; };
  setTimeout(release, ${params.timeout.inMilliseconds});
  const args = JSON.parse(${jsonEncode(jsonEncode(params.arguments))});
  Promise.resolve().then(() => (async function($names) {
${params.functionBody}
  })($values)).then(value => {
    try { const encoded = JSON.stringify(value); slot.result = {ok: true, value: encoded === undefined ? null : encoded}; }
    catch (error) { fail(error); }
  }, fail);
  function fail(error) {
    slot.result = {ok: false, name: String(error && error.name || 'Error'), message: String(error && error.message || error)};
  }
  return null;
})();
''');
  try {
    while (true) {
      final raw = await run(
        'JSON.stringify(globalThis[$key]?.result ?? null);',
      );
      if (raw is String) {
        final result = jsonDecode(raw);
        if (result is Map<String, dynamic>) {
          if (result['ok'] == true) {
            final encoded = result['value'];
            return encoded is String ? jsonDecode(encoded) : null;
          }
          throw JavaScriptExecutionException(
            name: result['name'] as String?,
            message: result['message'] as String? ?? 'JavaScript failed.',
          );
        }
      }
      final remaining = params.timeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'The JavaScript invocation timed out.',
          params.timeout,
        );
      }
      await Future<void>.delayed(
        remaining < const Duration(milliseconds: 20)
            ? remaining
            : const Duration(milliseconds: 20),
      );
    }
  } finally {
    if (isCurrentDocument() && watch.elapsed < params.timeout) {
      try {
        await run('delete globalThis[$key]; null;');
      } catch (_) {}
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

Future<bool> forceGarbageCollection() async {
  final server = (await developer.Service.getInfo()).serverUri;
  if (server == null) return false;
  final socket = await WebSocket.connect(
    server.replace(scheme: 'ws', path: '${server.path}ws').toString(),
  );
  final pending = <String, Completer<Map<String, dynamic>>>{};
  final subscription = socket.listen((message) {
    final value = jsonDecode(message as String) as Map<String, dynamic>;
    pending.remove(value['id'])?.complete(value);
  });
  try {
    for (var i = 0; i < 4; i++) {
      final id = '$i';
      final reply = Completer<Map<String, dynamic>>();
      pending[id] = reply;
      socket.add(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': 'getAllocationProfile',
          'params': {
            'isolateId': developer.Service.getIsolateId(Isolate.current),
            'gc': true,
          },
        }),
      );
      final result = await reply.future.timeout(const Duration(seconds: 10));
      if (result.containsKey('error')) {
        throw StateError(
          'The VM service could not request garbage collection.',
        );
      }
    }
    return true;
  } finally {
    await socket.close();
    await subscription.cancel();
  }
}

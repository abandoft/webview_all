import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

class _Owner {
  final bridge = WebViewResourceBridge(
    scheme: 'https',
    configure: (_, _, _) async {},
  );
  int calls = 0;

  Future<void> enable() => bridge.update(
    WebViewResourceDelegate(
      onRequest: (_) {
        calls++;
        return null;
      },
    ),
  );
}

@pragma('vm:never-inline')
Future<WeakReference<_Owner>> createOwner() async {
  final owner = _Owner();
  await owner.enable();
  return WeakReference<_Owner>(owner);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resource callbacks do not retain their released owner', () async {
    final info = await developer.Service.getInfo();
    final server = info.serverUri;
    if (server == null) {
      markTestSkipped('Run with --enable-vmservice to verify collection.');
      return;
    }
    final socket = await WebSocket.connect(
      server.replace(scheme: 'ws', path: '${server.path}ws').toString(),
    );
    final pending = <String, Completer<Map<String, dynamic>>>{};
    final subscription = socket.listen((message) {
      final value = jsonDecode(message as String) as Map<String, dynamic>;
      pending.remove(value['id'])?.complete(value);
    });
    addTearDown(socket.close);
    addTearDown(subscription.cancel);
    final weak = await createOwner();
    for (var i = 0; i < 4; i++) {
      final id = '$i';
      final reply = Completer<Map<String, dynamic>>();
      pending[id] = reply;
      socket.add(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': id,
          'method': 'getAllocationProfile',
          'params': <String, Object?>{
            'isolateId': developer.Service.getIsolateId(Isolate.current),
            'gc': true,
          },
        }),
      );
      final result = await reply.future;
      expect(result.containsKey('error'), isFalse);
    }
    expect(weak.target, isNull);
  });
}

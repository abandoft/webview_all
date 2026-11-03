import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_linux/src/linux_resource_server.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WebViewResourceBridge bridge;
  late LinuxResourceServer server;
  late HttpClient client;

  setUp(() async {
    bridge = WebViewResourceBridge(
      scheme: 'http',
      configure: (_, _, _) async {},
    );
    server = await LinuxResourceServer.bind(bridge);
    client = _LoopbackHttpOverrides().createHttpClient(null);
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    await bridge.close();
  });

  Future<HttpClientResponse> get(
    Uri uri, {
    String method = 'GET',
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    return request.close();
  }

  Future<List<int>> read(HttpClientResponse response) =>
      response.fold(<int>[], (bytes, chunk) => bytes..addAll(chunk));

  test(
    'token-protected URLs preserve resource paths and range headers',
    () async {
      WebViewResourceRequest? received;
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (request) {
            received = request;
            return WebViewResourceResponse.bytes(
              Uint8List.fromList(<int>[0, 1, 2, 3, 4]),
              mimeType: 'application/octet-stream',
            );
          },
        ),
      );
      final uri = bridge.getResourceUri('图像/a%20b.bin')!;
      expect(uri.host, InternetAddress.loopbackIPv4.address);
      final ranged = await get(
        uri,
        headers: <String, String>{'Range': 'bytes=1-2'},
      );
      expect(ranged.statusCode, 206);
      expect(ranged.contentLength, 2);
      expect(ranged.headers.value('content-range'), 'bytes 1-2/5');
      expect(ranged.headers.value('referrer-policy'), 'no-referrer');
      expect(await read(ranged), <int>[1, 2]);
      expect(received!.uri, uri);
      expect(received!.path, '/图像/a%20b.bin');
      received = null;
      final rejected = await get(uri.replace(path: '/wrong-token/file'));
      expect(rejected.statusCode, 403);
      await read(rejected);
      expect(received, isNull);
      final spoofed = await get(uri.replace(host: 'localhost'));
      expect(spoofed.statusCode, 403);
      await read(spoofed);
      expect(received, isNull);
      final head = await get(uri, method: 'HEAD');
      expect(head.contentLength, 5);
      expect(await read(head), isEmpty);
    },
  );

  test(
    'file URLs remain usable after disabling and re-enabling the delegate',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'resource-http-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/video.bin');
      await file.writeAsBytes(<int>[5, 6, 7, 8]);
      final delegate = WebViewResourceDelegate(
        onRequest: (_) => WebViewResourceResponse.file(
          file.path,
          mimeType: 'application/octet-stream',
        ),
      );
      await bridge.update(delegate);
      final uri = bridge.getResourceUri('video.bin')!;
      final response = await get(
        uri,
        headers: <String, String>{'Range': 'bytes=-2'},
      );
      expect(response.statusCode, 206);
      expect(await read(response), <int>[7, 8]);
      await bridge.update(null);
      final disabled = await get(uri);
      expect(disabled.statusCode, 404);
      expect(disabled.headers.value('cache-control'), 'no-store');
      await read(disabled);
      await bridge.update(delegate);
      final restored = await get(uri);
      expect(restored.statusCode, 200);
      expect(await read(restored), <int>[5, 6, 7, 8]);
    },
  );

  test(
    'streams arrive incrementally and disconnects cancel their producer',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      addTearDown(() async {
        client.close(force: true);
        await bridge.close();
        await source.close();
      });
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (_) => WebViewResourceResponse.stream(
            source.stream,
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      final pending = get(bridge.getResourceUri('stream')!);
      source.add(<int>[1, 2, 3]);
      final response = await pending;
      final first = Completer<List<int>>();
      final subscription = response.listen((chunk) {
        if (!first.isCompleted) first.complete(chunk);
      }, onError: (Object _) {});
      expect(await first.future.timeout(const Duration(seconds: 3)), <int>[
        1,
        2,
        3,
      ]);
      client.close(force: true);
      await cancelled.future.timeout(const Duration(seconds: 3));
      await subscription.cancel();
    },
  );

  test(
    'stream failures abort the response instead of accepting a partial body',
    () async {
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (_) => WebViewResourceResponse.stream(
            Stream<List<int>>.fromIterable(<List<int>>[
              <int>[1, 2],
            ]),
            contentLength: 10,
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      final response = await get(bridge.getResourceUri('short')!);
      await expectLater(read(response), throwsA(isA<HttpException>()));
    },
  );

  test(
    'closing the server cancels a pending callback and its late stream',
    () async {
      final requested = Completer<void>();
      final pending = Completer<WebViewResourceResponse?>();
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      addTearDown(source.close);
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (_) {
            requested.complete();
            return pending.future;
          },
        ),
      );
      final failed = expectLater(
        get(bridge.getResourceUri('pending')!),
        throwsA(isA<HttpException>()),
      );
      await requested.future.timeout(const Duration(seconds: 3));
      await server.close();
      await failed;
      pending.complete(
        WebViewResourceResponse.stream(
          source.stream,
          mimeType: 'application/octet-stream',
        ),
      );
      await cancelled.future.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'closing the server aborts an active response and cancels its producer',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      addTearDown(source.close);
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (_) => WebViewResourceResponse.stream(
            source.stream,
            mimeType: 'application/octet-stream',
          ),
        ),
      );
      final response = await get(bridge.getResourceUri('active')!);
      final failed = expectLater(read(response), throwsA(isA<HttpException>()));
      await server.close();
      await failed;
      await cancelled.future.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'closing the controller transport closes its listening socket',
    () async {
      await bridge.update(const WebViewResourceDelegate(onRequest: _missing));
      final uri = bridge.getResourceUri('closed')!;
      await server.close();
      await expectLater(get(uri), throwsA(isA<SocketException>()));
    },
  );
}

WebViewResourceResponse? _missing(WebViewResourceRequest _) => null;

// Use real loopback I/O without changing the widget binding's HTTP overrides.
class _LoopbackHttpOverrides extends HttpOverrides {}

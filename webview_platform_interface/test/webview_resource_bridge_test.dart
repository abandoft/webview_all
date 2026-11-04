import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late WebViewResourceBridge bridge;

  Future<Object?> native(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    final result = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      bridge.channelName,
      codec.encodeMethodCall(MethodCall(method, arguments)),
      result.complete,
    );
    final reply = await result.future;
    return reply == null ? null : codec.decodeEnvelope(reply);
  }

  Future<Map<Object?, Object?>> open({
    String id = 'one',
    String method = 'GET',
    Map<String, String> headers = const <String, String>{},
    String? uri,
  }) async =>
      (await native('open', <String, Object?>{
            'id': id,
            'uri': uri ?? bridge.getResourceUri('media.bin').toString(),
            'method': method,
            'headers': headers,
          }))!
          as Map<Object?, Object?>;

  Future<List<int>> readAll([String id = 'one']) async {
    final output = <int>[];
    while (true) {
      final data =
          await native('read', <String, Object?>{'id': id, 'length': 65536})
              as Uint8List?;
      if (data == null) return output;
      output.addAll(data);
    }
  }

  Future<void> serve(
    WebViewResourceResponse? Function(WebViewResourceRequest) response,
  ) => bridge.update(WebViewResourceDelegate(onRequest: response));

  setUp(() {
    bridge = WebViewResourceBridge(
      scheme: 'webview-all-resource',
      configure: (_, _, _) async {},
    );
  });
  tearDown(() async => bridge.close());

  testWidgets(
    'delegate deadlines override the bridge default for callbacks and reads',
    (tester) async {
      await bridge.close();
      bridge = WebViewResourceBridge(
        scheme: 'webview-all-resource',
        configure: (_, _, _) async {},
        requestTimeout: const Duration(milliseconds: 5),
      );
      await bridge.update(
        WebViewResourceDelegate(
          requestTimeout: const Duration(milliseconds: 30),
          onRequest: (_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return WebViewResourceResponse.stream(
              Stream<List<int>>.fromFuture(
                Future<List<int>>.delayed(
                  const Duration(milliseconds: 20),
                  () => <int>[1, 2, 3],
                ),
              ),
              mimeType: 'application/octet-stream',
            );
          },
        ),
      );
      expect(bridge.requestTimeout, const Duration(milliseconds: 30));
      final response = open();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect((await response)['statusCode'], 200);
      final body = readAll();
      await tester.pump();
      // The overall request takes 40 ms, but each operation stays below 30 ms.
      await tester.pump(const Duration(milliseconds: 20));
      expect(await body, <int>[1, 2, 3]);
      await bridge.update(null);
      expect(bridge.requestTimeout, const Duration(milliseconds: 5));
    },
  );

  for (final operation in <String>['cancel', 'replace', 'close']) {
    test(
      '$operation keeps the cleanup deadline with a long request timeout',
      () async {
        await bridge.close();
        bridge = WebViewResourceBridge(
          scheme: 'webview-all-resource',
          configure: (_, _, _) async {},
          requestTimeout: const Duration(milliseconds: 10),
        );
        final cancellation = Completer<void>();
        final source = StreamController<List<int>>(
          onCancel: () => cancellation.future,
        );
        await bridge.update(
          WebViewResourceDelegate(
            requestTimeout: const Duration(hours: 1),
            onRequest: (_) => WebViewResourceResponse.stream(
              source.stream,
              mimeType: 'application/octet-stream',
            ),
          ),
        );
        expect((await open())['statusCode'], 200);
        final cleanup = switch (operation) {
          'cancel' => native('cancel', <String, Object?>{'id': 'one'}),
          'replace' => bridge.update(null),
          _ => bridge.close(),
        };
        try {
          await cleanup.timeout(const Duration(seconds: 2));
        } finally {
          cancellation.complete();
          unawaited(source.close());
        }
      },
    );
  }

  test('invalid delegate deadlines preserve the active delegate', () async {
    await serve(
      (_) => WebViewResourceResponse.bytes(
        Uint8List.fromList(<int>[42]),
        mimeType: 'application/octet-stream',
      ),
    );
    for (final timeout in <Duration>[
      Duration.zero,
      const Duration(milliseconds: -1),
      const Duration(microseconds: 1001),
      const Duration(milliseconds: 2147483648),
    ]) {
      await expectLater(
        bridge.update(
          WebViewResourceDelegate(
            requestTimeout: timeout,
            onRequest: (_) => null,
          ),
        ),
        throwsArgumentError,
      );
    }
    expect(bridge.requestTimeout, const Duration(seconds: 30));
    expect((await open())['statusCode'], 200);
    expect(await readAll(), <int>[42]);
  });

  test(
    'a configured deadline expires without blocking a later request',
    () async {
      await bridge.update(
        WebViewResourceDelegate(
          requestTimeout: const Duration(milliseconds: 20),
          onRequest: (_) => Completer<WebViewResourceResponse?>().future,
        ),
      );
      expect((await open())['statusCode'], 504);
      await serve((_) => null);
      expect(bridge.requestTimeout, const Duration(seconds: 30));
      expect((await open(id: 'next'))['statusCode'], 404);
    },
  );

  test(
    'isolates controllers and rejects unrelated URLs before invoking application code',
    () async {
      var calls = 0;
      await serve((_) {
        calls++;
        return null;
      });
      expect((await open(uri: 'https://example.org/file'))['statusCode'], 403);
      expect(
        (await open(
          uri: 'webview-all-resource://other.webview.invalid/file',
        ))['statusCode'],
        403,
      );
      expect(
        (await open(
          uri: 'webview-all-resource://user@${bridge.host}/file',
        ))['statusCode'],
        403,
      );
      expect(calls, 0);
      final second = WebViewResourceBridge(
        scheme: 'webview-all-resource',
        configure: (_, _, _) async {},
      );
      addTearDown(second.close);
      expect(second.host, isNot(bridge.host));
      expect(() => bridge.getResourceUri('../secret'), throwsArgumentError);
      expect(bridge.getResourceUri('图像/a b.png')!.pathSegments, <String>[
        '图像',
        'a b.png',
      ]);
    },
  );

  test(
    'resource paths preserve literal percent escapes and URL delimiters',
    () async {
      String? received;
      await serve((request) {
        received = request.path;
        return null;
      });
      for (final path in <String>[
        'a%20b.bin',
        'a%2fb.bin',
        '%2e%2e/secret',
        '100%.png',
        '图像/a?b#c.png',
      ]) {
        final uri = bridge.getResourceUri(path)!;
        expect(uri.query, isEmpty);
        expect(uri.fragment, isEmpty);
        await open(uri: uri.toString());
        expect(received, '/$path');
      }
    },
  );

  test(
    'null means missing resource; unrecognized methods are rejected',
    () async {
      await serve((_) => null);
      final missing = await open();
      expect(missing['statusCode'], 404);
      expect((missing['headers']! as Map)['cache-control'], 'no-store');
      final rejected = await open(method: 'POST');
      expect(rejected['statusCode'], 405);
      expect((rejected['headers']! as Map)['allow'], 'GET, HEAD');
      expect((rejected['headers']! as Map)['cache-control'], 'no-store');
      expect(await readAll(), isEmpty);
    },
  );

  test(
    'reads bytes with case-insensitive range and known content length',
    () async {
      WebViewResourceRequest? received;
      await serve((request) {
        received = request;
        return WebViewResourceResponse.bytes(
          Uint8List.fromList(List<int>.generate(100, (i) => i)),
          mimeType: 'application/octet-stream',
        );
      });
      final response = await open(
        headers: <String, String>{'Range': 'bytes=10-19'},
      );
      expect(response['statusCode'], 206);
      expect(response['contentLength'], 10);
      expect((response['headers']! as Map)['content-range'], 'bytes 10-19/100');
      expect((response['headers']! as Map)['cache-control'], 'no-store');
      expect(received!.headers['range'], 'bytes=10-19');
      expect(await readAll(), List<int>.generate(10, (i) => i + 10));
    },
  );

  for (final range in <String>['bytes=-3', 'bytes=7-', 'bytes=7-100']) {
    test('supports suffix and open-ended ranges: $range', () async {
      await serve(
        (_) => WebViewResourceResponse.bytes(
          Uint8List.fromList(List<int>.generate(10, (i) => i)),
          mimeType: 'application/octet-stream',
        ),
      );
      expect(
        (await open(headers: <String, String>{'range': range}))['statusCode'],
        206,
      );
      expect(await readAll(), <int>[7, 8, 9]);
    });
  }

  test(
    'returns 416 for unsatisfiable ranges and ignores unsupported multipart requests',
    () async {
      await serve(
        (_) => WebViewResourceResponse.bytes(
          Uint8List(10),
          mimeType: 'application/octet-stream',
        ),
      );
      final response = await open(
        headers: <String, String>{'range': 'bytes=10-20'},
      );
      expect(response['statusCode'], 416);
      expect((response['headers']! as Map)['content-range'], 'bytes */10');
      expect((response['headers']! as Map)['cache-control'], 'no-store');
      expect(
        (await open(
          headers: <String, String>{'range': 'bytes=0-1,3-4'},
        ))['statusCode'],
        200,
      );
      expect(await readAll(), hasLength(10));
    },
  );

  test('If-Range mismatch returns the complete response', () async {
    await serve(
      (_) => WebViewResourceResponse.bytes(
        Uint8List(10),
        mimeType: 'application/octet-stream',
        headers: <String, String>{'ETag': '"new"'},
      ),
    );
    expect(
      (await open(
        headers: <String, String>{'range': 'bytes=1-2', 'if-range': '"old"'},
      ))['statusCode'],
      200,
    );
    expect(await readAll(), hasLength(10));
    expect(
      (await open(
        headers: <String, String>{'range': 'bytes=1-2', 'if-range': '"new"'},
      ))['statusCode'],
      206,
    );
    expect(await readAll(), hasLength(2));
  });

  test(
    'HEAD keeps the full length and does not subscribe to a stream',
    () async {
      var subscribed = false;
      final source = Stream<List<int>>.multi((controller) {
        subscribed = true;
        controller.close();
      });
      await serve(
        (_) => WebViewResourceResponse.stream(
          source,
          contentLength: 100,
          mimeType: 'application/octet-stream',
        ),
      );
      final response = await open(method: 'HEAD');
      expect(response['contentLength'], 100);
      expect(subscribed, isFalse);
      expect(await readAll(), isEmpty);
    },
  );

  test('file ranges use seek and bounded reads, including HEAD', () async {
    final directory = await Directory.systemTemp.createTemp(
      'webview-resource-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = await File(
      '${directory.path}/large.bin',
    ).open(mode: FileMode.write);
    await file.writeFrom(Uint8List(1024 * 1024));
    await file.writeFrom(<int>[1, 2, 3, 4]);
    await file.close();
    await serve(
      (_) => WebViewResourceResponse.file(
        '${directory.path}/large.bin',
        mimeType: 'application/octet-stream',
      ),
    );
    expect((await open(method: 'HEAD'))['contentLength'], 1024 * 1024 + 4);
    expect(await readAll(), isEmpty);
    expect(
      (await open(
        headers: <String, String>{'range': 'bytes=-4'},
      ))['statusCode'],
      206,
    );
    expect(await readAll(), <int>[1, 2, 3, 4]);
  });

  test(
    'splits large stream events into bounded transport chunks and cancels producers',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      await serve(
        (_) => WebViewResourceResponse.stream(
          source.stream,
          mimeType: 'application/octet-stream',
        ),
      );
      expect((await open())['contentLength'], -1);
      source.add(List<int>.filled(100000, 7));
      final first =
          await native('read', <String, Object?>{
                'id': 'one',
                'length': 1000000,
              })
              as Uint8List;
      expect(first, hasLength(65536));
      final second =
          await native('read', <String, Object?>{'id': 'one', 'length': 65536})
              as Uint8List;
      expect(second, hasLength(34464));
      await native('cancel', <String, Object?>{'id': 'one'});
      expect(cancelled, isTrue);
      await source.close();
    },
  );

  test('cancelling a pending callback ignores a late response', () async {
    final pending = Completer<WebViewResourceResponse?>();
    final seen = Completer<WebViewResourceRequest>();
    await bridge.update(
      WebViewResourceDelegate(
        onRequest: (request) {
          seen.complete(request);
          return pending.future;
        },
      ),
    );
    final opening = open();
    await seen.future;
    await native('cancel', <String, Object?>{'id': 'one'});
    expect((await opening)['statusCode'], 404);
    pending.complete(
      WebViewResourceResponse.bytes(
        Uint8List(10),
        mimeType: 'application/octet-stream',
      ),
    );
    expect(await readAll(), isEmpty);
  });

  test(
    'replacing a delegate cancels an existing body before serving new requests',
    () async {
      var cancelled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      await serve(
        (_) => WebViewResourceResponse.stream(
          source.stream,
          mimeType: 'application/octet-stream',
        ),
      );
      await open();
      final reading = native('read', <String, Object?>{'id': 'one'});
      await Future<void>.delayed(Duration.zero);
      await serve((_) => null);
      expect(await reading, isNull);
      expect(cancelled, isTrue);
      expect(await readAll(), isEmpty);
      expect((await open(id: 'two'))['statusCode'], 404);
      await source.close();
    },
  );

  test(
    'native file bodies preserve range metadata without reading data through Dart',
    () async {
      await bridge.close();
      bridge = WebViewResourceBridge(
        scheme: 'https',
        configure: (_, _, _) async {},
        nativeBodies: true,
        supportsStreaming: false,
      );
      final directory = await Directory.systemTemp.createTemp(
        'webview-native-resource-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/file.bin',
      ).writeAsBytes(<int>[1, 2, 3, 4]);
      await serve(
        (_) => WebViewResourceResponse.file(
          file.path,
          mimeType: 'application/octet-stream',
        ),
      );
      final response = await open(
        headers: <String, String>{'range': 'bytes=1-2'},
      );
      expect(response['filePath'], file.path);
      expect(response['offset'], 1);
      expect(response['contentLength'], 2);
      expect(await readAll(), isEmpty);
      await serve(
        (_) => WebViewResourceResponse.stream(
          Stream<List<int>>.value(<int>[1]),
          mimeType: 'application/octet-stream',
        ),
      );
      expect((await open())['statusCode'], 501);
    },
  );

  test(
    'callback failures and invalid headers fail one resource without escaping',
    () async {
      await bridge.update(
        WebViewResourceDelegate(onRequest: (_) => throw StateError('broken')),
      );
      expect((await open())['statusCode'], 500);
      await serve(
        (_) => WebViewResourceResponse.bytes(
          Uint8List(1),
          mimeType: 'image/png',
          headers: <String, String>{'X-Bad': 'a\r\nb'},
        ),
      );
      expect((await open())['statusCode'], 500);
      await serve(
        (_) =>
            WebViewResourceResponse.bytes(Uint8List(1), mimeType: 'image/png'),
      );
      expect((await open())['statusCode'], 200);
      expect(await readAll(), <int>[0]);
    },
  );

  test(
    'short streams fail instead of silently accepting truncated content',
    () async {
      await serve(
        (_) => WebViewResourceResponse.stream(
          Stream<List<int>>.value(<int>[1]),
          contentLength: 10,
          mimeType: 'application/octet-stream',
        ),
      );
      await open();
      expect(await native('read', <String, Object?>{'id': 'one'}), <int>[1]);
      await expectLater(
        native('read', <String, Object?>{'id': 'one'}),
        throwsA(isA<PlatformException>()),
      );
    },
  );

  test('cancels a stream before its first native read', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await serve(
      (_) => WebViewResourceResponse.stream(
        source.stream,
        mimeType: 'application/octet-stream',
      ),
    );
    await open();
    await bridge.update(null);
    expect(cancelled, isTrue);
    await source.close();
  });

  test('cancels streams returned by late callbacks', () async {
    final pending = Completer<WebViewResourceResponse?>();
    final seen = Completer<void>();
    final cancelled = Completer<void>();
    final source = StreamController<List<int>>(onCancel: cancelled.complete);
    await bridge.update(
      WebViewResourceDelegate(
        onRequest: (_) {
          seen.complete();
          return pending.future;
        },
      ),
    );
    final opening = open();
    await seen.future;
    await native('cancel', <String, Object?>{'id': 'one'});
    expect((await opening)['statusCode'], 404);
    pending.complete(
      WebViewResourceResponse.stream(
        source.stream,
        mimeType: 'application/octet-stream',
      ),
    );
    await cancelled.future.timeout(const Duration(seconds: 1));
    await source.close();
  });

  test('captures stream errors that arrive before the first read', () async {
    await serve(
      (_) => WebViewResourceResponse.stream(
        Stream<List<int>>.error(StateError('source failed')),
        mimeType: 'application/octet-stream',
      ),
    );
    expect((await open())['statusCode'], 200);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      native('read', <String, Object?>{'id': 'one'}),
      throwsA(isA<PlatformException>()),
    );
  });

  test('rejects inconsistent stream length and cancels the source', () async {
    var cancelled = false;
    final source = StreamController<List<int>>(
      onCancel: () {
        cancelled = true;
      },
    );
    await serve(
      (_) => WebViewResourceResponse.stream(
        source.stream,
        contentLength: 2,
        headers: <String, String>{'Content-Length': '3'},
        mimeType: 'application/octet-stream',
      ),
    );
    expect((await open())['statusCode'], 500);
    expect(cancelled, isTrue);
    await source.close();
  });

  test(
    'callback timeout fails one resource and permits the next request',
    () async {
      await bridge.close();
      bridge = WebViewResourceBridge(
        scheme: 'webview-all-resource',
        configure: (_, _, _) async {},
        requestTimeout: const Duration(milliseconds: 20),
      );
      await bridge.update(
        WebViewResourceDelegate(
          onRequest: (_) => Completer<WebViewResourceResponse?>().future,
        ),
      );
      expect((await open())['statusCode'], 504);
      await serve((_) => null);
      expect((await open(id: 'next'))['statusCode'], 404);
    },
  );

  test(
    'closing cancels native configuration and queued delegate updates',
    () async {
      await bridge.close();
      final started = Completer<void>();
      final configuration = Completer<void>();
      bridge = WebViewResourceBridge(
        scheme: 'https',
        configure: (_, _, _) {
          started.complete();
          return configuration.future;
        },
      );
      final updating = bridge.update(
        WebViewResourceDelegate(onRequest: (_) => null),
      );
      await started.future;
      final queued = bridge.update(null);
      await bridge.close();
      await updating;
      await queued;
      configuration.completeError(StateError('native view was released'));
      await Future<void>.delayed(Duration.zero);
      await expectLater(bridge.update(null), throwsStateError);
    },
  );
}

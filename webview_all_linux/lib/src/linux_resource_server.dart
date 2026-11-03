import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

/// A controller-owned loopback transport for WebKitGTK's HTTP media loader.
class LinuxResourceServer {
  LinuxResourceServer._(HttpServer server, this._bridge)
    : _disposal = _ResourceServerDisposal(server) {
    final weak = WeakReference<LinuxResourceServer>(this);
    server.listen(
      (request) {
        final target = weak.target;
        if (target == null) {
          unawaited(request.response.close());
        } else {
          unawaited(target._serve(request));
        }
      },
      onError: (Object error) {
        debugPrint('webview_all: Linux resource server failed: $error');
      },
    );
    _finalizer.attach(this, _disposal, detach: this);
  }

  static final Finalizer<_ResourceServerDisposal> _finalizer =
      Finalizer<_ResourceServerDisposal>(
        (disposal) => unawaited(disposal.close()),
      );

  static Future<LinuxResourceServer> bind(WebViewResourceBridge bridge) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.autoCompress = false;
    try {
      bridge.setBaseUri(
        Uri(
          scheme: 'http',
          host: server.address.address,
          port: server.port,
          pathSegments: <String>[bridge.host, ''],
        ),
      );
      return LinuxResourceServer._(server, bridge);
    } catch (_) {
      await server.close(force: true);
      rethrow;
    }
  }

  final _ResourceServerDisposal _disposal;
  final WebViewResourceBridge _bridge;
  int _nextId = 0;
  bool _closed = false;

  Future<void> _serve(HttpRequest request) async {
    final id = 'http-${++_nextId}';
    var disconnected = false;
    Socket? socket;
    StreamSubscription<Uint8List>? subscription;
    Future<void> cancel() async {
      await _bridge.handleCall(
        MethodCall('cancel', <String, Object?>{'id': id}),
      );
    }

    try {
      // HttpResponse pauses its input while writing, so it cannot reliably
      // report an idle client's disconnect. Keep Dart's HTTP parser, then own
      // the response socket so cancellation also works between stream events.
      final connection = await request.response.detachSocket(
        writeHeaders: false,
      );
      socket = connection;
      _disposal.sockets.add(connection);
      void disconnect() {
        if (disconnected) return;
        disconnected = true;
        unawaited(cancel());
        connection.destroy();
      }

      subscription = connection.listen(
        (_) {},
        onDone: disconnect,
        onError: (Object _) => disconnect(),
      );
      unawaited(
        connection.done.then<void>(
          (_) => disconnect(),
          onError: (Object _, StackTrace __) => disconnect(),
        ),
      );
      if (disconnected || _closed) return;
      final headers = <String, String>{};
      request.headers.forEach((name, values) {
        headers[name] = values.join(', ');
      });
      final response =
          (await _bridge.handleCall(
                MethodCall('open', <String, Object?>{
                  'id': id,
                  'uri': request.requestedUri.toString(),
                  'method': request.method,
                  'headers': headers,
                }),
              ))!
              as Map<String, Object?>;
      if (disconnected || _closed) return;
      final status = response['statusCode']! as int;
      final responseHeaders = Map<String, String>.of(
        response['headers']! as Map<String, String>,
      );
      final chunked =
          response['contentLength'] == -1 && request.method != 'HEAD';
      responseHeaders['connection'] = 'close';
      responseHeaders.putIfAbsent('referrer-policy', () => 'no-referrer');
      responseHeaders.putIfAbsent(
        'date',
        () => HttpDate.format(DateTime.now()),
      );
      if (chunked) responseHeaders['transfer-encoding'] = 'chunked';
      final header = StringBuffer('HTTP/1.1 $status Resource\r\n');
      responseHeaders.forEach(
        (name, value) => header.write('$name: $value\r\n'),
      );
      header.write('\r\n');
      connection.add(utf8.encode(header.toString()));
      await connection.flush().timeout(_bridge.requestTimeout);
      if (request.method != 'HEAD') {
        while (!disconnected && !_closed) {
          final data =
              await _bridge.handleCall(
                    MethodCall('read', <String, Object?>{
                      'id': id,
                      'length': 65536,
                    }),
                  )
                  as Uint8List?;
          if (data == null || disconnected || _closed) break;
          if (chunked) {
            connection.add(
              ascii.encode('${data.length.toRadixString(16)}\r\n'),
            );
          }
          connection.add(data);
          if (chunked) connection.add(const <int>[13, 10]);
          await connection.flush().timeout(_bridge.requestTimeout);
        }
      }
      if (chunked && !disconnected && !_closed) {
        connection.add(ascii.encode('0\r\n\r\n'));
      }
      await connection.flush().timeout(_bridge.requestTimeout);
      await connection.close().timeout(_bridge.requestTimeout);
    } catch (error) {
      if (!disconnected && !_closed) {
        debugPrint('webview_all: Linux application resource failed: $error');
      }
    } finally {
      socket?.destroy();
      if (socket != null) _disposal.sockets.remove(socket);
      await subscription?.cancel();
      await cancel();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _finalizer.detach(this);
    await _disposal.close();
  }
}

class _ResourceServerDisposal {
  _ResourceServerDisposal(this.server);

  final HttpServer server;
  final Set<Socket> sockets = <Socket>{};
  Future<void>? _closing;

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
    sockets.clear();
    await server.close(force: true);
  }
}

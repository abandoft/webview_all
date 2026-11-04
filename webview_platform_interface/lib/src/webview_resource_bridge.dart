import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'resources/resource_file.dart';
import 'platform_webview_controller.dart';
import 'types/webview_resource.dart';

typedef ResourceBridgeConfiguration =
    Future<void> Function(String channel, String host, bool enabled);

/// Shared implementation for native controllers with a resource transport.
mixin WebViewResourceControllerMixin on PlatformWebViewController {
  WebViewResourceBridge? _resourceBridge;

  String get resourceUrlScheme;
  bool get supportsStreamingResources => true;
  bool get nativeResourceBodies => false;

  Future<void> configureResourceBridge(
    String channel,
    String host,
    bool enabled,
  );

  @protected
  WebViewResourceBridge get resourceBridge {
    final weakThis = WeakReference<WebViewResourceControllerMixin>(this);
    return _resourceBridge ??= WebViewResourceBridge(
      scheme: resourceUrlScheme,
      supportsStreaming: supportsStreamingResources,
      nativeBodies: nativeResourceBodies,
      configure: (channel, host, enabled) {
        final target = weakThis.target;
        if (target == null) {
          throw StateError('The resource controller was released.');
        }
        return target.configureResourceBridge(channel, host, enabled);
      },
    );
  }

  @override
  WebViewResourceCapabilities get resourceCapabilities =>
      WebViewResourceCapabilities(
        supportsResources: true,
        supportsStreaming: supportsStreamingResources,
      );

  @override
  Future<void> setResourceDelegate(WebViewResourceDelegate? delegate) {
    if (delegate == null && _resourceBridge == null) {
      return Future<void>.value();
    }
    return resourceBridge.update(delegate);
  }

  @override
  Uri? getResourceUri(String path) => resourceBridge.getResourceUri(path);

  /// Called by native controllers before releasing their WebView.
  Future<void>? disposeResourceBridge() => _resourceBridge?.close();
}

/// Bounded request/body transport used by native platform implementations.
///
/// Native readers request one chunk at a time. This class is a platform bridge;
/// applications should use WebViewController's resource methods instead.
class WebViewResourceBridge {
  WebViewResourceBridge({
    required String scheme,
    required ResourceBridgeConfiguration configure,
    this.supportsStreaming = true,
    this.nativeBodies = false,
    Duration requestTimeout = const Duration(seconds: 30),
    BinaryMessenger? binaryMessenger,
  }) : _defaultRequestTimeout = requestTimeout,
       _scheme = scheme,
       _configure = configure,
       host = _newHost() {
    _baseUri = Uri(scheme: _scheme, host: host, path: '/');
    _channel = MethodChannel(
      'com.abandoft.webview_all/resources/$host',
      const StandardMethodCodec(),
      binaryMessenger,
    );
    // The messenger must not keep application callbacks and their controller
    // alive after the application releases them.
    final weak = WeakReference<WebViewResourceBridge>(this);
    _channel.setMethodCallHandler((call) async {
      return weak.target?._handleCall(call);
    });
    _channelFinalizer.attach(this, _channel, detach: this);
  }

  static final Finalizer<MethodChannel> _channelFinalizer =
      Finalizer<MethodChannel>((channel) {
        channel.setMethodCallHandler(null);
      });

  static String _newHost() {
    final random = Random.secure();
    final token = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'resource-$token.webview.invalid';
  }

  final String _scheme;
  final ResourceBridgeConfiguration _configure;
  final bool supportsStreaming;

  /// Whether the native engine reads file/byte bodies without Dart chunk calls.
  final bool nativeBodies;
  final Duration _defaultRequestTimeout;

  /// Effective deadline shared with the native resource transport.
  Duration get requestTimeout =>
      _delegate?.requestTimeout ?? _defaultRequestTimeout;
  final String host;
  late final MethodChannel _channel;
  late Uri _baseUri;
  final Map<String, _ResourceBody> _requests = <String, _ResourceBody>{};
  WebViewResourceDelegate? _delegate;
  Future<void> _updates = Future<void>.value();
  final Completer<void> _closedSignal = Completer<void>();
  bool _closed = false;

  String get channelName => _channel.name;

  /// Sets the transport endpoint while no requests are in progress.
  /// Platform adapters may use a token-protected loopback URL base.
  void setBaseUri(Uri uri) {
    if (_closed || _requests.isNotEmpty) {
      throw StateError('The resource transport is closed or in use.');
    }
    if (uri.scheme.isEmpty ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !uri.path.endsWith('/')) {
      throw ArgumentError.value(uri, 'uri', 'Invalid resource URL base.');
    }
    _baseUri = uri;
  }

  Uri? getResourceUri(String path) {
    if (_closed || _delegate == null) {
      debugPrint(
        'webview_all: Set a resource delegate before requesting a resource URL.',
      );
      return null;
    }
    if (path.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(path) ||
        path.split('/').any((segment) => segment == '.' || segment == '..')) {
      throw ArgumentError.value(
        path,
        'path',
        'Use a resource path without traversal or control characters.',
      );
    }
    return _baseUri.replace(
      pathSegments: <String>[
        ..._baseUri.pathSegments.take(max(0, _baseUri.pathSegments.length - 1)),
        ...(path.startsWith('/') ? path.substring(1) : path).split('/'),
      ],
    );
  }

  Future<void> update(WebViewResourceDelegate? delegate) {
    final timeout = delegate?.requestTimeout;
    if (timeout != null &&
        (timeout.inMilliseconds < 1 ||
            timeout.inMilliseconds > 2147483647 ||
            timeout.inMicroseconds % 1000 != 0)) {
      return Future<void>.error(
        ArgumentError.value(
          timeout,
          'requestTimeout',
          'Use a whole number of milliseconds between 1 and 2147483647.',
        ),
      );
    }
    if (_closed) {
      return Future<void>.error(
        StateError('The resource bridge has been closed.'),
      );
    }
    final update = _updates.catchError((Object _) {}).then((_) async {
      if (_closed) return;
      final previous = _delegate;
      _delegate = delegate;
      await _cancelAll();
      if (_closed) return;
      try {
        await Future.any<void>(<Future<void>>[
          Future<void>.sync(
            () => _configure(channelName, host, delegate != null),
          ),
          _closedSignal.future,
        ]);
      } catch (_) {
        if (_closed) return;
        if (!_closed) _delegate = previous;
        rethrow;
      }
    });
    _updates = update;
    return update;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _closedSignal.complete();
    _delegate = null;
    _channelFinalizer.detach(this);
    _channel.setMethodCallHandler(null);
    await _cancelAll();
  }

  Future<void> _cancelAll() async {
    final bodies = _requests.values.toList();
    _requests.clear();
    await Future.wait(bodies.map((body) => body.close()));
  }

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'closed') {
      await close();
      return null;
    }
    final arguments =
        (call.arguments as Map<Object?, Object?>?) ??
        const <Object?, Object?>{};
    final id = arguments['id'] as String?;
    if (id == null) throw const FormatException('Missing resource request ID.');
    switch (call.method) {
      case 'open':
        return _open(id, arguments);
      case 'read':
        final body = _requests[id];
        if (body == null) return null;
        if (body.reading) {
          throw StateError(
            'Concurrent reads of one resource are not supported.',
          );
        }
        body.reading = true;
        try {
          final count = ((arguments['length'] as int?) ?? 65536).clamp(
            1,
            65536,
          );
          final data = await body.read(count).timeout(requestTimeout);
          if (data == null) {
            _requests.remove(id);
            await body.close();
          }
          return data;
        } catch (error) {
          _requests.remove(id);
          await body.close();
          _log(error);
          throw PlatformException(
            code: 'resource_read_failed',
            message: 'Reading the application resource failed.',
          );
        } finally {
          body.reading = false;
        }
      case 'cancel':
        await _requests.remove(id)?.close();
        return null;
      default:
        throw MissingPluginException('Unknown resource method ${call.method}.');
    }
  }

  /// Handles a request from an alternate platform transport.
  Future<Object?> handleCall(MethodCall call) => _handleCall(call);

  Map<String, Object?> _emptyResponse(
    int status, [
    Map<String, String>? headers,
  ]) => <String, Object?>{
    'statusCode': status,
    'mimeType': 'text/plain',
    'headers': <String, String>{
      'content-length': '0',
      'cache-control': 'no-store',
      ...?headers,
    },
    'contentLength': 0,
    if (nativeBodies) 'bytes': Uint8List(0),
  };

  Future<Map<String, Object?>> _open(
    String id,
    Map<Object?, Object?> arguments,
  ) async {
    final delegate = _delegate;
    if (_closed || delegate == null) return _emptyResponse(404);
    final uri = Uri.tryParse(arguments['uri'] as String? ?? '');
    if (uri == null ||
        uri.scheme != _baseUri.scheme ||
        uri.host != _baseUri.host ||
        uri.port != _baseUri.port ||
        uri.hasPort != _baseUri.hasPort ||
        uri.userInfo.isNotEmpty ||
        !uri.path.startsWith(_baseUri.path)) {
      return _emptyResponse(403);
    }
    final method = (arguments['method'] as String? ?? 'GET').toUpperCase();
    if (method != 'GET' && method != 'HEAD') {
      return _emptyResponse(405, <String, String>{'allow': 'GET, HEAD'});
    }
    if (_requests.length >= 64 || _requests.containsKey(id)) {
      return _emptyResponse(503);
    }
    // A longer request deadline must not extend delegate/session cleanup.
    final body = _ResourceBody(_defaultRequestTimeout);
    _requests[id] = body;
    final headers = <String, String>{};
    for (final entry
        in ((arguments['headers'] as Map<Object?, Object?>?) ??
                const <Object?, Object?>{})
            .entries) {
      if (entry.key is String && entry.value is String) {
        headers[(entry.key! as String).toLowerCase()] = entry.value! as String;
      }
    }
    try {
      final request = WebViewResourceRequest(
        uri: uri,
        method: method,
        headers: headers,
        path: Uri.decodeComponent(
          '/${uri.path.substring(_baseUri.path.length)}',
        ),
      );
      final response = await Future.any<WebViewResourceResponse?>(
        <Future<WebViewResourceResponse?>>[
          Future<WebViewResourceResponse?>.sync(
            () => delegate.onRequest(request),
          ).then((response) async {
            if (body.closed && response?.stream != null) {
              await body.discardStream(response!.stream!);
            }
            return response;
          }),
          body.cancelled.future.then((_) => null),
        ],
      ).timeout(requestTimeout);
      if (body.closed || response == null) {
        if (response?.stream != null) {
          await body.discardStream(response!.stream!);
        }
        _requests.remove(id);
        await body.close();
        return _emptyResponse(404);
      }
      if (method != 'HEAD') body.unstartedStream = response.stream;
      _validateResponse(response);
      if (response.stream != null && !supportsStreaming && method != 'HEAD') {
        throw UnsupportedError(
          'Incremental resource streams are unavailable on this platform. Return WebViewResourceResponse.file or .bytes instead.',
        );
      }
      final responseHeaders = <String, String>{
        for (final entry in response.headers.entries)
          entry.key.toLowerCase(): entry.value,
      };
      responseHeaders.putIfAbsent('content-type', () => response.mimeType);
      // Responses may contain private files; caching is opt-in.
      responseHeaders.putIfAbsent('cache-control', () => 'no-store');
      var status = response.statusCode;
      int? length = response.contentLength;
      if (response.stream != null &&
          responseHeaders.containsKey('content-length')) {
        final declaredLength = int.tryParse(responseHeaders['content-length']!);
        if (declaredLength == null ||
            declaredLength < 0 ||
            (length != null && length != declaredLength)) {
          throw ArgumentError(
            'Resource Content-Length must match its declared stream length.',
          );
        }
        length = declaredLength;
      }
      var offset = 0;
      if (response.filePath != null) {
        body.file = await ResourceFile.open(response.filePath!);
        length = body.file!.length;
      } else if (response.bytes != null) {
        body.bytes = response.bytes;
      }
      if (body.closed) {
        await body.file?.close();
        return _emptyResponse(404);
      }
      if (status == 200 && response.stream == null) {
        responseHeaders['accept-ranges'] = 'bytes';
        final ifRange = headers['if-range'];
        final mayRange =
            ifRange == null ||
            (ifRange == responseHeaders['etag'] && !ifRange.startsWith('W/')) ||
            ifRange == responseHeaders['last-modified'];
        final range = method == 'GET' && mayRange
            ? _parseRange(headers['range'], length!)
            : null;
        if (range != null) {
          if (range.$1 < 0) {
            _requests.remove(id);
            await body.close();
            return _emptyResponse(416, <String, String>{
              'content-range': 'bytes */$length',
              'accept-ranges': 'bytes',
            });
          }
          offset = range.$1;
          final total = length;
          length = range.$2 - offset + 1;
          status = 206;
          responseHeaders['content-range'] = 'bytes $offset-${range.$2}/$total';
        }
      }
      if (length != null) responseHeaders['content-length'] = '$length';
      if (status == 204 || status == 205) {
        length = 0;
        responseHeaders['content-length'] = '0';
      }
      body.remaining = length;
      body.offset = offset;
      if (method == 'HEAD' || length == 0) {
        _requests.remove(id);
        await body.close();
      } else if (nativeBodies) {
        _requests.remove(id);
        await body.close();
      } else if (body.file != null) {
        await body.file!.seek(offset);
      } else if (response.stream != null) {
        body.startStream(response.stream!);
      }
      return <String, Object?>{
        'statusCode': status,
        'mimeType': response.mimeType,
        'headers': responseHeaders,
        'contentLength': length ?? -1,
        if (nativeBodies &&
            method != 'HEAD' &&
            length != 0 &&
            response.filePath != null)
          'filePath': response.filePath,
        if (nativeBodies &&
            method != 'HEAD' &&
            length != 0 &&
            response.filePath != null)
          'offset': offset,
        if (nativeBodies && (method == 'HEAD' || length == 0))
          'bytes': Uint8List(0),
        if (nativeBodies &&
            method != 'HEAD' &&
            length != 0 &&
            response.bytes != null)
          'bytes': Uint8List.sublistView(
            response.bytes!,
            offset,
            offset + length!,
          ),
      };
    } catch (error) {
      _requests.remove(id);
      await body.close();
      _log(error);
      return _emptyResponse(
        error is TimeoutException
            ? 504
            : error is UnsupportedError
            ? 501
            : 500,
      );
    }
  }

  void _validateResponse(WebViewResourceResponse response) {
    if (!((response.statusCode >= 200 && response.statusCode <= 299) ||
        (response.statusCode >= 400 && response.statusCode <= 599))) {
      throw ArgumentError('Resource status must be 200–299 or 400–599.');
    }
    if (response.mimeType.isEmpty ||
        RegExp(r'[\r\n\x00]').hasMatch(response.mimeType)) {
      throw ArgumentError('Invalid resource MIME type.');
    }
    if (response.contentLength != null && response.contentLength! < 0) {
      throw ArgumentError('Resource content length must not be negative.');
    }
    final token = RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$");
    for (final entry in response.headers.entries) {
      if (!token.hasMatch(entry.key) ||
          RegExp(r'[\r\n\x00]').hasMatch(entry.value)) {
        throw ArgumentError('Invalid resource response header.');
      }
      if (entry.key.toLowerCase() == 'transfer-encoding') {
        throw ArgumentError('Resource body framing is managed by the plugin.');
      }
      if (entry.key.toLowerCase() == 'content-type' &&
          entry.value.split(';').first.trim().toLowerCase() !=
              response.mimeType.toLowerCase()) {
        throw ArgumentError('Resource Content-Type must match mimeType.');
      }
    }
  }

  static void _log(Object error) => debugPrint(
    'webview_all: Application resource failed: ${error.toString().replaceAll(RegExp(r"[\r\n]+"), " ")}',
  );
}

// Null means ignore an unsupported/malformed range; (-1, -1) means 416.
(int, int)? _parseRange(String? value, int length) {
  if (value == null) return null;
  final match = RegExp(
    r'^bytes=(\d*)-(\d*)$',
    caseSensitive: false,
  ).firstMatch(value.trim());
  if (match == null || (match[1]!.isEmpty && match[2]!.isEmpty)) return null;
  if (match[1]!.isEmpty) {
    final suffix = int.tryParse(match[2]!);
    if (suffix == null) return null;
    if (suffix == 0 || length == 0) return (-1, -1);
    return (max(0, length - suffix), length - 1);
  }
  final start = int.tryParse(match[1]!);
  final end = match[2]!.isEmpty ? length - 1 : int.tryParse(match[2]!);
  if (start == null || end == null) return null;
  if (start >= length || start > end) return (-1, -1);
  return (start, min(end, length - 1));
}

class _ResourceBody {
  _ResourceBody(this.timeout);

  final Duration timeout;
  ResourceFile? file;
  Uint8List? bytes;
  StreamIterator<List<int>>? iterator;
  Stream<List<int>>? unstartedStream;
  Stream<List<int>>? discardedStream;
  Future<bool>? prefetched;
  Object? streamError;
  StackTrace? streamStack;
  List<int>? chunk;
  int chunkOffset = 0;
  int offset = 0;
  int? remaining;
  bool reading = false;
  bool closed = false;
  final Completer<void> cancelled = Completer<void>();
  Future<void> fileRead = Future<void>.value();

  Future<void> discardStream(Stream<List<int>> stream) async {
    if (identical(discardedStream, stream)) return;
    discardedStream = stream;
    try {
      await _cancelUnstartedStream(stream).timeout(timeout);
    } catch (error) {
      WebViewResourceBridge._log(error);
    }
  }

  void startStream(Stream<List<int>> stream) {
    unstartedStream = null;
    iterator = StreamIterator<List<int>>(stream);
    // Subscribe before the first native read so cancellation reaches producers
    // even if the engine has not requested a chunk yet. Only one event is held.
    prefetched = iterator!.moveNext().then(
      (available) => available,
      onError: (Object error, StackTrace stack) {
        streamError = error;
        streamStack = stack;
        return false;
      },
    );
  }

  Future<Uint8List?> read(int count) async {
    if (closed || remaining == 0) return null;
    count = min(count, remaining ?? count);
    Uint8List data;
    if (file != null) {
      final finished = Completer<void>();
      fileRead = finished.future;
      try {
        data = await file!.read(count);
      } finally {
        finished.complete();
      }
    } else if (bytes != null) {
      data = Uint8List.sublistView(
        bytes!,
        offset,
        min(bytes!.length, offset + count),
      );
      offset += data.length;
    } else {
      while (chunk == null || chunkOffset == chunk!.length) {
        final next = prefetched;
        prefetched = null;
        if (closed || !(await (next ?? iterator!.moveNext()))) {
          if (streamError != null && !closed) {
            Error.throwWithStackTrace(streamError!, streamStack!);
          }
          if (remaining != null && remaining! > 0 && !closed) {
            throw StateError(
              'Resource stream ended before its declared length.',
            );
          }
          return null;
        }
        chunk = iterator!.current;
        chunkOffset = 0;
      }
      data = Uint8List.fromList(
        chunk!.sublist(chunkOffset, min(chunk!.length, chunkOffset + count)),
      );
      chunkOffset += data.length;
    }
    if (closed) return null;
    if (data.isEmpty) {
      if (remaining != null && remaining! > 0) {
        throw StateError('Resource file ended before its declared length.');
      }
      return null;
    }
    if (remaining != null) remaining = remaining! - data.length;
    return data;
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    cancelled.complete();
    try {
      await iterator?.cancel().timeout(timeout);
      if (unstartedStream != null) {
        await discardStream(unstartedStream!);
      }
    } catch (error) {
      WebViewResourceBridge._log(error);
    } finally {
      // A pending file read must finish before its handle is closed.
      if (file != null) {
        try {
          await fileRead;
          await file!.close();
        } catch (_) {
          // A cancellation can race with file preparation or native disposal.
        }
      }
      bytes = null;
      chunk = null;
      unstartedStream = null;
    }
  }
}

Future<void> _cancelUnstartedStream(Stream<List<int>> stream) async {
  final subscription = stream.listen(
    (_) {},
    onError: (Object _, StackTrace __) {},
  );
  await subscription.cancel();
}

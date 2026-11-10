import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'platform_webview_controller.dart';
import 'types/types.dart';
import 'types/javascript_json.dart';

/// Shared, bounded Promise transport. Native adapters provide world-aware
/// channels and evaluation; document tokens prevent replies entering a new page.
class WebViewJavaScriptBridge {
  WebViewJavaScriptBridge(PlatformWebViewController controller)
    : _controller = WeakReference(controller);

  final WeakReference<PlatformWebViewController> _controller;
  final Map<WebViewJavaScriptWorld, _World> _worlds = {};
  final Map<String, _PendingCall> _pending = {};
  Future<void> _updates = Future<void>.value();
  bool _closed = false;
  static const int _maxMessageBytes = 1024 * 1024;

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _updates.then((_) => operation());
    _updates = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> add(
    WebViewJavaScriptHandlerParams params,
  ) => _serialize(() async {
    if (params.name.isEmpty || params.name.length > 256) {
      throw ArgumentError.value(params.name, 'name', 'Use 1–256 characters.');
    }
    if (params.timeout <= Duration.zero ||
        params.timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        params.timeout,
        'timeout',
        'Use a timeout up to five minutes.',
      );
    }
    final controller = _controller.target;
    if (_closed || controller == null) return false;
    final WebViewJavaScriptCapabilities caps;
    try {
      caps = await controller.getJavaScriptCapabilities(world: params.world);
    } catch (error) {
      debugPrint(
        'webview_all: JavaScript handler registration was skipped: $error',
      );
      return false;
    }
    if (_closed) return false;
    final policy = params.accessPolicy;
    String? reason;
    if (!caps.supportsPromiseHandlers) {
      reason = caps.limitation ?? 'Promise handlers are unavailable.';
    } else if (!caps.supportsWorld(params.world)) {
      reason = 'The requested isolated JavaScript world is unavailable.';
    } else if (policy.allowedOrigins != null && !caps.supportsTrustedOrigins) {
      reason =
          'The engine cannot verify security origins. Use unrestricted access only for content you control.';
    } else if (policy.mainFrameOnly && !caps.supportsTrustedFrameInformation) {
      reason = 'The engine cannot verify the sending frame.';
    }
    if (reason != null) {
      debugPrint(
        'webview_all: JavaScript handler "${params.name}" was skipped. $reason',
      );
      return false;
    }
    var state = _worlds[params.world];
    final replacing = state != null;
    if (state == null) {
      state = _World(params.world);
      state.handlers[params.name] = params;
      _worlds[params.world] = state;
      try {
        await controller.addJavaScriptChannelInWorld(
          JavaScriptChannelParams(
            name: state.channel,
            onMessageReceived: _channelReceiver(
              WeakReference(this),
              WeakReference(state),
            ),
          ),
          params.world,
        );
        if (_closed) throw StateError('The WebView is closed.');
        state.script = await controller.installJavaScriptBridgeScript(
          WebViewUserScript(source: _bootstrap(state), world: params.world),
        );
        if (state.script == null) {
          throw UnsupportedError('Bridge injection is unavailable.');
        }
        if (_closed) throw StateError('The WebView is closed.');
      } catch (error) {
        _worlds.remove(params.world);
        try {
          await controller.removeJavaScriptChannel(state.channel);
        } catch (_) {}
        if (state.script != null) {
          try {
            await controller.removeUserScript(state.script!);
          } catch (_) {}
        }
        debugPrint(
          'webview_all: JavaScript handler registration was skipped: $error',
        );
        return false;
      }
      if (caps.limitation != null) {
        debugPrint('webview_all: ${caps.limitation}');
      }
    }
    if (replacing) {
      _cancelWhere(
        (call) => call.state == state && call.handler.name == params.name,
      );
    }
    state.handlers[params.name] = params;
    if (caps.requiresControlledContent) {
      debugPrint(
        'webview_all: JavaScript handlers on Web require same-origin or plugin-controlled HTML. Cross-origin URLs cannot be injected.',
      );
    }
    return true;
  });

  // Keep the native callback outside add's async closure context: other
  // closures there capture the registration and its user-owned handler.
  static void Function(JavaScriptMessage) _channelReceiver(
    WeakReference<WebViewJavaScriptBridge> bridge,
    WeakReference<_World> state,
  ) => (message) {
    final target = bridge.target;
    final currentState = state.target;
    if (target != null && currentState != null) {
      unawaited(target._receive(currentState, message));
    }
  };

  Future<void> remove(String name, WebViewJavaScriptWorld world) =>
      _serialize(() async {
        _worlds[world]?.handlers.remove(name);
        _cancelWhere(
          (call) => call.state.world == world && call.handler.name == name,
        );
      });

  Future<void> removeAll() => _serialize(() async {
    for (final world in _worlds.values) {
      world.handlers.clear();
    }
    _cancelWhere((_) => true);
  });

  /// Navigation invalidates pending calls, but may leave the document alive
  /// when a provisional load fails. Its token is retired by pagehide or the
  /// next document's handshake, rather than by a navigation notification.
  void documentChanged() {
    _cancelWhere((_) => true);
  }

  void close() {
    _closed = true;
    documentChanged();
    for (final state in _worlds.values) {
      state.handlers.clear();
    }
    _worlds.clear();
  }

  void _cancelWhere(bool Function(_PendingCall) predicate) {
    for (final call in _pending.values.toList()) {
      if (predicate(call) && !call.cancelled.isCompleted) {
        call.cancelled.complete();
      }
    }
  }

  Future<void> _receive(_World state, JavaScriptMessage message) async {
    if (_closed ||
        message.isMainFrame == false ||
        !identical(_worlds[state.world], state)) {
      return;
    }
    if (message.message.length > _maxMessageBytes ||
        utf8.encode(message.message).length > _maxMessageBytes) {
      debugPrint(
        'webview_all: Ignored an oversized JavaScript bridge message.',
      );
      return;
    }
    try {
      final value = jsonDecode(message.message);
      if (value is! Map<String, dynamic> || value['v'] != 1) return;
      final document = value['document'];
      if (document is! String || document.length > 128) return;
      if (value['type'] == 'hello') {
        if (state.document != document) {
          _cancelWhere((call) => call.state == state);
          state.document = document;
        }
        await _send(state, document, {'type': 'ready'});
        return;
      }
      if (state.document != document) return;
      if (value['type'] == 'bye') {
        state.document = null;
        _cancelWhere((call) => call.state == state);
        return;
      }
      if (value['type'] != 'call') return;
      final id = value['id'];
      final name = value['name'];
      if (id is! String || id.length > 128 || name is! String) return;
      final key = '${state.channel}/$document/$id';
      if (_pending.containsKey(key)) return;
      final handler = state.handlers[name];
      if (handler == null) {
        await _error(
          state,
          document,
          id,
          'handler_not_found',
          'No handler is registered with this name.',
        );
        return;
      }
      if (!handler.accessPolicy.allows(
        origin: message.sourceOrigin,
        isMainFrame: message.isMainFrame,
      )) {
        debugPrint(
          'webview_all: JavaScript handler "$name" rejected a caller with an unverified or disallowed origin/frame.',
        );
        await _error(
          state,
          document,
          id,
          'forbidden',
          'The caller is not allowed.',
        );
        return;
      }
      if (_pending.length >= 128) {
        await _error(
          state,
          document,
          id,
          'busy',
          'Too many JavaScript calls are pending.',
        );
        return;
      }
      final args = value['arguments'];
      if (args is! List<Object?>) return;
      final arguments = _copyJson(args) as List<Object?>;
      final pending = _PendingCall(state, handler);
      _pending[key] = pending;
      try {
        final result = await Future.any<Object?>([
          Future<Object?>.sync(
            () => handler.onCall(
              WebViewJavaScriptCall(
                arguments: arguments,
                world: state.world,
                cancelled: pending.cancelled.future,
                sourceUrl: message.sourceUrl,
                sourceOrigin: message.sourceOrigin,
                isMainFrame: message.isMainFrame,
              ),
            ),
          ),
          pending.cancelled.future.then<Object?>((_) => throw const _Aborted()),
        ]).timeout(handler.timeout);
        if (_closed || state.document != document) return;
        if (state.handlers[name] != handler) {
          await _error(
            state,
            document,
            id,
            'aborted',
            'The JavaScript handler was replaced.',
          );
          return;
        }
        Object? copied;
        try {
          copied = _copyJson(result);
          if (utf8.encode(jsonEncode(copied)).length > _maxMessageBytes) {
            throw const FormatException('Oversized result.');
          }
        } catch (_) {
          await _error(
            state,
            document,
            id,
            'serialization_error',
            'The Dart result must contain bounded JSON-compatible values.',
          );
          return;
        }
        await _send(state, document, {
          'type': 'result',
          'id': id,
          'value': copied,
        });
      } on _Aborted {
        await _error(
          state,
          document,
          id,
          'aborted',
          'The JavaScript call was cancelled.',
        );
      } on TimeoutException {
        if (!pending.cancelled.isCompleted) pending.cancelled.complete();
        await _error(
          state,
          document,
          id,
          'timeout',
          'The Dart handler timed out.',
        );
      } catch (_) {
        await _error(
          state,
          document,
          id,
          'handler_error',
          'The Dart handler failed.',
        );
      } finally {
        _pending.remove(key);
      }
    } catch (error) {
      debugPrint(
        'webview_all: Ignored an invalid JavaScript bridge message: ${error.runtimeType}.',
      );
    }
  }

  Future<void> _error(
    _World state,
    String document,
    String id,
    String code,
    String message,
  ) => _send(state, document, {
    'type': 'error',
    'id': id,
    'code': code,
    'message': message,
  });

  Future<void> _send(
    _World state,
    String document,
    Map<String, Object?> value,
  ) async {
    final controller = _controller.target;
    if (_closed || controller == null || state.document != document) return;
    try {
      await controller.runJavaScriptInWorld(
        'globalThis[${jsonEncode(state.receiver)}]?.(${jsonEncode(document)}, JSON.parse(${jsonEncode(jsonEncode(value))}));',
        state.world,
      );
    } catch (_) {
      // The original document can disappear while a native reply is in flight.
    }
  }

  static Object? _copyJson(Object? value) => freezeJavaScriptJsonValue(value);

  String _bootstrap(_World state) =>
      '''
(function() {
  'use strict';
  const root = globalThis;
  const receiver = ${jsonEncode(state.receiver)};
  if (root[receiver]) return;
  if ('webviewAll' in root) {
    console.warn('webview_all: window.webviewAll is already in use; Promise bridge injection was skipped.');
    return;
  }
  const stringify = JSON.stringify.bind(JSON);
  const encoder = new TextEncoder();
  const pending = new Map();
  let documentId, sequence = 0, ready, resolveReady, rejectReady, handshakeTimer;
  function error(code, message) { const e = new Error(message); e.code = code; return e; }
  function send(value) {
    value.v = 1; value.document = documentId;
    const text = stringify(value);
    if (text.length > $_maxMessageBytes || encoder.encode(text).byteLength > $_maxMessageBytes) throw error('serialization_error', 'The JavaScript message is too large.');
    const channel = root[${jsonEncode(state.channel)}];
    if (!channel || typeof channel.postMessage !== 'function') return false;
    channel.postMessage(text); return true;
  }
  function validate(value, seen, depth) {
    if (depth > 64) throw error('serialization_error', 'JSON nesting is too deep.');
    if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
    if (typeof value === 'number' && Number.isFinite(value)) return;
    if (typeof value !== 'object' || seen.has(value)) throw error('serialization_error', 'Only non-cyclic JSON values are accepted.');
    const proto = Object.getPrototypeOf(value);
    if (!Array.isArray(value) && proto !== Object.prototype && proto !== null) throw error('serialization_error', 'Only JSON objects and arrays are accepted.');
    seen.add(value);
    if (Object.getOwnPropertySymbols(value).length) throw error('serialization_error', 'JSON object keys must be strings.');
    if (Array.isArray(value)) {
      for (let i = 0; i < value.length; i++) validate(value[i], seen, depth + 1);
    } else {
      for (const key of Object.keys(value)) validate(value[key], seen, depth + 1);
    }
    seen.delete(value);
  }
  function abort() {
    clearTimeout(handshakeTimer);
    rejectReady(error('aborted', 'The document was replaced.'));
    for (const call of pending.values()) { clearTimeout(call.timer); call.reject(error('aborted', 'The document was replaced.')); }
    pending.clear();
    try { send({type: 'bye'}); } catch (_) {}
  }
  function connect() {
    documentId = Date.now().toString(36) + ':' + Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2);
    ready = new Promise((resolve, reject) => { resolveReady = resolve; rejectReady = reject; });
    ready.catch(() => {});
    const deadline = Date.now() + 10000;
    function hello() {
      try {
        if (send({type: 'hello'})) {
          handshakeTimer = setTimeout(() => rejectReady(error('timeout', 'The JavaScript bridge did not become ready.')), 10000);
          return;
        }
      } catch (_) {}
      if (Date.now() >= deadline) { rejectReady(error('unsupported', 'The native JavaScript channel is unavailable.')); return; }
      handshakeTimer = setTimeout(hello, 20);
    }
    hello();
  }
  Object.defineProperty(root, receiver, {value: function(document, message) {
    if (document !== documentId) return;
    if (message.type === 'ready') {
      clearTimeout(handshakeTimer); resolveReady();
      root.dispatchEvent(new Event('webviewAllReady')); return;
    }
    const call = pending.get(message.id);
    if (!call) return;
    pending.delete(message.id); clearTimeout(call.timer);
    if (message.type === 'result') call.resolve(message.value);
    else call.reject(error(message.code, message.message));
  }});
  const api = {
    get ready() { return ready; },
    async callHandler(name, ...args) {
      validate(args, new Set(), 0);
      if (typeof name !== 'string' || !name || name.length > 256) throw error('invalid_argument', 'Invalid handler name.');
      await ready;
      if (pending.size >= 128) throw error('busy', 'Too many JavaScript calls are pending.');
      const id = String(++sequence);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => { pending.delete(id); reject(error('timeout', 'The JavaScript call timed out.')); }, 300000);
        pending.set(id, {resolve, reject, timer});
        try { if (!send({type: 'call', id, name, arguments: args})) throw error('unsupported', 'The native channel is unavailable.'); }
        catch (e) { clearTimeout(timer); pending.delete(id); reject(e); }
      });
    }
  };
  Object.defineProperty(root, 'webviewAll', {value: Object.freeze(api)});
  const onPageShow = event => { if (event.persisted) connect(); };
  function restoreLifecycle() {
    root.addEventListener('pagehide', abort);
    root.addEventListener('pageshow', onPageShow);
  }
  restoreLifecycle();
  // document.open removes listeners but retains globals and observers.
  if (typeof MutationObserver !== 'undefined') {
    new MutationObserver(restoreLifecycle).observe(document, {childList: true});
  }
  connect();
})();
''';
}

class _World {
  _World(this.world) {
    final random = Random.secure();
    final token = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    channel = 'webviewAllRpc_$token';
    receiver = '__webviewAllReply_$token';
  }
  final WebViewJavaScriptWorld world;
  late final String channel;
  late final String receiver;
  final Map<String, WebViewJavaScriptHandlerParams> handlers = {};
  String? script;
  String? document;
}

class _PendingCall {
  _PendingCall(this.state, this.handler);
  final _World state;
  final WebViewJavaScriptHandlerParams handler;
  final Completer<void> cancelled = Completer<void>();
}

class _Aborted implements Exception {
  const _Aborted();
}

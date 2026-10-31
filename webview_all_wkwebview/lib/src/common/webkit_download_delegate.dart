import 'dart:async';

import 'package:flutter/services.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

/// Controller-owned bridge. Accepted transfers retain their original delegate.
class WebKitDownloadDelegateBridge {
  WebKitDownloadDelegateBridge(this.identifier, this._delegate)
    : _channel = MethodChannel(
        'com.abandoft.webview_all_wkwebview/downloads/$identifier',
      );

  static const MethodChannel _registration = MethodChannel(
    'com.abandoft.webview_all_wkwebview/downloads',
  );
  final int identifier;
  WebViewDownloadDelegate? _delegate;
  final MethodChannel _channel;
  final Map<String, WebViewDownloadDelegate> _owners = {};
  final Map<String, Completer<void>> _pending = {};
  int _generation = 0;
  bool _closed = false;
  bool _closing = false;
  Future<void>? _closeFuture;

  Future<void> enable() async {
    final weak = WeakReference<WebKitDownloadDelegateBridge>(this);
    _channel.setMethodCallHandler(
      (call) =>
          weak.target?._handle(call) ??
          Future<Object?>.value(<String, Object?>{'action': 'cancel'}),
    );
    try {
      await update(_delegate);
    } catch (_) {
      _closed = true;
      _channel.setMethodCallHandler(null);
      rethrow;
    }
  }

  Future<void> update(WebViewDownloadDelegate? delegate) async {
    if (_closed || _closing) throw StateError('The download bridge is closed.');
    final previous = _delegate;
    final previousGeneration = _generation;
    final generation = ++_generation;
    _cancelPending();
    _delegate = delegate;
    try {
      await _registration.invokeMethod<void>('configure', <String, Object?>{
        'webViewId': identifier,
        'enabled': delegate != null,
        'generation': generation,
      });
    } catch (_) {
      if (_generation == generation) {
        _delegate = previous;
        _generation = previousGeneration;
      }
      rethrow;
    }
  }

  Future<Object?> _handle(MethodCall call) async {
    final args = Map<Object?, Object?>.from(call.arguments as Map);
    final id = args['id']! as String;
    if (_closed || (_closing && call.method == 'request')) {
      return <String, Object?>{'action': 'cancel'};
    }
    if (_closing && call.method == 'progress') return null;
    switch (call.method) {
      case 'request':
        final delegate = _delegate;
        final generation = _generation;
        if (delegate == null ||
            (args['generation'] != null && args['generation'] != generation) ||
            _owners.containsKey(id)) {
          return <String, Object?>{'action': 'cancel'};
        }
        _owners[id] = delegate;
        final cancellation = Completer<void>();
        _pending[id] = cancellation;
        try {
          final supported = (args['supportedActions']! as List<Object?>)
              .map(
                (value) =>
                    WebViewDownloadAction.values.byName(value! as String),
              )
              .toSet();
          final length = args['contentLength'] as int?;
          final request = WebViewDownloadRequest(
            id: id,
            url: args['url']! as String,
            suggestedFilename: args['suggestedFilename'] as String?,
            mimeType: args['mimeType'] as String?,
            contentDisposition: args['contentDisposition'] as String?,
            contentLength: length != null && length >= 0 ? length : null,
            supportedActions: supported,
          );
          final decision = await delegate.decide(
            request,
            cancelled: cancellation.future,
          );
          return _closed || _closing || generation != _generation
              ? <String, Object?>{'action': 'cancel'}
              : decision.toMap();
        } catch (error) {
          if (_closing || _closed || generation != _generation) {
            return <String, Object?>{'action': 'cancel'};
          }
          return <String, Object?>{
            'action': 'cancel',
            'errorCode': 'download_decision_failed',
            'description': error.toString(),
          };
        } finally {
          _pending.remove(id);
          if (!cancellation.isCompleted) cancellation.complete();
        }
      case 'progress':
        _owners[id]?.notifyProgress(
          WebViewDownloadProgress(
            id: id,
            bytesReceived: args['bytesReceived']! as int,
            totalBytes: args['totalBytes'] as int?,
          ),
        );
      case 'result':
        final owner = _owners.remove(id);
        final pending = _pending[id];
        if (pending != null && !pending.isCompleted) pending.complete();
        owner?.notifyResult(
          WebViewDownloadResult(
            id: id,
            status: WebViewDownloadStatus.values.byName(
              args['status']! as String,
            ),
            path: args['path'] as String?,
            errorCode: args['errorCode'] as String?,
            description: args['description'] as String?,
          ),
        );
      default:
        throw MissingPluginException(
          'Unknown download callback: ${call.method}',
        );
    }
    return null;
  }

  void _cancelPending() {
    for (final cancellation in _pending.values) {
      if (!cancellation.isCompleted) cancellation.complete();
    }
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closing = true;
    _cancelPending();
    try {
      await _registration.invokeMethod<void>('configure', <String, Object?>{
        'webViewId': identifier,
        'enabled': false,
        'dispose': true,
      });
    } finally {
      _closed = true;
      for (final entry in _owners.entries) {
        entry.value.notifyResult(
          WebViewDownloadResult(
            id: entry.key,
            status: WebViewDownloadStatus.cancelled,
          ),
        );
      }
      _owners.clear();
      _channel.setMethodCallHandler(null);
    }
  }
}

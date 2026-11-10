import 'dart:async';
import 'package:flutter/foundation.dart';

/// Native print-flow state, not confirmation that paper was physically printed.
enum WebViewPrintState {
  presented,
  queued,
  started,
  blocked,
  completed,
  cancelled,
  failed,
  cancelledOrFailed,
  unknown,

  /// The browser received a print request but cannot confirm showing its UI.
  requested,
}

/// An explicitly requested system print flow. Support for observing and
/// cancelling jobs depends on the engine; opening a dialog is not completion.
class WebViewPrintJob {
  WebViewPrintJob({
    required this.initialState,
    Future<WebViewPrintState> Function()? readState,
    Future<bool> Function()? cancel,
    Future<void> Function()? release,
  }) : _readState = readState,
       _cancel = cancel,
       _release = release;
  final WebViewPrintState initialState;
  final Future<WebViewPrintState> Function()? _readState;
  final Future<bool> Function()? _cancel;
  final Future<void> Function()? _release;
  bool _disposed = false;
  Future<void>? _disposeFuture;
  bool get canQueryState => _readState != null;
  bool get canCancel => _cancel != null;
  Future<WebViewPrintState> getState() async {
    if (_disposed) return WebViewPrintState.unknown;
    if (_readState == null) {
      debugPrint(
        'webview_all: this system print flow cannot report subsequent job state. Opening the panel does not confirm printing.',
      );
      return initialState;
    }
    try {
      return await _readState().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('webview_all: reading print state failed: $error');
      return WebViewPrintState.unknown;
    }
  }

  Future<bool> cancel() async {
    if (_disposed) return false;
    if (_cancel == null) {
      debugPrint(
        'webview_all: programmatic cancellation is unavailable for this system print flow; use its native controls.',
      );
      return false;
    }
    try {
      return await _cancel().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('webview_all: cancelling printing failed: $error');
      return false;
    }
  }

  /// Releases the handle without cancelling a job already owned by the OS.
  Future<void> dispose() => _disposeFuture ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    try {
      await _release?.call().timeout(const Duration(seconds: 10));
    } catch (error) {
      debugPrint('webview_all: releasing print handle failed: $error');
    }
  }
}

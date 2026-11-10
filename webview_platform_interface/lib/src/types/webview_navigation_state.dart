import 'dart:async';

import 'package:flutter/foundation.dart';

/// An engine-owned back/forward state, valid in this Flutter engine and store.
///
/// This is an in-memory native snapshot, not a list of URLs to reload. It does
/// not guarantee restoration of cookies, page JavaScript, form data or POST
/// bodies. Dispose it when no longer needed. Engine shutdown invalidates it.
class WebViewNavigationState {
  WebViewNavigationState({
    required this.platform,
    required this.identifier,
    required Future<void> Function() onDispose,
  }) : _disposal = _NavigationStateDisposal(onDispose) {
    _finalizer.attach(this, _disposal, detach: this);
  }

  final String platform;
  final String identifier;
  final _NavigationStateDisposal _disposal;
  bool get isDisposed => _disposal.future != null;

  /// Native snapshots cannot be serialized or transferred between engines.
  bool get canPersist => false;

  static final _finalizer = Finalizer<_NavigationStateDisposal>((disposal) {
    unawaited(disposal.close());
  });

  Future<void> dispose() {
    _finalizer.detach(this);
    return _disposal.close();
  }
}

class _NavigationStateDisposal {
  _NavigationStateDisposal(this.callback);
  final Future<void> Function() callback;
  Future<void>? future;
  Future<void> close() => future ??= Future<void>.sync(callback).catchError((
    Object error,
  ) {
    debugPrint('webview_all: releasing the navigation snapshot failed: $error');
  });
}

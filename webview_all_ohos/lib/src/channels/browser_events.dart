import 'dart:async';

import 'package:flutter/foundation.dart';

/// Native browser lifecycle callbacks, independent of optional navigation hooks.
class OhosBrowserEvents {
  static final _listeners =
      <int, Future<void> Function(Map<Object?, Object?>)>{};
  static final _owners = <int, WeakReference<Object>>{};

  static void observe(
    int identifier,
    Object owner,
    Future<void> Function(Map<Object?, Object?>) listener,
  ) {
    for (final key in _owners.keys.toList()) {
      if (_owners[key]?.target == null) {
        remove(key);
      }
    }
    _owners[identifier] = WeakReference(owner);
    _listeners[identifier] = listener;
  }

  static void remove(int identifier) {
    _listeners.remove(identifier);
    _owners.remove(identifier);
  }

  static Future<void> dispatch(
    int identifier,
    Map<Object?, Object?> event,
  ) async {
    try {
      if (_owners[identifier]?.target == null) {
        remove(identifier);
        return;
      }
      await _listeners[identifier]?.call(event);
    } catch (error) {
      debugPrint('webview_all_ohos: browser event callback failed: $error');
    }
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';

/// A native request to open another browsing window.
///
/// Use [createController], configure the child, then await [attach] before
/// presenting it. Some engines require this factory's related configuration.
/// Returning from the delegate without attaching a controller rejects the
/// request. The application owns the supplied controller even if attachment
/// fails, and must release controllers it no longer needs.
class WebViewNewWindowRequest<T> {
  WebViewNewWindowRequest({
    this.url,
    this.isUserGesture,
    this.isDialog,
    Future<T?> Function()? onCreateController,
    required Future<bool> Function(T controller) onAttach,
    required Future<void> Function() onReject,
  }) : _onCreateController = onCreateController,
       _onAttach = onAttach,
       _onReject = onReject;

  /// The initial destination, when the engine exposes it before attachment.
  /// Android does not supply this URL; POST navigation may also bypass its
  /// navigation-policy callback. Enable delegation for trusted opener pages.
  final Uri? url;
  final bool? isUserGesture;
  final bool? isDialog;
  final Future<T?> Function()? _onCreateController;
  Future<T?>? _creation;
  final Future<bool> Function(T) _onAttach;
  final Future<void> Function() _onReject;
  bool _resolved = false;

  /// Creates the controller associated with this native window request.
  ///
  /// Repeated calls return the same controller. This does not accept the popup;
  /// configure callbacks and scripts before calling [attach]. The application
  /// owns the returned controller, including when the request subsequently
  /// expires or attachment fails, and must release it when no longer needed.
  /// Returns null if unavailable, expired or creation fails.
  Future<T?> createController() {
    if (_creation != null) return _creation!;
    if (_resolved) return Future<T?>.value();
    return _creation = Future<T?>.sync(() async {
      final create = _onCreateController;
      if (create == null) {
        debugPrint(
          'webview_all: this window request has no controller factory.',
        );
        return null;
      }
      try {
        return await create();
      } catch (error) {
        debugPrint('webview_all: creating the child controller failed: $error');
        return null;
      }
    });
  }

  /// Hands a fresh controller to the native engine without reloading its URL.
  /// The controller must share the opener's native environment and profile.
  /// Returns false for expired requests, reused or incompatible controllers.
  Future<bool> attach(T controller) async {
    if (_resolved) return false;
    _resolved = true;
    try {
      return await _onAttach(controller);
    } catch (error) {
      debugPrint('webview_all: native child-window attachment failed: $error');
      try {
        await _onReject();
      } catch (_) {}
      return false;
    }
  }

  Future<void> reject() async {
    if (_resolved) return;
    _resolved = true;
    try {
      await _onReject();
    } catch (error) {
      debugPrint('webview_all: rejecting the child window failed: $error');
    }
  }

  /// Adapts the controller type for a higher-level WebView API.
  WebViewNewWindowRequest<U> map<U>(
    T Function(U) convert, {
    U Function(T)? fromPlatform,
  }) => WebViewNewWindowRequest<U>(
    url: url,
    isUserGesture: isUserGesture,
    isDialog: isDialog,
    onCreateController: fromPlatform == null
        ? null
        : () async {
            final controller = await createController();
            return controller == null ? null : fromPlatform(controller);
          },
    onAttach: (controller) => attach(convert(controller)),
    onReject: reject,
  );
}

/// Bounds native deferrals and rejects abandoned or failed delegate requests.
Future<void> dispatchWebViewNewWindowRequest<T>(
  FutureOr<void> Function(WebViewNewWindowRequest<T>)? delegate,
  WebViewNewWindowRequest<T> request,
) async {
  try {
    if (delegate != null) {
      await Future<void>.sync(
        () => delegate(request),
      ).timeout(const Duration(seconds: 20));
    }
  } catch (error) {
    debugPrint(
      'webview_all: the new-window delegate failed or timed out: $error',
    );
  } finally {
    if (!request._resolved) await request.reject();
  }
}

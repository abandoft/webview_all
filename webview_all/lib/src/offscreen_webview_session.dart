import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'webview_controller.dart';

/// Owns a [WebViewController] used without a `WebViewWidget`.
///
/// Closing the session deterministically releases its platform resources. The
/// controller must not be retained or used after [close] starts.
class OffscreenWebViewSession {
  OffscreenWebViewSession._(WebViewController controller)
    : _controller = controller;

  /// Creates an offscreen session with default controller parameters.
  static Future<OffscreenWebViewSession> create({
    void Function(WebViewPermissionRequest request)? onPermissionRequest,
  }) async {
    _verifyPlatformSupport();
    return _fromOwnedController(
      WebViewController(onPermissionRequest: onPermissionRequest),
    );
  }

  /// Creates an offscreen session with platform-specific controller params.
  static Future<OffscreenWebViewSession> fromPlatformCreationParams(
    PlatformWebViewControllerCreationParams params, {
    void Function(WebViewPermissionRequest request)? onPermissionRequest,
  }) async {
    _verifyPlatformSupport();
    return _fromOwnedController(
      WebViewController.fromPlatformCreationParams(
        params,
        onPermissionRequest: onPermissionRequest,
      ),
    );
  }

  /// Transfers ownership of [controller] to a new offscreen session.
  ///
  /// The caller must not independently retain or use [controller] after the
  /// returned session is closed.
  static Future<OffscreenWebViewSession> fromController(
    WebViewController controller,
  ) async {
    if (!await controller.isOffscreenWebViewSupported()) {
      throw UnsupportedError(
        'Offscreen WebView sessions are not supported on the current platform.',
      );
    }
    return OffscreenWebViewSession._(controller);
  }

  static Future<OffscreenWebViewSession> _fromOwnedController(
    WebViewController controller,
  ) async {
    try {
      return await fromController(controller);
    } catch (error, stackTrace) {
      try {
        await controller.platform.closeOffscreenWebView();
      } catch (_) {
        // Preserve the creation failure while making cleanup best-effort.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static void _verifyPlatformSupport() {
    if (WebViewPlatform.instance?.supportsOffscreenWebViews != true) {
      throw UnsupportedError(
        'Offscreen WebView sessions are not supported on the current platform.',
      );
    }
  }

  WebViewController? _controller;
  Future<void>? _closeFuture;

  /// The controller owned by this session.
  ///
  /// Access after [close] starts throws [StateError].
  WebViewController get controller {
    final WebViewController? value = _controller;
    if (value == null) {
      throw StateError('The offscreen WebView session is closed.');
    }
    return value;
  }

  /// Whether [close] has started.
  bool get isClosed => _controller == null;

  /// Permanently releases the controller and its platform resources.
  ///
  /// Repeated calls return the same cleanup operation.
  Future<void> close() {
    final Future<void>? existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    final WebViewController ownedController = controller;
    _controller = null;
    return _closeFuture = Future<void>.sync(
      ownedController.platform.closeOffscreenWebView,
    );
  }
}

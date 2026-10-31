import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'webview_controller.dart';
import 'webview_cookie_manager.dart';
import 'webview_data_manager.dart';

/// Owns one controller and its selected website-data store.
///
/// The controller can be displayed with WebViewWidget or used offscreen where
/// supported. Remove its widget before closing the session. Capabilities distinguish
/// limited incognito handling from native private stores. Requests for an
/// isolatedIncognito store never fall back to shared storage.
class WebViewSession {
  WebViewSession._(this._controller, this.mode, this.capabilities);

  /// Queries runtime support. Failures are logged and return no supported modes.
  static Future<WebViewSessionCapabilities> getCapabilities() async {
    try {
      final platform = WebViewPlatform.instance;
      if (platform == null) {
        throw StateError('No WebView platform is registered.');
      }
      return await platform.getSessionCapabilities();
    } catch (error) {
      debugPrint(
        'webview_all: Cannot query WebView session capabilities: $error',
      );
      return WebViewSessionCapabilities(
        supportedModes: const {},
        privateSessionRestriction: error.toString(),
      );
    }
  }

  /// Creates one owned WebView with the requested data policy.
  ///
  /// Unsupported modes or creation failures print a diagnostic and return null.
  /// No ordinary WebView is created as a fallback for private browsing.
  static Future<WebViewSession?> create({
    WebViewSessionMode mode = WebViewSessionMode.incognito,
    void Function(WebViewPermissionRequest request)? onPermissionRequest,
  }) async {
    final capabilities = await getCapabilities();
    if (!capabilities.canClose || !capabilities.supports(mode)) {
      final message =
          'Owned WebView session mode ${mode.name} is not supported on this platform/runtime.';
      debugPrint(
        'webview_all: $message ${capabilities.privateSessionRestriction ?? ''} No WebView was created.',
      );
      return null;
    }
    if (mode == WebViewSessionMode.incognito &&
        capabilities.incognitoSupport == WebViewIncognitoSupport.limited) {
      debugPrint(
        'webview_all: Limited incognito handling. ${capabilities.privateSessionRestriction ?? "Website data may remain shared and persistent."}',
      );
    }
    WebViewController? controller;
    try {
      controller = WebViewController.fromPlatformCreationParams(
        PlatformWebViewControllerCreationParams(sessionMode: mode),
        onPermissionRequest: onPermissionRequest,
      );
      await controller.platform.prepareSession();
      return WebViewSession._(controller, mode, capabilities);
    } catch (error) {
      try {
        await controller?.platform.closeWebViewSession();
      } catch (_) {
        // Preserve the creation failure.
      }
      debugPrint(
        'webview_all: WebView session creation failed: $error. No session was returned.',
      );
      return null;
    }
  }

  final WebViewSessionMode mode;
  final WebViewSessionCapabilities capabilities;
  WebViewController? _controller;
  Future<void>? _closeFuture;

  bool get isClosed => _controller == null;

  WebViewController get controller =>
      _controller ?? (throw StateError('The WebView session is closed.'));

  /// Addresses this store. In shared/native-incognito modes, other views may
  /// share the store; isolatedIncognito guarantees separate stores.
  late final WebViewCookieManager cookieManager =
      WebViewCookieManager.fromPlatform(
        _SessionCookieManager(
          this,
          controller.platform.createSessionCookieManager(),
        ),
      );

  late final WebViewDataManager dataManager = WebViewDataManager.fromPlatform(
    _SessionDataManager(this, controller.platform.createSessionDataManager()),
  );

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final owned = controller;
    _controller = null;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    Future<void>.sync(
      owned.platform.closeWebViewSession,
    ).then(completion.complete, onError: completion.completeError);
    return completion.future;
  }
}

class _SessionCookieManager extends PlatformWebViewCookieManager {
  _SessionCookieManager(this.session, this.delegate)
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
  final WebViewSession session;
  final PlatformWebViewCookieManager delegate;
  void _checkOpen() {
    session.controller;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    _checkOpen();
    return delegate.setCookie(cookie);
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) {
    _checkOpen();
    return delegate.getCookies(url);
  }

  @override
  Future<bool> clearCookies() {
    _checkOpen();
    return delegate.clearCookies();
  }
}

class _SessionDataManager extends PlatformWebViewDataManager {
  _SessionDataManager(this.session, this.delegate)
    : super.implementation(const PlatformWebViewDataManagerCreationParams());
  final WebViewSession session;
  final PlatformWebViewDataManager delegate;
  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() {
    session.controller;
    return delegate.clearAllWebsiteData();
  }
}

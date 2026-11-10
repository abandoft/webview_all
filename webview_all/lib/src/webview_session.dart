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
  WebViewSession._(
    this._controller,
    this.mode,
    this.capabilities, {
    Future<void> Function()? onClosed,
  }) : _onClosed = onClosed;
  final Future<void> Function()? _onClosed;

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
    WebViewMediaPlaybackPolicy? mediaPlaybackPolicy,
    List<String> customSchemes = const [],
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
        PlatformWebViewControllerCreationParams(
          sessionMode: mode,
          mediaPlaybackPolicy: mediaPlaybackPolicy,
          customSchemes: customSchemes,
        ),
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
    Future<void>.sync(owned.platform.closeWebViewSession)
        .whenComplete(() async {
          await _onClosed?.call();
        })
        .then(completion.complete, onError: completion.completeError);
    return completion.future;
  }
}

/// Owns a website-data store shared by explicitly created sessions.
///
/// A named profile persists across launches; unnamed private profiles follow
/// native private-session capabilities. Closing a profile stops new sessions;
/// its store stays alive until existing sessions close. Remove their widgets
/// and close each session explicitly. Closing never deletes persistent data.
class WebViewProfile {
  WebViewProfile._(this._anchor, this.name) {
    _released.future.ignore();
  }
  final WebViewSession _anchor;
  final String? name;
  int _sessions = 0;
  bool _closing = false;
  Future<void>? _release;
  final Completer<void> _released = Completer<void>();
  bool get isClosed => _closing;
  Future<void> get whenReleased => _released.future;
  WebViewSessionMode get mode => _anchor.mode;
  WebViewCookieManager get cookieManager => _anchor.cookieManager;
  WebViewDataManager get dataManager => _anchor.dataManager;

  static Future<WebViewProfile?> create({
    String? name,
    WebViewSessionMode? mode,
    WebViewMediaPlaybackPolicy? mediaPlaybackPolicy,
    List<String> customSchemes = const [],
  }) async {
    final selectedMode =
        mode ??
        (name == null
            ? WebViewSessionMode.isolatedIncognito
            : WebViewSessionMode.shared);
    final caps = await WebViewSession.getCapabilities();
    if (!caps.canClose ||
        !caps.relatedControllers ||
        !caps.supports(selectedMode) ||
        (name != null &&
            (!caps.namedProfiles ||
                selectedMode != WebViewSessionMode.shared ||
                !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(name)))) {
      debugPrint(
        'webview_all: this profile configuration is unavailable. Named profiles require engine support, shared mode and a name of 1–64 ASCII letters, numbers, underscores or hyphens. Private profiles require related-controller support. No fallback store was created.',
      );
      return null;
    }
    WebViewController? anchor;
    try {
      anchor = WebViewController.fromPlatformCreationParams(
        PlatformWebViewControllerCreationParams(
          sessionMode: selectedMode,
          profileName: name,
          mediaPlaybackPolicy: mediaPlaybackPolicy,
          customSchemes: customSchemes,
        ),
      );
      await anchor.platform.prepareSession();
      if (caps.incognitoSupport == WebViewIncognitoSupport.limited &&
          selectedMode != WebViewSessionMode.shared) {
        debugPrint(
          'webview_all: this private profile provides limited privacy settings only. ${caps.privateSessionRestriction ?? "Website data remains shared and persistent."}',
        );
      }
      return WebViewProfile._(
        WebViewSession._(anchor, selectedMode, caps),
        name,
      );
    } catch (error) {
      try {
        await anchor?.platform.closeWebViewSession();
      } catch (_) {}
      debugPrint(
        'webview_all: profile creation failed: $error. No fallback store was created.',
      );
      return null;
    }
  }

  Future<WebViewSession?> createSession({
    void Function(WebViewPermissionRequest request)? onPermissionRequest,
  }) async {
    if (_closing) {
      debugPrint(
        'webview_all: the profile is closed; no additional session was created.',
      );
      return null;
    }
    _sessions++;
    var reserved = true;
    Future<void> release() async {
      if (!reserved) return;
      reserved = false;
      await _sessionClosed();
    }

    PlatformWebViewController? controller;
    try {
      controller = await _anchor.controller.platform.createRelatedController();
      if (controller == null) {
        await release();
        return null;
      }
      await controller.prepareSession();
      if (_closing) {
        await controller.closeWebViewSession();
        await release();
        return null;
      }
      return WebViewSession._(
        WebViewController.fromPlatform(
          controller,
          onPermissionRequest: onPermissionRequest,
        ),
        mode,
        _anchor.capabilities,
        onClosed: release,
      );
    } catch (error) {
      try {
        await controller?.closeWebViewSession();
      } catch (_) {}
      try {
        await release();
      } catch (_) {}
      debugPrint('webview_all: profile session creation failed: $error');
      return null;
    }
  }

  Future<void> _sessionClosed() async {
    _sessions--;
    if (_closing && _sessions == 0) await _releaseAnchor();
  }

  Future<void> _releaseAnchor() => _release ??= () async {
    try {
      await _anchor.close();
      _released.complete();
    } catch (error, stack) {
      _released.completeError(error, stack);
      rethrow;
    }
  }();
  Future<void> close() async {
    _closing = true;
    if (_sessions == 0) await _releaseAnchor();
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
  Future<WebViewCookieCapabilities> getCapabilities() {
    _checkOpen();
    return delegate.getCapabilities();
  }

  @override
  Future<bool> deleteCookie({
    required String name,
    required String domain,
    String path = '/',
  }) {
    _checkOpen();
    return delegate.deleteCookie(name: name, domain: domain, path: path);
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
  Future<List<WebViewDataRecord>?> getWebsiteDataRecords({
    WebViewDataTarget? target,
    Set<WebViewDataType> dataTypes = const {...WebViewDataType.values},
  }) {
    session.controller;
    return delegate.getWebsiteDataRecords(target: target, dataTypes: dataTypes);
  }

  @override
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) {
    session.controller;
    return delegate.clearWebsiteDataFor(target, dataTypes: dataTypes);
  }

  @override
  Future<WebViewDataCapabilities> getCapabilities() {
    session.controller;
    return delegate.getCapabilities();
  }

  @override
  Future<WebViewDataClearingResult> clearWebsiteData({
    required Set<WebViewDataType> dataTypes,
  }) {
    session.controller;
    return delegate.clearWebsiteData(dataTypes: dataTypes);
  }

  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() {
    session.controller;
    return delegate.clearAllWebsiteData();
  }
}

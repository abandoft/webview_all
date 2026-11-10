// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'windows_webview_cookie.dart';
import 'windows_webview_native.dart' as native_webview;

/// Creation parameters for [WindowsWebViewCookieManager].
class WindowsWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  /// Creates a new [WindowsWebViewCookieManagerCreationParams].
  const WindowsWebViewCookieManagerCreationParams();

  /// Creates a [WindowsWebViewCookieManagerCreationParams] from generic params.
  const WindowsWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  );
}

/// Cookie manager implementation for Windows.
///
/// Uses the shared WebView2 environment, including an active or initializing
/// custom data directory. Configure custom environment options with
/// `WindowsWebViewController.ensureEnvironment` before the first cookie operation
/// or WebView. If no environment exists, cookie operations initialize defaults.
class WindowsWebViewCookieManager extends PlatformWebViewCookieManager {
  @override
  Future<WebViewCookieCapabilities> getCapabilities() async =>
      WebViewCookieCapabilities(
        setHttpOnly: true,
        deleteByIdentity: true,
        readableAttributes: Set.unmodifiable(WebViewCookieAttribute.values),
      );

  @override
  Future<bool> deleteCookie({
    required String name,
    required String domain,
    String path = '/',
  }) async {
    WebViewCookie(name: name, value: '', domain: domain, path: path).validate();
    await deleteCookiesWithNameDomainAndPath(
      name: name,
      domain: domain,
      path: path,
    );
    return true;
  }

  /// Creates a [WindowsWebViewCookieManager].
  WindowsWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(
        params is WindowsWebViewCookieManagerCreationParams
            ? params
            : WindowsWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                params,
              ),
      );

  /// Uses the profile selected when this controller was created.
  WindowsWebViewCookieManager.forController(
    native_webview.WebviewController controller,
  ) : _sessionController = controller,
      super.implementation(const WindowsWebViewCookieManagerCreationParams());

  native_webview.WebviewController? _sessionController;

  // WebView2 can end its browser process when its last controller closes.
  // Keep one unattached ordinary controller alive so session cookies set before
  // the first displayed page survive. Engine disposal releases the native view.
  static native_webview.WebviewController? _ordinaryController;
  static Future<native_webview.WebviewController>? _ordinaryInitialization;
  static StreamSubscription<int>? _ordinaryFailures;

  static Future<native_webview.WebviewController> _ordinaryStore() {
    final pending = _ordinaryInitialization;
    if (pending != null) return pending;
    final controller = native_webview.WebviewController();
    _ordinaryController = controller;
    return _ordinaryInitialization = () async {
      try {
        await controller.initialize();
        if (!identical(_ordinaryController, controller)) {
          throw StateError('Cookie-store initialization was cancelled.');
        }
        _ordinaryFailures = controller.processFailures.stream.listen((kind) {
          if ((kind == 0 || kind == 1) &&
              identical(_ordinaryController, controller)) {
            unawaited(resetSharedCookieController());
          }
        });
        return controller;
      } catch (_) {
        if (identical(_ordinaryController, controller)) {
          _ordinaryController = null;
          _ordinaryInitialization = null;
        }
        try {
          await controller.dispose();
        } catch (_) {}
        rethrow;
      }
    }();
  }

  @visibleForTesting
  static Future<void> resetSharedCookieController() async {
    final pending = _ordinaryInitialization;
    final subscription = _ordinaryFailures;
    _ordinaryController = null;
    _ordinaryInitialization = null;
    _ordinaryFailures = null;
    try {
      await subscription?.cancel();
      if (pending != null) await (await pending).dispose();
    } catch (error) {
      debugPrint(
        'webview_all_windows: releasing the ordinary cookie store failed: $error',
      );
    }
  }

  Future<T> _withController<T>(
    Future<T> Function(native_webview.WebviewController) operation,
  ) async {
    final controller = _sessionController ?? await _ordinaryStore();
    if (_sessionController != null) await controller.initialize();
    try {
      return await operation(controller);
    } on PlatformException {
      // Never replay a write with an unknown outcome. Recreate the ordinary
      // helper for the next explicit operation after a native process failure.
      if (_sessionController == null &&
          identical(_ordinaryController, controller)) {
        await resetSharedCookieController();
      }
      rethrow;
    }
  }

  @override
  Future<bool> clearCookies() =>
      _withController((controller) => controller.clearCookiesWithResult());

  @override
  Future<void> setCookie(WebViewCookie cookie) async {
    cookie.validate();
    _validateCookieFields(
      name: cookie.name,
      domain: cookie.domain,
      path: cookie.path,
    );

    await setWindowsCookie(
      WindowsWebViewCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        expires: cookie.expires,
        isSecure: cookie.isSecure,
        isHttpOnly: cookie.isHttpOnly,
        sameSite: cookie.sameSite == null
            ? null
            : WindowsWebViewCookieSameSite.values[cookie.sameSite!.index],
      ),
    );
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final cookies = await getWindowsCookies(url);
    return cookies
        .map(
          (WindowsWebViewCookie cookie) => WebViewCookie(
            name: cookie.name,
            value: cookie.value,
            domain: cookie.domain,
            path: cookie.path,
            expires: cookie.isSession == true ? null : cookie.expires,
            isSecure: cookie.isSecure,
            isHttpOnly: cookie.isHttpOnly,
            isSession: cookie.isSession,
            sameSite: cookie.sameSite == null
                ? null
                : WebViewCookieSameSite.values[cookie.sameSite!.index],
          ),
        )
        .toList();
  }

  /// Sets a full Windows WebView2 cookie.
  Future<void> setWindowsCookie(WindowsWebViewCookie cookie) async {
    _validateCookieFields(
      name: cookie.name,
      domain: cookie.domain,
      path: cookie.path,
    );

    await _withController(
      (controller) => controller.setCookie(
        name: cookie.name,
        value: cookie.value,
        domain: cookie.domain,
        path: cookie.path,
        expires: cookie.expires,
        isHttpOnly: cookie.isHttpOnly,
        isSecure: cookie.isSecure,
        sameSite: cookie.sameSite?.index,
      ),
    );
  }

  /// Returns full Windows WebView2 cookies visible for [url].
  Future<List<WindowsWebViewCookie>> getWindowsCookies(Uri url) =>
      _withController((controller) => controller.getCookies(url.toString()));

  /// Deletes a cookie by its native WebView2 cookie identity.
  Future<void> deleteWindowsCookie(WindowsWebViewCookie cookie) =>
      _withController((controller) async {
        await controller.deleteCookie(cookie);
        await controller.getCookies('');
      });

  /// Deletes cookies matching [name] and [url].
  Future<void> deleteCookiesWithNameAndUrl({
    required String name,
    required Uri url,
  }) => _withController((controller) async {
    await controller.deleteCookiesWithNameAndUrl(name, url.toString());
    await controller.getCookies('');
  });

  /// Deletes cookies matching [name], [domain], and [path].
  Future<void> deleteCookiesWithNameDomainAndPath({
    required String name,
    required String domain,
    required String path,
  }) => _withController((controller) async {
    await controller.deleteCookiesWithNameDomainAndPath(name, domain, path);
    // Wait for the native cookie queue, without restarting its browser.
    await controller.getCookies('');
  });

  void _validateCookieFields({
    required String name,
    required String domain,
    required String path,
  }) {
    _validateCookieName(name);
    _validateCookieAttribute('domain', domain);
    _validateCookieAttribute('path', path);

    if (path.isNotEmpty && !path.startsWith('/')) {
      throw ArgumentError.value(
        path,
        'cookie.path',
        'Cookie path must start with "/".',
      );
    }
    if (!_isValidPath(path)) {
      throw ArgumentError(
        'The path property for the provided cookie was not given a legal value.',
      );
    }
  }

  void _validateCookieName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(name, 'cookie.name', 'Cookie name is empty.');
    }

    if (RegExp(r'[\x00-\x20\x7F()<>@,;:\\"/\[\]?={}]+').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'cookie.name',
        'Cookie name contains characters rejected by browsers.',
      );
    }
  }

  void _validateCookieAttribute(String field, String value) {
    if (value.isEmpty) {
      return;
    }

    if (RegExp(r'[\x00-\x1F\x7F;]').hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'cookie.$field',
        'Cookie $field contains characters rejected by browsers.',
      );
    }
  }

  bool _isValidPath(String path) {
    // Permitted ranges based on RFC6265bis section 4.1.1.
    for (final char in path.codeUnits) {
      if ((char < 0x20 || char > 0x3A) && (char < 0x3C || char > 0x7E)) {
        return false;
      }
    }
    return true;
  }
}

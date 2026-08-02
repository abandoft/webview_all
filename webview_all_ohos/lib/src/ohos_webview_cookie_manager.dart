// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'ohos_webview_native.dart';
import 'ohos_webview_controller.dart';

/// Object specifying creation parameters for creating a [OhosWebViewCookieManager].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewCookieManagerCreationParams] for
/// more information.
@immutable
class OhosWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  /// Creates a new [OhosWebViewCookieManagerCreationParams] instance.
  const OhosWebViewCookieManagerCreationParams._(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewCookieManagerCreationParams params,
  ) : super();

  /// Creates a [OhosWebViewCookieManagerCreationParams] instance based on [PlatformWebViewCookieManagerCreationParams].
  factory OhosWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return OhosWebViewCookieManagerCreationParams._(params);
  }
}

/// Handles all cookie operations for the Ohos platform.
class OhosWebViewCookieManager extends PlatformWebViewCookieManager {
  /// Creates a new [OhosWebViewCookieManager].
  OhosWebViewCookieManager(
    PlatformWebViewCookieManagerCreationParams params, {
    CookieManager? cookieManager,
  }) : _cookieManager = cookieManager ?? CookieManager.instance,
       super.implementation(
         params is OhosWebViewCookieManagerCreationParams
             ? params
             : OhosWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                 params,
               ),
       );

  final CookieManager _cookieManager;

  @override
  Future<bool> clearCookies() {
    return _cookieManager.removeAllCookies();
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    _validateWebViewCookie(cookie);

    return _cookieManager.setCookie(
      cookie.domain,
      '${Uri.encodeComponent(cookie.name)}=${Uri.encodeComponent(cookie.value)}; path=${cookie.path}',
    );
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final String cookies = await _cookieManager.getCookies(url.toString());
    if (cookies.isEmpty) {
      return <WebViewCookie>[];
    }

    final List<WebViewCookie> webViewCookies = <WebViewCookie>[];
    for (final String cookie in cookies.split(';')) {
      final String trimmedCookie = cookie.trim();
      if (trimmedCookie.isEmpty) {
        continue;
      }

      final int separatorIndex = trimmedCookie.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }

      webViewCookies.add(
        WebViewCookie(
          name: _decodeCookieComponent(
            trimmedCookie.substring(0, separatorIndex),
          ),
          value: _decodeCookieComponent(
            trimmedCookie.substring(separatorIndex + 1),
          ),
          domain: url.host,
          path: '/',
        ),
      );
    }
    return webViewCookies;
  }

  String _decodeCookieComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    }
  }

  void _validateWebViewCookie(WebViewCookie cookie) {
    _validateCookieName(cookie.name);
    _validateCookieAttribute('domain', cookie.domain);
    _validateCookieAttribute('path', cookie.path);

    if (cookie.path.isNotEmpty && !cookie.path.startsWith('/')) {
      throw ArgumentError.value(
        cookie.path,
        'cookie.path',
        'Cookie path must start with "/".',
      );
    }
    if (!_isValidPath(cookie.path)) {
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
    // Permitted ranges based on RFC6265bis: https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
    for (final int char in path.codeUnits) {
      if ((char < 0x20 || char > 0x3A) && (char < 0x3C || char > 0x7E)) {
        return false;
      }
    }
    return true;
  }

  /// Sets whether the WebView should allow third party cookies to be set.
  ///
  /// The default behavior is controlled by the platform WebView engine and may
  /// vary across HarmonyOS/OpenHarmony versions.
  Future<void> setAcceptThirdPartyCookies(
    OhosWebViewController controller,
    bool accept,
  ) {
    // ignore: invalid_use_of_visible_for_testing_member
    final WebView webView = WebView.api.instanceManager
        .getInstanceWithWeakReference(controller.webViewIdentifier)!;
    return _cookieManager.setAcceptThirdPartyCookies(webView, accept);
  }
}

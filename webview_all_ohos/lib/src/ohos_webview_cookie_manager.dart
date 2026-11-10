// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'ohos_webview_native.dart';
import 'channels/host_api.dart';
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
  @override
  Future<WebViewCookieCapabilities>
  getCapabilities() async => const WebViewCookieCapabilities(
    setHttpOnly: true,
    deleteByIdentity: true,
    limitation:
        'The engine returns cookie names and values only. Domain and path on reads are compatibility placeholders, not the stored cookie identity; other attributes remain null.',
  );

  @override
  Future<bool> deleteCookie({
    required String name,
    required String domain,
    String path = '/',
  }) async {
    final expired = WebViewCookie(
      name: name,
      value: '',
      domain: domain,
      path: path,
      expires: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      isSecure:
          name.startsWith('__Secure-') ||
              name.startsWith('__Host-') ||
              name.startsWith('__Http-')
          ? true
          : null,
      isHttpOnly: name.startsWith('__Http-') || name.startsWith('__Host-Http-')
          ? true
          : null,
    );
    // Canonical domains retain the leading dot for domain cookies. Omitting
    // Domain expires only the host cookie; never also expire its domain peer.
    await _writeCookie(expired, includeDomain: domain.startsWith('.'));
    return true;
  }

  /// Creates a new [OhosWebViewCookieManager].
  OhosWebViewCookieManager(
    PlatformWebViewCookieManagerCreationParams params, {
    CookieManager? cookieManager,
    bool incognito = false,
  }) : _incognito = incognito,
       _cookieManager = cookieManager ?? CookieManager.instance,
       super.implementation(
         params is OhosWebViewCookieManagerCreationParams
             ? params
             : OhosWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                 params,
               ),
       );

  final bool _incognito;
  final CookieManager _cookieManager;

  @override
  Future<bool> clearCookies() {
    return _incognito
        ? CookieManagerHostApi().removeAllCookies(0, incognito: true)
        : _cookieManager.removeAllCookies();
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) => _writeCookie(cookie);

  Future<void> _writeCookie(WebViewCookie cookie, {bool? includeDomain}) {
    final normalized = cookie.forUrlStore;
    normalized.validate();
    final value = normalized.toSetCookieHeader(
      includeDomain:
          includeDomain ??
          (identical(normalized, cookie) &&
              !(normalized.name.startsWith('__Host-') &&
                  !normalized.domain.startsWith('.'))),
    );
    if (_incognito) {
      return CookieManagerHostApi().setCookie(
        0,
        cookie.url.toString(),
        value,
        incognito: true,
      );
    }
    return _cookieManager.setCookie(cookie.url.toString(), value);
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final String cookies = await (_incognito
        ? CookieManagerHostApi().getCookies(0, url.toString(), incognito: true)
        : _cookieManager.getCookies(url.toString()));
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

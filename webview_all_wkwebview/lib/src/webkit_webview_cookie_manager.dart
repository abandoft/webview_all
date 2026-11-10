// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'common/web_kit.g.dart';
import 'common/platform_webview.dart';

/// Object specifying creation parameters for a [WebKitWebViewCookieManager].
class WebKitWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  /// Constructs a [WebKitWebViewCookieManagerCreationParams].
  WebKitWebViewCookieManagerCreationParams();

  /// Constructs a [WebKitWebViewCookieManagerCreationParams] using a
  /// [PlatformWebViewCookieManagerCreationParams].
  WebKitWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewCookieManagerCreationParams params,
  );

  /// Manages stored data for [WKWebView]s.
  late final WKWebsiteDataStore _websiteDataStore =
      WKWebsiteDataStore.defaultDataStore;
}

/// An implementation of [PlatformWebViewCookieManager] with the WebKit api.
class WebKitWebViewCookieManager extends PlatformWebViewCookieManager {
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
    final store = (await _store).httpCookieStore;
    for (final cookie in await store.getAllCookies()) {
      final props = await cookie.getProperties();
      if (props?[HttpCookiePropertyKey.name] == name &&
          props?[HttpCookiePropertyKey.domain]?.toString().toLowerCase() ==
              domain.toLowerCase() &&
          props?[HttpCookiePropertyKey.path] == path) {
        await store.deleteCookie(cookie);
      }
    }
    return true;
  }

  /// Constructs a [WebKitWebViewCookieManager].
  WebKitWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(
        params is WebKitWebViewCookieManagerCreationParams
            ? params
            : WebKitWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                params,
              ),
      );

  /// Uses the actual store configured on this WebView, including private stores.
  WebKitWebViewCookieManager.forController(PlatformWebView controller)
    : _sessionController = controller,
      super.implementation(WebKitWebViewCookieManagerCreationParams());

  PlatformWebView? _sessionController;

  Future<WKWebsiteDataStore> get _store async => _sessionController == null
      ? _webkitParams._websiteDataStore
      : await _sessionController!.configuration.getWebsiteDataStore();

  WebKitWebViewCookieManagerCreationParams get _webkitParams =>
      params as WebKitWebViewCookieManagerCreationParams;

  @override
  Future<bool> clearCookies() {
    if (_sessionController == null) {
      return _webkitParams._websiteDataStore.removeDataOfTypes(
        <WebsiteDataType>[WebsiteDataType.cookies],
        0.0,
      );
    }
    return _store.then(
      (store) => store.removeDataOfTypes(<WebsiteDataType>[
        WebsiteDataType.cookies,
      ], 0.0),
    );
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) async {
    cookie.validate();
    if (!_isValidPath(cookie.path)) {
      throw ArgumentError(
        'The path property for the provided cookie was not given a legal value.',
      );
    }

    return (await _store).httpCookieStore.setCookie(
      HTTPCookie(
        properties: <HttpCookiePropertyKey, Object>{
          HttpCookiePropertyKey.name: cookie.name,
          HttpCookiePropertyKey.value: cookie.value,
          HttpCookiePropertyKey.domain: cookie.domain,
          HttpCookiePropertyKey.path: cookie.path,
          if (cookie.expires != null)
            HttpCookiePropertyKey.expires: cookie
                .expires!
                .millisecondsSinceEpoch
                .toDouble(),
          if (cookie.isSecure == true) HttpCookiePropertyKey.secure: 'TRUE',
          if (cookie.isHttpOnly == true) HttpCookiePropertyKey.httpOnly: 'TRUE',
          if (cookie.sameSite != null)
            HttpCookiePropertyKey.sameSitePolicy: switch (cookie.sameSite!) {
              WebViewCookieSameSite.none => 'None',
              WebViewCookieSameSite.lax => 'Lax',
              WebViewCookieSameSite.strict => 'Strict',
            },
        },
      ),
    );
  }

  bool _isValidPath(String path) {
    // Permitted ranges based on RFC6265bis: https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
    return !path.codeUnits.any((int char) {
      return (char < 0x20 || char > 0x3A) && (char < 0x3C || char > 0x7E);
    });
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final List<HTTPCookie> httpCookies = await (await _store).httpCookieStore
        .getAllCookies();

    final Iterable<Future<WebViewCookie?>> webviewCookies = httpCookies.map((
      cookie,
    ) async {
      final Map<HttpCookiePropertyKey, Object>? props = await cookie
          .getProperties();

      if (props == null) {
        return null;
      }

      final domain = props[HttpCookiePropertyKey.domain].toString();

      // Follow RFC 6265 guideline for domain matching
      var cookieDomain = domain;
      if (domain.startsWith('.')) {
        cookieDomain = cookieDomain.substring(1);
      }

      cookieDomain = cookieDomain.toLowerCase();
      final host = url.host.toLowerCase();
      if (host != cookieDomain &&
          !(domain.startsWith('.') && host.endsWith('.$cookieDomain'))) {
        return null;
      }

      final path = props[HttpCookiePropertyKey.path]?.toString() ?? '/';
      final requestPath = url.path.isEmpty ? '/' : url.path;
      if (requestPath != path &&
          !(requestPath.startsWith(path) &&
              (path.endsWith('/') ||
                  requestPath.substring(path.length).startsWith('/')))) {
        return null;
      }
      final secure = _boolProperty(props[HttpCookiePropertyKey.secure]);
      if (secure == true && url.scheme != 'https') return null;
      final expiry = props[HttpCookiePropertyKey.expires];
      final expires = expiry is num
          ? DateTime.fromMillisecondsSinceEpoch(expiry.toInt(), isUtc: true)
          : null;
      if (expires != null && !expires.isAfter(DateTime.now())) return null;
      final sameSite = props[HttpCookiePropertyKey.sameSitePolicy]
          ?.toString()
          .toLowerCase();

      return WebViewCookie(
        name: props[HttpCookiePropertyKey.name].toString(),
        value: props[HttpCookiePropertyKey.value].toString(),
        domain: domain,
        path: path,
        expires: expires,
        isSecure: secure,
        isHttpOnly: _boolProperty(props[HttpCookiePropertyKey.httpOnly]),
        isSession: _boolProperty(props[HttpCookiePropertyKey.discard]),
        sameSite: switch (sameSite) {
          'none' => WebViewCookieSameSite.none,
          'lax' => WebViewCookieSameSite.lax,
          'strict' => WebViewCookieSameSite.strict,
          _ => null,
        },
      );
    });

    return (await Future.wait(webviewCookies)).nonNulls.toList();
  }

  bool? _boolProperty(Object? value) => value == null
      ? null
      : value is bool
      ? value
      : {'true', 'yes', '1'}.contains(value.toString().toLowerCase());
}

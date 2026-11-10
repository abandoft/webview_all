// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'android_webkit.g.dart';
import 'android_webview_controller.dart';

/// Object specifying creation parameters for creating a [AndroidWebViewCookieManager].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewCookieManagerCreationParams] for
/// more information.
@immutable
class AndroidWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  /// Creates a new [AndroidWebViewCookieManagerCreationParams] instance.
  const AndroidWebViewCookieManagerCreationParams._(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewCookieManagerCreationParams params,
  ) : super();

  /// Creates a [AndroidWebViewCookieManagerCreationParams] instance based on [PlatformWebViewCookieManagerCreationParams].
  factory AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return AndroidWebViewCookieManagerCreationParams._(params);
  }
}

/// Handles all cookie operations for the Android platform.
class AndroidWebViewCookieManager extends PlatformWebViewCookieManager {
  @override
  Future<WebViewCookieCapabilities> getCapabilities() async {
    final metadata = await _supportsCookieInfo;
    return WebViewCookieCapabilities(
      setHttpOnly: true,
      deleteByIdentity: true,
      readableAttributes: metadata
          ? WebViewCookieAttribute.values.toSet()
          : const {},
      limitation: metadata
          ? 'Attributes follow the provider\'s canonical Set-Cookie information. Omitted SameSite remains unknown.'
          : 'This System WebView cannot report cookie attributes. Domain/path are compatibility placeholders and other read attributes remain null.',
    );
  }

  late final Future<bool> _supportsCookieInfo = () async {
    try {
      return await _cookieManager.supportsCookieInfo();
    } catch (_) {
      return false;
    }
  }();

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

  /// Creates a new [AndroidWebViewCookieManager].
  AndroidWebViewCookieManager(
    PlatformWebViewCookieManagerCreationParams params, {
    CookieManager? cookieManager,
  }) : _cookieManager = cookieManager ?? CookieManager.instance,
       super.implementation(
         params is AndroidWebViewCookieManagerCreationParams
             ? params
             : AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                 params,
               ),
       );

  final CookieManager _cookieManager;

  @override
  Future<bool> clearCookies() {
    return _cookieManager.removeAllCookies();
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
    return _cookieManager.setCookie(cookie.url.toString(), value);
  }

  /// Sets whether the WebView should allow third party cookies to be set.
  ///
  /// Defaults to false.
  Future<void> setAcceptThirdPartyCookies(
    AndroidWebViewController controller,
    bool accept,
  ) {
    final WebView webView = PigeonInstanceManager.instance
        .getInstanceWithWeakReference(controller.webViewIdentifier)!;
    return _cookieManager.setAcceptThirdPartyCookies(webView, accept);
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    if (await _supportsCookieInfo) {
      try {
        final entries = await _cookieManager.getCookieInfo(url.toString());
        if (entries != null) {
          return entries
              .map((value) => _parseInfo(value, url))
              .whereType<WebViewCookie>()
              .toList();
        }
      } catch (error) {
        debugPrint(
          'webview_all_android: cookie attributes could not be read; falling back to names and values: $error',
        );
      }
    }
    final String? cookies = await _cookieManager.getCookies(url.toString());
    if (cookies == null || cookies.isEmpty) {
      return [];
    }

    final webViewCookies = <WebViewCookie>[];
    for (final String rawCookie in cookies.split(';')) {
      final String cookie = rawCookie.trim();
      final int separatorIndex = cookie.indexOf('=');
      if (separatorIndex <= 0) {
        continue;
      }
      webViewCookies.add(
        WebViewCookie(
          name: _decodeCookieComponent(cookie.substring(0, separatorIndex)),
          value: _decodeCookieComponent(cookie.substring(separatorIndex + 1)),
          domain: url.host,
          path: '/',
        ),
      );
    }

    return webViewCookies;
  }

  WebViewCookie? _parseInfo(String value, Uri url) {
    final fields = value.split(';');
    final first = fields.first.trim();
    final equal = first.indexOf('=');
    if (equal <= 0) return null;
    final attributes = <String, String>{};
    for (final field in fields.skip(1)) {
      final split = field.indexOf('=');
      attributes[(split < 0 ? field : field.substring(0, split))
          .trim()
          .toLowerCase()] = split < 0
          ? ''
          : field.substring(split + 1).trim();
    }
    DateTime? expires;
    if (attributes['expires'] case final String date) {
      try {
        expires = HttpDate.parse(date).toUtc();
      } on FormatException {
        /* Unknown native date. */
      }
    }
    final age = int.tryParse(attributes['max-age'] ?? '');
    if (age != null) {
      try {
        final now = DateTime.now().toUtc();
        // Clamp before constructing Duration: native Max-Age can exceed both
        // Duration's microsecond range and DateTime's supported date range.
        const maxMilliseconds = 8640000000000000;
        expires = age <= 0
            ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
            : DateTime.fromMillisecondsSinceEpoch(
                age > (maxMilliseconds - now.millisecondsSinceEpoch) ~/ 1000
                    ? maxMilliseconds
                    : now.millisecondsSinceEpoch + age * 1000,
                isUtc: true,
              );
      } on ArgumentError {
        /* Preserve the independently reported expiry. */
      }
    }
    final sameSite = switch (attributes['samesite']?.toLowerCase()) {
      'strict' => WebViewCookieSameSite.strict,
      'lax' => WebViewCookieSameSite.lax,
      'none' => WebViewCookieSameSite.none,
      _ => null,
    };
    return WebViewCookie(
      name: _decodeCookieComponent(first.substring(0, equal)),
      value: _decodeCookieComponent(first.substring(equal + 1)),
      domain: attributes['domain'] ?? url.host,
      path: attributes['path'] ?? '/',
      expires: expires,
      isSecure: attributes.containsKey('secure'),
      isHttpOnly: attributes.containsKey('httponly'),
      sameSite: sameSite,
      isSession:
          !attributes.containsKey('expires') &&
          !attributes.containsKey('max-age'),
    );
  }

  String _decodeCookieComponent(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    }
  }
}

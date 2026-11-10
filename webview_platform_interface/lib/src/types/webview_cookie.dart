// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

enum WebViewCookieSameSite { none, lax, strict }

enum WebViewCookieAttribute {
  domain,
  path,
  expires,
  secure,
  httpOnly,
  sameSite,
  session,
}

@immutable
class WebViewCookieCapabilities {
  const WebViewCookieCapabilities({
    this.setHttpOnly = false,
    this.deleteByIdentity = false,
    this.readableAttributes = const {},
    this.limitation,
  });

  final bool setHttpOnly;
  final bool deleteByIdentity;

  /// Metadata exposed by native reads. Other fields may be null or, for
  /// domain/path, compatibility placeholders derived from the query URL.
  final Set<WebViewCookieAttribute> readableAttributes;
  final String? limitation;
}

/// A cookie in the website-data store selected by its cookie manager.
@immutable
class WebViewCookie {
  /// Creates a cookie, optionally specifying expiry and security attributes.
  const WebViewCookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expires,
    this.isSecure,
    this.isHttpOnly,
    this.sameSite,
    this.isSession,
  });

  /// The cookie-name of the cookie.
  ///
  /// Its value should match "cookie-name" in RFC6265bis:
  /// https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
  final String name;

  /// The cookie-value of the cookie.
  ///
  /// Its value should match "cookie-value" in RFC6265bis:
  /// https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
  final String value;

  /// The domain-value of the cookie.
  ///
  /// Its value should match "domain-value" in RFC6265bis:
  /// https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
  final String domain;

  /// The path-value of the cookie, set to `/` by default.
  ///
  /// Its value should match "path-value" in RFC6265bis:
  /// https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-rfc6265bis-02#section-4.1.1
  final String path;

  /// UTC expiration instant; null leaves the native default when setting.
  /// A null value from a read may mean the platform cannot report this field.
  final DateTime? expires;
  final bool? isSecure;
  final bool? isHttpOnly;
  final WebViewCookieSameSite? sameSite;

  /// Read-only metadata; null when the platform cannot report it.
  final bool? isSession;

  /// Checks cookie syntax before sending attributes to an engine.
  void validate({bool allowEmptyDomain = false}) {
    if (name.isEmpty ||
        RegExp(r'[\x00-\x20\x7F()<>@,;:\\"/\[\]?={}]+').hasMatch(name)) {
      throw ArgumentError.value(name, 'cookie.name', 'Invalid cookie name.');
    }
    if (RegExp(r'[\x00-\x20\x7F;/]').hasMatch(domain)) {
      throw ArgumentError.value(domain, 'cookie.domain');
    }
    if (RegExp(r'[\x00-\x1F\x7F;]').hasMatch(path)) {
      throw ArgumentError.value(path, 'cookie.path');
    }
    if ((!allowEmptyDomain && domain.isEmpty) ||
        (path.isNotEmpty && !path.startsWith('/'))) {
      throw ArgumentError('Invalid cookie domain or path.');
    }
    if (sameSite == WebViewCookieSameSite.none && isSecure != true) {
      throw ArgumentError('SameSite=None requires isSecure: true.');
    }
  }

  /// An HTTPS URL suitable for native cookie stores accepting a URL.
  Uri get url =>
      _legacyUrl ??
      Uri(
        scheme: 'https',
        host: domain.replaceFirst(RegExp(r'^\.'), ''),
        path: path.isEmpty ? '/' : path,
      );

  Uri? get _legacyUrl {
    final uri = Uri.tryParse(domain);
    return uri != null &&
            (uri.scheme == 'https' || uri.scheme == 'http') &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty
        ? uri
        : null;
  }

  /// Normalizes the legacy URL domain accepted by Android and OHOS stores.
  WebViewCookie get forUrlStore {
    final uri = _legacyUrl;
    if (uri == null) return this;
    return WebViewCookie(
      name: name,
      value: value,
      domain: uri.host,
      path: path,
      expires: expires,
      isSecure: isSecure,
      isHttpOnly: isHttpOnly,
      sameSite: sameSite,
      isSession: isSession,
    );
  }

  /// Serializes attributes for stores using the Set-Cookie format.
  /// Values retain the encoding used by the Android and OHOS implementations.
  String toSetCookieHeader({
    bool includeDomain = true,
    bool encodeName = true,
  }) {
    validate(allowEmptyDomain: !includeDomain);
    final buffer = StringBuffer(
      '${encodeName ? Uri.encodeComponent(name) : name}=${Uri.encodeComponent(value)}; path=${path.isEmpty ? '/' : path}',
    );
    if (includeDomain) buffer.write('; domain=$domain');
    if (expires case final instant?) {
      final utc = instant.toUtc();
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      String two(int value) => value.toString().padLeft(2, '0');
      buffer.write(
        '; expires=${weekdays[utc.weekday - 1]}, ${two(utc.day)} ${months[utc.month - 1]} ${utc.year.toString().padLeft(4, '0')} ${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)} GMT',
      );
    }
    if (isSecure == true) buffer.write('; Secure');
    if (isHttpOnly == true) buffer.write('; HttpOnly');
    if (sameSite case final policy?) buffer.write('; SameSite=${policy.name}');
    return buffer.toString();
  }

  @override
  String toString() {
    return 'WebViewCookie{name: $name, value: $value, domain: $domain, path: $path}';
  }
}

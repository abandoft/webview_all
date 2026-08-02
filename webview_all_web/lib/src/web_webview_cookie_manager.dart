import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:webview_platform_interface/webview_platform_interface.dart';

@immutable
class WebWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  const WebWebViewCookieManagerCreationParams();

  const WebWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  );
}

class WebWebViewCookieManager extends PlatformWebViewCookieManager {
  WebWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(
        params is WebWebViewCookieManagerCreationParams
            ? params
            : WebWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                params,
              ),
      );

  bool _reportedInaccessibleCookieUrl = false;

  @override
  Future<bool> clearCookies() async {
    final List<String> visibleCookies = _visibleCookieTokens();
    if (visibleCookies.isEmpty) {
      return false;
    }
    final Set<String> cookieNames = visibleCookies
        .map((String cookie) {
          final int separatorIndex = cookie.indexOf('=');
          return separatorIndex < 0
              ? cookie
              : cookie.substring(0, separatorIndex);
        })
        .where((String name) => name.isNotEmpty)
        .toSet();

    final Uri currentUri = _currentDocumentUri;
    final Set<String> paths = _cookiePathCandidates(currentUri.path);
    final Set<String> domains = _cookieDomainCandidates(currentUri.host);
    for (final String name in cookieNames) {
      for (final String path in paths) {
        _expireCookie(name, path: path);
        for (final String domain in domains) {
          _expireCookie(name, path: path, domain: domain);
        }
      }
    }

    return _visibleCookieTokens().length < visibleCookies.length;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) async {
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
    if (cookie.domain.isNotEmpty &&
        !_domainMatchesHost(cookie.domain, _currentDocumentUri.host)) {
      throw ArgumentError.value(
        cookie.domain,
        'cookie.domain',
        'Cookie domain is not visible to the current browser document.',
      );
    }

    final StringBuffer buffer = StringBuffer(
      '${cookie.name}=${Uri.encodeComponent(cookie.value)}',
    );
    if (cookie.domain.isNotEmpty) {
      buffer.write('; domain=${cookie.domain}');
    }
    if (cookie.path.isNotEmpty) {
      buffer.write('; path=${cookie.path}');
    } else {
      buffer.write('; path=/');
    }
    web.document.cookie = buffer.toString();
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final Uri currentUri = _currentDocumentUri;
    if (!_isCurrentCookieContext(url, currentUri)) {
      if (!_reportedInaccessibleCookieUrl) {
        _reportedInaccessibleCookieUrl = true;
        debugPrint(
          'webview_all_web: browser cookie reads are limited to the current document URL.',
        );
      }
      return <WebViewCookie>[];
    }

    final String cookieString = web.document.cookie;
    if (cookieString.isEmpty) {
      return <WebViewCookie>[];
    }

    return cookieString
        .split(';')
        .map((String cookie) => cookie.trim())
        .where((String cookie) => cookie.isNotEmpty)
        .map((String cookie) {
          final int splitIndex = cookie.indexOf('=');
          if (splitIndex == -1) {
            return WebViewCookie(
              name: cookie,
              value: '',
              domain: currentUri.host,
              path: '/',
            );
          }
          return WebViewCookie(
            name: cookie.substring(0, splitIndex),
            value: _decodeCookieValue(cookie.substring(splitIndex + 1)),
            domain: currentUri.host,
            path: '/',
          );
        })
        .toList();
  }

  Uri get _currentDocumentUri => Uri.parse(web.window.location.href);

  List<String> _visibleCookieTokens() {
    return web.document.cookie
        .split(';')
        .map((String cookie) => cookie.trim())
        .where((String cookie) => cookie.isNotEmpty)
        .toList(growable: false);
  }

  Set<String> _cookiePathCandidates(String currentPath) {
    final String path = currentPath.isEmpty ? '/' : currentPath;
    final Set<String> candidates = <String>{'/', path};
    for (int index = 1; index < path.length; index++) {
      if (path.codeUnitAt(index) == 0x2F) {
        candidates
          ..add(path.substring(0, index))
          ..add(path.substring(0, index + 1));
      }
    }
    return candidates;
  }

  Set<String> _cookieDomainCandidates(String host) {
    final List<String> labels = host.toLowerCase().split('.');
    final Set<String> candidates = <String>{};
    for (int index = 0; index < labels.length; index++) {
      final String domain = labels.sublist(index).join('.');
      if (domain.isNotEmpty) {
        candidates
          ..add(domain)
          ..add('.$domain');
      }
    }
    return candidates;
  }

  void _expireCookie(String name, {required String path, String? domain}) {
    final StringBuffer cookie = StringBuffer(
      '$name=; expires=Thu, 01 Jan 1970 00:00:00 GMT; max-age=0; path=$path',
    );
    if (domain != null) {
      cookie.write('; domain=$domain');
    }
    web.document.cookie = cookie.toString();
  }

  bool _domainMatchesHost(String domain, String host) {
    final String normalizedDomain = domain.trim().toLowerCase().replaceFirst(
      RegExp(r'^\.'),
      '',
    );
    final String normalizedHost = host.toLowerCase();
    return normalizedHost == normalizedDomain ||
        normalizedHost.endsWith('.$normalizedDomain');
  }

  bool _isCurrentCookieContext(Uri requested, Uri current) {
    final String requestedPath = requested.path.isEmpty ? '/' : requested.path;
    final String currentPath = current.path.isEmpty ? '/' : current.path;
    return requested.scheme.toLowerCase() == current.scheme.toLowerCase() &&
        requested.host.toLowerCase() == current.host.toLowerCase() &&
        requestedPath == currentPath;
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

  String _decodeCookieValue(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    }
  }
}

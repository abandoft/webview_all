import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_controller.dart';

class LinuxWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  const LinuxWebViewCookieManagerCreationParams();

  const LinuxWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  );
}

class LinuxWebViewCookieManager extends PlatformWebViewCookieManager {
  LinuxWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(
        params is LinuxWebViewCookieManagerCreationParams
            ? params
            : LinuxWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                params,
              ),
      );

  @override
  Future<bool> clearCookies() async {
    final bool? value = await LinuxWebViewController.rootChannel.invokeMethod(
      'clearCookies',
    );
    return value ?? false;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    _validateWebViewCookie(cookie);

    return LinuxWebViewController.rootChannel.invokeMethod<void>('setCookie', {
      'name': cookie.name,
      'value': cookie.value,
      'domain': cookie.domain,
      'path': cookie.path,
    });
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final List<Object?> rawCookies =
        await LinuxWebViewController.rootChannel.invokeListMethod<Object?>(
          'getCookies',
          <String, Object?>{'url': url.toString()},
        ) ??
        const <Object?>[];

    return rawCookies.whereType<Map<Object?, Object?>>().map((cookie) {
      return WebViewCookie(
        name: '${cookie['name'] ?? ''}',
        value: '${cookie['value'] ?? ''}',
        domain: '${cookie['domain'] ?? url.host}',
        path: '${cookie['path'] ?? '/'}',
      );
    }).toList();
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
    // Permitted ranges based on RFC6265bis section 4.1.1.
    for (final int char in path.codeUnits) {
      if ((char < 0x20 || char > 0x3A) && (char < 0x3C || char > 0x7E)) {
        return false;
      }
    }
    return true;
  }
}

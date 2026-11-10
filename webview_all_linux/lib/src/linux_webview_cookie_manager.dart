import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_controller.dart';

class LinuxWebViewCookieManagerCreationParams
    extends PlatformWebViewCookieManagerCreationParams {
  const LinuxWebViewCookieManagerCreationParams({this.webViewId});

  final int? webViewId;

  const LinuxWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
    PlatformWebViewCookieManagerCreationParams params,
  ) : webViewId = null;
}

class LinuxWebViewCookieManager extends PlatformWebViewCookieManager {
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
    await LinuxWebViewController.rootChannel
        .invokeMethod<void>('deleteCookie', {
          if (_viewId != null) 'webViewId': _viewId,
          'name': name,
          'domain': domain,
          'path': path,
          'url': WebViewCookie(
            name: name,
            value: '',
            domain: domain,
            path: path,
          ).url.toString(),
        });
    return true;
  }

  LinuxWebViewCookieManager(PlatformWebViewCookieManagerCreationParams params)
    : super.implementation(
        params is LinuxWebViewCookieManagerCreationParams
            ? params
            : LinuxWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
                params,
              ),
      );

  int? get _viewId =>
      (params as LinuxWebViewCookieManagerCreationParams).webViewId;

  @override
  Future<bool> clearCookies() async {
    final bool? value = await LinuxWebViewController.rootChannel.invokeMethod(
      'clearCookies',
      _viewId == null ? null : <String, Object?>{'webViewId': _viewId},
    );
    return value ?? false;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) {
    cookie.validate();

    return LinuxWebViewController.rootChannel.invokeMethod<void>('setCookie', {
      if (_viewId != null) 'webViewId': _viewId,
      'name': cookie.name,
      'value': cookie.value,
      'domain': cookie.domain,
      'path': cookie.path,
      if (cookie.expires != null)
        'expires': cookie.expires!.millisecondsSinceEpoch,
      if (cookie.isSecure != null) 'isSecure': cookie.isSecure,
      if (cookie.isHttpOnly != null) 'isHttpOnly': cookie.isHttpOnly,
      if (cookie.sameSite != null) 'sameSite': cookie.sameSite!.index,
    });
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async {
    final List<Object?> rawCookies =
        await LinuxWebViewController.rootChannel.invokeListMethod<Object?>(
          'getCookies',
          <String, Object?>{
            'url': url.toString(),
            if (_viewId != null) 'webViewId': _viewId,
          },
        ) ??
        const <Object?>[];

    return rawCookies.whereType<Map<Object?, Object?>>().map((cookie) {
      return WebViewCookie(
        name: '${cookie['name'] ?? ''}',
        value: '${cookie['value'] ?? ''}',
        domain: '${cookie['domain'] ?? url.host}',
        path: '${cookie['path'] ?? '/'}',
        expires: cookie['expires'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (cookie['expires'] as num).toInt(),
                isUtc: true,
              ),
        isSecure: cookie['isSecure'] as bool?,
        isHttpOnly: cookie['isHttpOnly'] as bool?,
        isSession: cookie['isSession'] as bool?,
        sameSite: cookie['sameSite'] == null
            ? null
            : WebViewCookieSameSite.values[(cookie['sameSite'] as num).toInt()],
      );
    }).toList();
  }
}

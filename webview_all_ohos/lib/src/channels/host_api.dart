import 'package:flutter/services.dart'
    show BinaryMessenger, MethodChannel, StandardMethodCodec, Uint8List;

import 'types.dart' show WebViewPoint;

const String _channelName = 'com.abandoft.webview_all_ohos/host_api';

class _HostChannel {
  _HostChannel(BinaryMessenger? binaryMessenger)
    : _channel = MethodChannel(
        _channelName,
        const StandardMethodCodec(),
        binaryMessenger,
      );

  final MethodChannel _channel;

  Future<T?> invoke<T>(String method, [Map<String, Object?>? arguments]) {
    return _channel.invokeMethod<T>(method, arguments);
  }
}

WebViewPoint _decodePoint(Object? value) {
  if (value is List<Object?>) {
    return WebViewPoint(x: value[0]! as int, y: value[1]! as int);
  }
  if (value is Map<Object?, Object?>) {
    return WebViewPoint(x: value['x']! as int, y: value['y']! as int);
  }
  throw StateError('Unexpected WebViewPoint payload: $value');
}

List<String?> _stringList(Object? value) {
  if (value == null) {
    return <String?>[];
  }
  return (value as List<Object?>).cast<String?>();
}

class InstanceManagerHostApi {
  InstanceManagerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> clear() {
    return _host.invoke<void>('InstanceManager.clear');
  }
}

class OhosObjectHostApi {
  OhosObjectHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> dispose(int identifier) {
    return _host.invoke<void>('OhosObject.dispose', <String, Object?>{
      'identifier': identifier,
    });
  }
}

class CookieManagerHostApi {
  CookieManagerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> attachInstance(int instanceIdentifier) {
    return _host.invoke<void>('CookieManager.attachInstance', <String, Object?>{
      'instanceIdentifier': instanceIdentifier,
    });
  }

  Future<void> setCookie(int identifier, String url, String value) {
    return _host.invoke<void>('CookieManager.setCookie', <String, Object?>{
      'identifier': identifier,
      'url': url,
      'value': value,
    });
  }

  Future<String> getCookies(int identifier, String url) async {
    return await _host.invoke<String>(
          'CookieManager.getCookies',
          <String, Object?>{'identifier': identifier, 'url': url},
        ) ??
        '';
  }

  Future<bool> removeAllCookies(int identifier) async {
    return await _host.invoke<bool>(
          'CookieManager.removeAllCookies',
          <String, Object?>{'identifier': identifier},
        ) ??
        false;
  }

  Future<void> setAcceptThirdPartyCookies(
    int identifier,
    int webViewIdentifier,
    bool accept,
  ) {
    return _host.invoke<void>(
      'CookieManager.setAcceptThirdPartyCookies',
      <String, Object?>{
        'identifier': identifier,
        'webViewIdentifier': webViewIdentifier,
        'accept': accept,
      },
    );
  }
}

class WebViewHostApi {
  WebViewHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId) {
    return _host.invoke<void>('WebView.create', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> loadData(
    int instanceId,
    String data,
    String? mimeType,
    String? encoding,
  ) {
    return _host.invoke<void>('WebView.loadData', <String, Object?>{
      'instanceId': instanceId,
      'data': data,
      'mimeType': mimeType,
      'encoding': encoding,
    });
  }

  Future<void> loadDataWithBaseUrl(
    int instanceId,
    String? baseUrl,
    String data,
    String? mimeType,
    String? encoding,
    String? historyUrl,
  ) {
    return _host.invoke<void>('WebView.loadDataWithBaseUrl', <String, Object?>{
      'instanceId': instanceId,
      'baseUrl': baseUrl,
      'data': data,
      'mimeType': mimeType,
      'encoding': encoding,
      'historyUrl': historyUrl,
    });
  }

  Future<void> loadUrl(
    int instanceId,
    String url,
    Map<String, String> headers,
  ) {
    return _host.invoke<void>('WebView.loadUrl', <String, Object?>{
      'instanceId': instanceId,
      'url': url,
      'headers': headers,
    });
  }

  Future<void> postUrl(int instanceId, String url, Uint8List data) {
    return _host.invoke<void>('WebView.postUrl', <String, Object?>{
      'instanceId': instanceId,
      'url': url,
      'data': data,
    });
  }

  Future<String?> getUrl(int instanceId) {
    return _host.invoke<String>('WebView.getUrl', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<bool> canGoBack(int instanceId) async {
    return await _host.invoke<bool>('WebView.canGoBack', <String, Object?>{
          'instanceId': instanceId,
        }) ??
        false;
  }

  Future<bool> canGoForward(int instanceId) async {
    return await _host.invoke<bool>('WebView.canGoForward', <String, Object?>{
          'instanceId': instanceId,
        }) ??
        false;
  }

  Future<void> goBack(int instanceId) {
    return _host.invoke<void>('WebView.goBack', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> goForward(int instanceId) {
    return _host.invoke<void>('WebView.goForward', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> reload(int instanceId) {
    return _host.invoke<void>('WebView.reload', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> setDocumentStartScripts(int instanceId, List<String> scripts) {
    return _host.invoke<void>(
      'WebView.setDocumentStartScripts',
      <String, Object?>{'instanceId': instanceId, 'scripts': scripts},
    );
  }

  Future<void> clearCache(int instanceId, bool includeDiskFiles) {
    return _host.invoke<void>('WebView.clearCache', <String, Object?>{
      'instanceId': instanceId,
      'includeDiskFiles': includeDiskFiles,
    });
  }

  Future<String?> evaluateJavascript(int instanceId, String javascriptString) {
    return _host.invoke<String>('WebView.evaluateJavascript', <String, Object?>{
      'instanceId': instanceId,
      'javascriptString': javascriptString,
    });
  }

  Future<String?> getTitle(int instanceId) {
    return _host.invoke<String>('WebView.getTitle', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> scrollTo(int instanceId, int x, int y) {
    return _host.invoke<void>('WebView.scrollTo', <String, Object?>{
      'instanceId': instanceId,
      'x': x,
      'y': y,
    });
  }

  Future<void> scrollBy(int instanceId, int x, int y) {
    return _host.invoke<void>('WebView.scrollBy', <String, Object?>{
      'instanceId': instanceId,
      'x': x,
      'y': y,
    });
  }

  Future<int> getScrollX(int instanceId) async {
    return await _host.invoke<int>('WebView.getScrollX', <String, Object?>{
          'instanceId': instanceId,
        }) ??
        0;
  }

  Future<int> getScrollY(int instanceId) async {
    return await _host.invoke<int>('WebView.getScrollY', <String, Object?>{
          'instanceId': instanceId,
        }) ??
        0;
  }

  Future<WebViewPoint> getScrollPosition(int instanceId) async {
    return _decodePoint(
      await _host.invoke<Object>('WebView.getScrollPosition', <String, Object?>{
        'instanceId': instanceId,
      }),
    );
  }

  Future<void> setWebContentsDebuggingEnabled(bool enabled) {
    return _host.invoke<void>(
      'WebView.setWebContentsDebuggingEnabled',
      <String, Object?>{'enabled': enabled},
    );
  }

  Future<void> setWebViewClient(int instanceId, int webViewClientInstanceId) {
    return _host.invoke<void>('WebView.setWebViewClient', <String, Object?>{
      'instanceId': instanceId,
      'webViewClientInstanceId': webViewClientInstanceId,
    });
  }

  Future<void> addJavaScriptChannel(
    int instanceId,
    int javaScriptChannelInstanceId,
  ) {
    return _host.invoke<void>('WebView.addJavaScriptChannel', <String, Object?>{
      'instanceId': instanceId,
      'javaScriptChannelInstanceId': javaScriptChannelInstanceId,
    });
  }

  Future<void> removeJavaScriptChannel(
    int instanceId,
    int javaScriptChannelInstanceId,
  ) {
    return _host
        .invoke<void>('WebView.removeJavaScriptChannel', <String, Object?>{
          'instanceId': instanceId,
          'javaScriptChannelInstanceId': javaScriptChannelInstanceId,
        });
  }

  Future<void> setDownloadListener(int instanceId, int? listenerInstanceId) {
    return _host.invoke<void>('WebView.setDownloadListener', <String, Object?>{
      'instanceId': instanceId,
      'listenerInstanceId': listenerInstanceId,
    });
  }

  Future<void> setWebChromeClient(int instanceId, int? clientInstanceId) {
    return _host.invoke<void>('WebView.setWebChromeClient', <String, Object?>{
      'instanceId': instanceId,
      'clientInstanceId': clientInstanceId,
    });
  }
}

class WebSettingsHostApi {
  WebSettingsHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId, int webViewInstanceId) {
    return _host.invoke<void>('WebSettings.create', <String, Object?>{
      'instanceId': instanceId,
      'webViewInstanceId': webViewInstanceId,
    });
  }

  Future<void> setDomStorageEnabled(int instanceId, bool flag) =>
      _setting('setDomStorageEnabled', instanceId, flag);

  Future<void> setJavaScriptCanOpenWindowsAutomatically(
    int instanceId,
    bool flag,
  ) => _setting('setJavaScriptCanOpenWindowsAutomatically', instanceId, flag);

  Future<void> setSupportMultipleWindows(int instanceId, bool support) =>
      _setting('setSupportMultipleWindows', instanceId, support);

  Future<void> setBackgroundColor(int instanceId, int color) =>
      _setting('setBackgroundColor', instanceId, color);

  Future<void> setJavaScriptEnabled(int instanceId, bool flag) =>
      _setting('setJavaScriptEnabled', instanceId, flag);

  Future<void> setUserAgentString(int instanceId, String? userAgentString) {
    return _host.invoke<void>(
      'WebSettings.setUserAgentString',
      <String, Object?>{'instanceId': instanceId, 'value': userAgentString},
    );
  }

  Future<void> setMediaPlaybackRequiresUserGesture(
    int instanceId,
    bool require,
  ) => _setting('setMediaPlaybackRequiresUserGesture', instanceId, require);

  Future<void> setSupportZoom(int instanceId, bool support) =>
      _setting('setSupportZoom', instanceId, support);

  Future<void> setLoadWithOverviewMode(int instanceId, bool overview) =>
      _setting('setLoadWithOverviewMode', instanceId, overview);

  Future<void> setUseWideViewPort(int instanceId, bool use) =>
      _setting('setUseWideViewPort', instanceId, use);

  Future<void> setDisplayZoomControls(int instanceId, bool enabled) =>
      _setting('setDisplayZoomControls', instanceId, enabled);

  Future<void> setBuiltInZoomControls(int instanceId, bool enabled) =>
      _setting('setBuiltInZoomControls', instanceId, enabled);

  Future<void> setAllowFileAccess(int instanceId, bool enabled) =>
      _setting('setAllowFileAccess', instanceId, enabled);

  Future<void> setMixedContentMode(int instanceId, String mode) =>
      _setting('setMixedContentMode', instanceId, mode);

  Future<void> setTextZoom(int instanceId, int textZoom) =>
      _setting('setTextZoom', instanceId, textZoom);

  Future<String> getUserAgentString(int instanceId) async {
    return await _host.invoke<String>(
          'WebSettings.getUserAgentString',
          <String, Object?>{'instanceId': instanceId},
        ) ??
        '';
  }

  Future<void> setAllowFullScreenRotate(int instanceId, bool enabled) =>
      _setting('setAllowFullScreenRotate', instanceId, enabled);

  Future<void> _setting(String method, int instanceId, Object? value) {
    return _host.invoke<void>('WebSettings.$method', <String, Object?>{
      'instanceId': instanceId,
      'value': value,
    });
  }
}

class JavaScriptChannelHostApi {
  JavaScriptChannelHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId, String channelName) {
    return _host.invoke<void>('JavaScriptChannel.create', <String, Object?>{
      'instanceId': instanceId,
      'channelName': channelName,
    });
  }
}

class WebViewClientHostApi {
  WebViewClientHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId) {
    return _host.invoke<void>('WebViewClient.create', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> setSynchronousReturnValueForShouldOverrideUrlLoading(
    int instanceId,
    bool value,
  ) {
    return _host.invoke<void>(
      'WebViewClient.setSynchronousReturnValueForShouldOverrideUrlLoading',
      <String, Object?>{'instanceId': instanceId, 'value': value},
    );
  }
}

class DownloadListenerHostApi {
  DownloadListenerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId) {
    return _host.invoke<void>('DownloadListener.create', <String, Object?>{
      'instanceId': instanceId,
    });
  }
}

class WebChromeClientHostApi {
  WebChromeClientHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId) {
    return _host.invoke<void>('WebChromeClient.create', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> setSynchronousReturnValueForOnShowFileChooser(
    int instanceId,
    bool value,
  ) => _setReturn(
    'setSynchronousReturnValueForOnShowFileChooser',
    instanceId,
    value,
  );

  Future<void> setSynchronousReturnValueForOnConsoleMessage(
    int instanceId,
    bool value,
  ) => _setReturn(
    'setSynchronousReturnValueForOnConsoleMessage',
    instanceId,
    value,
  );

  Future<void> setSynchronousReturnValueForOnJsAlert(
    int instanceId,
    bool value,
  ) => _setReturn('setSynchronousReturnValueForOnJsAlert', instanceId, value);

  Future<void> setSynchronousReturnValueForOnJsConfirm(
    int instanceId,
    bool value,
  ) => _setReturn('setSynchronousReturnValueForOnJsConfirm', instanceId, value);

  Future<void> setSynchronousReturnValueForOnJsPrompt(
    int instanceId,
    bool value,
  ) => _setReturn('setSynchronousReturnValueForOnJsPrompt', instanceId, value);

  Future<void> _setReturn(String method, int instanceId, bool value) {
    return _host.invoke<void>('WebChromeClient.$method', <String, Object?>{
      'instanceId': instanceId,
      'value': value,
    });
  }
}

class FlutterAssetManagerHostApi {
  FlutterAssetManagerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<List<String?>> list(String path) async {
    return _stringList(
      await _host.invoke<Object>('FlutterAssetManager.list', <String, Object?>{
        'path': path,
      }),
    );
  }

  Future<String> getAssetFilePathByName(String name) async {
    return await _host.invoke<String>(
          'FlutterAssetManager.getAssetFilePathByName',
          <String, Object?>{'name': name},
        ) ??
        '';
  }
}

class WebStorageHostApi {
  WebStorageHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> create(int instanceId) {
    return _host.invoke<void>('WebStorage.create', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> deleteAllData(int instanceId) {
    return _host.invoke<void>('WebStorage.deleteAllData', <String, Object?>{
      'instanceId': instanceId,
    });
  }
}

class PermissionRequestHostApi {
  PermissionRequestHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> grant(int instanceId, List<String?> resources) {
    return _host.invoke<void>('PermissionRequest.grant', <String, Object?>{
      'instanceId': instanceId,
      'resources': resources,
    });
  }

  Future<void> deny(int instanceId) {
    return _host.invoke<void>('PermissionRequest.deny', <String, Object?>{
      'instanceId': instanceId,
    });
  }
}

class CustomViewCallbackHostApi {
  CustomViewCallbackHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> onCustomViewHidden(int identifier) {
    return _host.invoke<void>(
      'CustomViewCallback.onCustomViewHidden',
      <String, Object?>{'identifier': identifier},
    );
  }
}

class GeolocationPermissionsCallbackHostApi {
  GeolocationPermissionsCallbackHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> invoke(int instanceId, String origin, bool allow, bool retain) {
    return _host.invoke<void>(
      'GeolocationPermissionsCallback.invoke',
      <String, Object?>{
        'instanceId': instanceId,
        'origin': origin,
        'allow': allow,
        'retain': retain,
      },
    );
  }
}

class HttpAuthHandlerHostApi {
  HttpAuthHandlerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<bool> useHttpAuthUsernamePassword(int instanceId) async {
    return await _host.invoke<bool>(
          'HttpAuthHandler.useHttpAuthUsernamePassword',
          <String, Object?>{'instanceId': instanceId},
        ) ??
        false;
  }

  Future<void> cancel(int instanceId) {
    return _host.invoke<void>('HttpAuthHandler.cancel', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> proceed(int instanceId, String username, String password) {
    return _host.invoke<void>('HttpAuthHandler.proceed', <String, Object?>{
      'instanceId': instanceId,
      'username': username,
      'password': password,
    });
  }
}

class SslAuthHandlerHostApi {
  SslAuthHandlerHostApi({BinaryMessenger? binaryMessenger})
    : _host = _HostChannel(binaryMessenger);

  final _HostChannel _host;

  Future<void> cancel(int instanceId) {
    return _host.invoke<void>('SslAuthHandler.cancel', <String, Object?>{
      'instanceId': instanceId,
    });
  }

  Future<void> proceed(int instanceId) {
    return _host.invoke<void>('SslAuthHandler.proceed', <String, Object?>{
      'instanceId': instanceId,
    });
  }
}

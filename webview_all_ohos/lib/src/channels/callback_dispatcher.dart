import 'package:flutter/services.dart';

import 'types.dart';
import 'api_implementations.dart';

const String _channelName = 'com.abandoft.webview_all_ohos/callback_api';

class OhosWebViewCallbackDispatcher {
  OhosWebViewCallbackDispatcher({BinaryMessenger? binaryMessenger})
    : _channel = MethodChannel(
        _channelName,
        const StandardMethodCodec(),
        binaryMessenger,
      );

  static OhosWebViewCallbackDispatcher instance =
      OhosWebViewCallbackDispatcher();

  final MethodChannel _channel;

  OhosWebViewFlutterApis? _apis;

  void setUp(OhosWebViewFlutterApis apis) {
    _apis = apis;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<Object?> _handleMethodCall(MethodCall call) async {
    final OhosWebViewFlutterApis apis =
        _apis ?? OhosWebViewFlutterApis.instance;
    final Map<Object?, Object?> args =
        (call.arguments as Map<Object?, Object?>?) ?? <Object?, Object?>{};

    switch (call.method) {
      case 'OhosObject.dispose':
        apis.ohosObjectFlutterApi.dispose(args.intValue('identifier'));
        return null;
      case 'WebView.create':
        apis.webViewFlutterApi.create(args.intValue('identifier'));
        return null;
      case 'WebView.onScrollChanged':
        apis.webViewFlutterApi.onScrollChanged(
          args.intValue('webViewInstanceId'),
          args.intValue('left'),
          args.intValue('top'),
          args.intValue('oldLeft'),
          args.intValue('oldTop'),
        );
        return null;
      case 'JavaScriptChannel.postMessage':
        final Object? sourceUrl = args['sourceUrl'];
        apis.javaScriptChannelFlutterApi.postMessage(
          args.intValue('instanceId'),
          args.stringValue('message'),
          sourceUrl: sourceUrl is String && sourceUrl.isNotEmpty
              ? sourceUrl
              : null,
        );
        return null;
      case 'WebViewClient.onPageStarted':
        apis.webViewClientFlutterApi.onPageStarted(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.stringValue('url'),
        );
        return null;
      case 'WebViewClient.onPageFinished':
        apis.webViewClientFlutterApi.onPageFinished(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.stringValue('url'),
        );
        return null;
      case 'WebViewClient.onReceivedRequestError':
        apis.webViewClientFlutterApi.onReceivedRequestError(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          WebResourceRequestData.fromMessage(args['request']),
          WebResourceErrorData.fromMessage(args['error']),
        );
        return null;
      case 'WebViewClient.onReceivedHttpError':
        apis.webViewClientFlutterApi.onReceivedHttpError(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          WebResourceRequestData.fromMessage(args['request']),
          WebResourceResponseData.fromMessage(args['response']),
        );
        return null;
      case 'WebViewClient.onReceivedError':
        apis.webViewClientFlutterApi.onReceivedError(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.intValue('errorCode'),
          args.stringValue('description'),
          args.stringValue('failingUrl'),
        );
        return null;
      case 'WebViewClient.requestLoading':
        apis.webViewClientFlutterApi.requestLoading(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          WebResourceRequestData.fromMessage(args['request']),
        );
        return null;
      case 'WebViewClient.urlLoading':
        apis.webViewClientFlutterApi.urlLoading(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.stringValue('url'),
        );
        return null;
      case 'WebViewClient.doUpdateVisitedHistory':
        apis.webViewClientFlutterApi.doUpdateVisitedHistory(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.stringValue('url'),
          args.boolValue('isReload'),
        );
        return null;
      case 'WebViewClient.onReceivedHttpAuthRequest':
        apis.webViewClientFlutterApi.onReceivedHttpAuthRequest(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.intValue('httpAuthHandlerInstanceId'),
          args.stringValue('host'),
          args.stringValue('realm'),
        );
        return null;
      case 'WebViewClient.onReceivedSslAuthError':
        apis.webViewClientFlutterApi.onReceivedSslAuthError(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.intValue('sslAuthHandlerInstanceId'),
          args.stringValue('url'),
          args.intValue('errorCode'),
          args.stringValue('description'),
        );
        return null;
      case 'DownloadListener.onDownloadStart':
        apis.downloadListenerFlutterApi.onDownloadStart(
          args.intValue('instanceId'),
          args.stringValue('url'),
          args.stringValue('userAgent'),
          args.stringValue('contentDisposition'),
          args.stringValue('mimetype'),
          args.intValue('contentLength'),
        );
        return null;
      case 'WebChromeClient.onProgressChanged':
        apis.webChromeClientFlutterApi.onProgressChanged(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.intValue('progress'),
        );
        return null;
      case 'WebChromeClient.onShowFileChooser':
        return apis.webChromeClientFlutterApi.onShowFileChooser(
          args.intValue('instanceId'),
          args.intValue('webViewInstanceId'),
          args.intValue('paramsInstanceId'),
        );
      case 'WebChromeClient.onPermissionRequest':
        apis.webChromeClientFlutterApi.onPermissionRequest(
          args.intValue('instanceId'),
          args.intValue('requestInstanceId'),
        );
        return null;
      case 'WebChromeClient.onShowCustomView':
        apis.webChromeClientFlutterApi.onShowCustomView(
          args.intValue('instanceId'),
          args.intValue('viewIdentifier'),
          args.intValue('callbackIdentifier'),
        );
        return null;
      case 'WebChromeClient.onHideCustomView':
        apis.webChromeClientFlutterApi.onHideCustomView(
          args.intValue('instanceId'),
        );
        return null;
      case 'WebChromeClient.onGeolocationPermissionsShowPrompt':
        apis.webChromeClientFlutterApi.onGeolocationPermissionsShowPrompt(
          args.intValue('instanceId'),
          args.intValue('paramsInstanceId'),
          args.stringValue('origin'),
        );
        return null;
      case 'WebChromeClient.onGeolocationPermissionsHidePrompt':
        apis.webChromeClientFlutterApi.onGeolocationPermissionsHidePrompt(
          args.intValue('identifier'),
        );
        return null;
      case 'WebChromeClient.onConsoleMessage':
        apis.webChromeClientFlutterApi.onConsoleMessage(
          args.intValue('instanceId'),
          ConsoleMessage.fromMessage(args['message']),
        );
        return null;
      case 'WebChromeClient.onJsAlert':
        await apis.webChromeClientFlutterApi.onJsAlert(
          args.intValue('instanceId'),
          args.stringValue('url'),
          args.stringValue('message'),
        );
        return null;
      case 'WebChromeClient.onJsConfirm':
        return apis.webChromeClientFlutterApi.onJsConfirm(
          args.intValue('instanceId'),
          args.stringValue('url'),
          args.stringValue('message'),
        );
      case 'WebChromeClient.onJsPrompt':
        return apis.webChromeClientFlutterApi.onJsPrompt(
          args.intValue('instanceId'),
          args.stringValue('url'),
          args.stringValue('message'),
          args.stringValue('defaultValue'),
        );
      case 'FileChooserParams.create':
        apis.fileChooserParamsFlutterApi.create(
          args.intValue('instanceId'),
          args.boolValue('isCaptureEnabled'),
          (args['acceptTypes'] as List<Object?>).cast<String?>(),
          FileChooserMode.values[args.intValue('mode')],
          args['filenameHint'] as String?,
        );
        return null;
      case 'PermissionRequest.create':
        apis.permissionRequestFlutterApi.create(
          args.intValue('identifier'),
          (args['resources'] as List<Object?>).cast<String?>(),
        );
        return null;
      case 'CustomViewCallback.create':
        apis.customViewCallbackFlutterApi.create(args.intValue('identifier'));
        return null;
      case 'View.create':
        apis.viewFlutterApi.create(args.intValue('identifier'));
        return null;
      case 'GeolocationPermissionsCallback.create':
        apis.geolocationPermissionsCallbackFlutterApi.create(
          args.intValue('instanceId'),
        );
        return null;
      case 'HttpAuthHandler.create':
        apis.httpAuthHandlerFlutterApi.create(args.intValue('instanceId'));
        return null;
      case 'SslAuthHandler.create':
        apis.sslAuthHandlerFlutterApi.create(args.intValue('instanceId'));
        return null;
    }

    throw MissingPluginException(
      'Unknown OHOS WebView callback: ${call.method}',
    );
  }
}

extension _MessageArgs on Map<Object?, Object?> {
  int intValue(String key) => this[key]! as int;
  bool boolValue(String key) => this[key]! as bool;
  String stringValue(String key) => this[key]! as String;
}

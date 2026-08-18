// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'windows_webview_types.dart' as native_types;
import 'windows_webview_native.dart' as native_webview;

const Duration _pendingWebView2RequestTimeout = Duration(seconds: 30);

String _singleLineWindowsLogValue(Object value) {
  return value.toString().replaceAll(RegExp(r'[\r\n]+'), ' ');
}

String _createWindowsVirtualHost(String prefix) {
  final Random random = Random.secure();
  final String token = List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    growable: false,
  ).join();
  return '$prefix-$token.webview.invalid';
}

Future<void> _disposeFinalizedWindowsWebView(
  native_webview.WebviewController controller,
) async {
  try {
    await controller.dispose();
  } catch (_) {
    // The Flutter engine can already be detached when a finalizer runs.
    return;
  }
}

/// Windows-specific policy for popup windows.
enum WindowsPopupWindowPolicy {
  /// Allow popups to open separate windows.
  allow,

  /// Suppress popup windows.
  deny,

  /// Open popup content in the current window.
  sameWindow,
}

/// Creation parameters for [WindowsWebViewController].
@immutable
class WindowsWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Creates a new [WindowsWebViewControllerCreationParams].
  const WindowsWebViewControllerCreationParams({
    this.popupWindowPolicy = WindowsPopupWindowPolicy.sameWindow,
  });

  /// Creates a [WindowsWebViewControllerCreationParams] from generic params.
  const WindowsWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params, {
    this.popupWindowPolicy = WindowsPopupWindowPolicy.sameWindow,
  });

  /// How popup windows should be handled.
  final WindowsPopupWindowPolicy popupWindowPolicy;
}

/// Windows-specific creation parameters for [WindowsWebViewWidget].
@immutable
class WindowsWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  /// Creates a new [WindowsWebViewWidgetCreationParams].
  const WindowsWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
    this.scaleFactor,
    this.filterQuality = FilterQuality.none,
  });

  /// Creates a [WindowsWebViewWidgetCreationParams] from generic params.
  WindowsWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params, {
    double? scaleFactor,
    FilterQuality filterQuality = FilterQuality.none,
  }) : this(
         key: params.key,
         controller: params.controller,
         layoutDirection: params.layoutDirection,
         gestureRecognizers: params.gestureRecognizers,
         scaleFactor: scaleFactor,
         filterQuality: filterQuality,
       );

  /// Optional rasterization scale factor.
  final double? scaleFactor;

  /// Filter quality for the underlying texture.
  final FilterQuality filterQuality;
}

/// Creation parameters for [WindowsNavigationDelegate].
@immutable
class WindowsNavigationDelegateCreationParams
    extends PlatformNavigationDelegateCreationParams {
  /// Creates a new [WindowsNavigationDelegateCreationParams].
  const WindowsNavigationDelegateCreationParams();

  /// Creates a [WindowsNavigationDelegateCreationParams] from generic params.
  const WindowsNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
    PlatformNavigationDelegateCreationParams params,
  );
}

/// A WebView2-backed implementation of [PlatformWebViewController].
class WindowsWebViewController extends PlatformWebViewController {
  /// Creates a [WindowsWebViewController].
  WindowsWebViewController(PlatformWebViewControllerCreationParams params)
    : _webviewController = native_webview.WebviewController(),
      super.implementation(
        params is WindowsWebViewControllerCreationParams
            ? params
            : WindowsWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
                params,
              ),
      ) {
    final WeakReference<WindowsWebViewController> weakThis =
        WeakReference<WindowsWebViewController>(this);
    _setInitializationFuture(_initialize(weakThis));
    _finalizer.attach(this, _webviewController, detach: this);
  }

  static final Finalizer<native_webview.WebviewController> _finalizer =
      Finalizer<native_webview.WebviewController>((
        native_webview.WebviewController controller,
      ) {
        unawaited(_disposeFinalizedWindowsWebView(controller));
      });

  final native_webview.WebviewController _webviewController;
  final Map<String, JavaScriptChannelParams> _javaScriptChannelParams =
      <String, JavaScriptChannelParams>{};
  final Map<String, String> _javaScriptChannelScriptIds = <String, String>{};
  final Map<String, String> _virtualHostMappings = <String, String>{};
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  Future<void>? _initializationFuture;
  Future<void>? _disposeFuture;
  bool _isDisposed = false;
  WindowsNavigationDelegate? _currentNavigationDelegate;
  Future<void> Function(bool enabled)? _navigationRequestListener;
  final String _fileVirtualHost = _createWindowsVirtualHost('app-file');
  final String _assetVirtualHost = _createWindowsVirtualHost('flutter-assets');
  String? _currentUrl;
  String? _pageStartedUrl;
  String? _title;
  String? _userAgent;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _verticalScrollBarEnabled = true;
  bool _horizontalScrollBarEnabled = true;
  WebViewOverScrollMode _overScrollMode = WebViewOverScrollMode.always;
  bool _scrollBridgeInstalled = false;
  String? _consoleBridgeScriptId;
  String? _scrollBarStyleScriptId;
  String? _overScrollStyleScriptId;

  void Function(JavaScriptConsoleMessage)? _onConsoleMessageCallback;
  Future<void> Function(JavaScriptAlertDialogRequest)?
  _onJavaScriptAlertDialogCallback;
  Future<bool> Function(JavaScriptConfirmDialogRequest)?
  _onJavaScriptConfirmDialogCallback;
  Future<String> Function(JavaScriptTextInputDialogRequest)?
  _onJavaScriptTextInputDialogCallback;
  void Function(ScrollPositionChange)? _onScrollPositionChangeCallback;
  void Function(PlatformWebViewPermissionRequest)?
  _onPlatformPermissionRequestCallback;

  WindowsWebViewControllerCreationParams get _windowsParams =>
      params as WindowsWebViewControllerCreationParams;

  static const String _channelMessageType = '__windows_webview_all_type';
  static const String _javaScriptChannelMessageType = 'javascriptChannel';
  static const String _consoleMessageType = 'consoleMessage';
  static const String _scrollMessageType = 'scrollPositionChange';

  Future<T> _awaitPendingRequest<T>(
    Future<T> Function() decision, {
    required T fallback,
    required String requestName,
  }) async {
    try {
      return await decision().timeout(
        _pendingWebView2RequestTimeout,
        onTimeout: () {
          debugPrint(
            'webview_all_windows: $requestName did not complete within '
            '${_pendingWebView2RequestTimeout.inSeconds} seconds; the safe '
            'default was used.',
          );
          return fallback;
        },
      );
    } catch (error) {
      debugPrint(
        'webview_all_windows: $requestName failed; the safe default was used: '
        '${_singleLineWindowsLogValue(error)}',
      );
      return fallback;
    }
  }

  /// Explicitly initializes the shared WebView2 environment.
  static Future<void> initializeEnvironment({
    String? userDataPath,
    String? browserExePath,
    String? additionalArguments,
  }) {
    return native_webview.WebviewController.initializeEnvironment(
      userDataPath: userDataPath,
      browserExePath: browserExePath,
      additionalArguments: additionalArguments,
    );
  }

  /// Returns the installed WebView2 runtime version, if available.
  static Future<String?> getWebViewVersion() {
    return native_webview.WebviewController.getWebViewVersion();
  }

  Future<void> _initialize(
    WeakReference<WindowsWebViewController> weakThis,
  ) async {
    await _webviewController.initialize();
    _throwIfDisposed();
    _webviewController.setNavigationRequestedDelegate((
      String url,
      bool isUserInitiated,
      bool isRedirected,
    ) async {
      return weakThis.target?._shouldNavigate(url) ?? false;
    });
    _webviewController.setJavaScriptDialogRequestedDelegate((
      String dialogType,
      String url,
      String message,
      String? defaultText,
    ) {
      return weakThis.target?._handleJavaScriptDialogRequested(
        dialogType,
        url,
        message,
        defaultText,
      );
    });
    _webviewController.setHttpAuthRequestedDelegate((
      String url,
      String challenge,
    ) {
      return weakThis.target?._handleHttpAuthRequested(url, challenge);
    });
    _webviewController.setSslAuthErrorRequestedDelegate((
      String url,
      int errorStatus,
    ) {
      return weakThis.target?._handleSslAuthError(url, errorStatus);
    });
    await _webviewController.setPopupWindowPolicy(
      switch (_windowsParams.popupWindowPolicy) {
        WindowsPopupWindowPolicy.allow =>
          native_types.WebviewPopupWindowPolicy.allow,
        WindowsPopupWindowPolicy.deny =>
          native_types.WebviewPopupWindowPolicy.deny,
        WindowsPopupWindowPolicy.sameWindow =>
          native_types.WebviewPopupWindowPolicy.sameWindow,
      },
    );
    _throwIfDisposed();

    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _webviewController.url.listen((String url) {
        weakThis.target?._handleUrlChanged(url);
      }),
      _webviewController.title.listen((String title) {
        weakThis.target?._title = title;
      }),
      _webviewController.historyChanged.listen((
        native_webview.HistoryChanged value,
      ) {
        final WindowsWebViewController? target = weakThis.target;
        target?._canGoBack = value.canGoBack;
        target?._canGoForward = value.canGoForward;
      }),
      _webviewController.loadingState.listen((native_types.LoadingState state) {
        weakThis.target?._handleLoadingStateChanged(state);
      }),
      _webviewController.onLoadError.listen((
        native_types.WebErrorStatus status,
      ) {
        weakThis.target?._handleLoadError(status);
      }),
      _webviewController.httpResponseError.listen((
        native_webview.WebviewHttpResponseError error,
      ) {
        weakThis.target?._handleHttpResponseError(error);
      }),
      _webviewController.webMessage.listen((dynamic message) {
        weakThis.target?._handleWebMessage(message);
      }),
    ]);
  }

  Future<void> _ensureInitialized() async {
    _throwIfDisposed();
    await _initializationFuture!;
    _throwIfDisposed();
  }

  Future<void> _retryInitialization() {
    if (_isDisposed) {
      return Future<void>.error(_disposedStateError());
    }
    final Future<void> initializationFuture = _prepareRetry();
    _setInitializationFuture(initializationFuture);
    return initializationFuture;
  }

  void _setInitializationFuture(Future<void> future) {
    _initializationFuture = future;
    unawaited(future.catchError((Object _) {}));
  }

  Future<void> _prepareRetry() async {
    final List<StreamSubscription<dynamic>> subscriptions =
        List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    await Future.wait<void>(
      subscriptions.map(
        (StreamSubscription<dynamic> subscription) => subscription.cancel(),
      ),
    );
    _throwIfDisposed();
    await _initialize(WeakReference<WindowsWebViewController>(this));
  }

  StateError _disposedStateError() {
    return StateError('This Windows WebView controller has been disposed.');
  }

  void _throwIfDisposed() {
    if (_isDisposed) {
      throw _disposedStateError();
    }
  }

  /// Permanently releases this controller and its native WebView2 resources.
  ///
  /// Removing a WebView widget does not call this method because controllers
  /// can be detached and mounted again. Call this when the controller will no
  /// longer be used. A disposed controller cannot be reused.
  ///
  /// Repeated calls return the same cleanup operation.
  Future<void> dispose() {
    final Future<void>? existingFuture = _disposeFuture;
    if (existingFuture != null) {
      return existingFuture;
    }

    _isDisposed = true;
    _finalizer.detach(this);
    final Future<void> Function(bool enabled)? listener =
        _navigationRequestListener;
    if (listener != null) {
      _currentNavigationDelegate?._removeNavigationRequestListener(listener);
    }
    _navigationRequestListener = null;
    _currentNavigationDelegate = null;
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    // Initialization errors are reported by the operation that initialized the
    // controller. Disposal still has to release every resource created before
    // that failure, without reporting the same initialization error again.
    try {
      await _initializationFuture;
    } catch (_) {
      // Continue with cleanup.
    }

    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    final List<StreamSubscription<dynamic>> subscriptions =
        List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    try {
      await Future.wait<void>(
        subscriptions.map(
          (StreamSubscription<dynamic> subscription) => subscription.cancel(),
        ),
        eagerError: false,
      );
    } catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
    }

    _webviewController.setNavigationRequestedDelegate(null);
    _webviewController.setJavaScriptDialogRequestedDelegate(null);
    _webviewController.setHttpAuthRequestedDelegate(null);
    _webviewController.setSslAuthErrorRequestedDelegate(null);
    _webviewController.setPermissionRequestedDelegate(null);
    try {
      await _webviewController.dispose();
    } catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
    }

    _javaScriptChannelParams.clear();
    _javaScriptChannelScriptIds.clear();
    _virtualHostMappings.clear();
    _onConsoleMessageCallback = null;
    _onJavaScriptAlertDialogCallback = null;
    _onJavaScriptConfirmDialogCallback = null;
    _onJavaScriptTextInputDialogCallback = null;
    _onScrollPositionChangeCallback = null;
    _onPlatformPermissionRequestCallback = null;
    _consoleBridgeScriptId = null;
    _scrollBarStyleScriptId = null;
    _overScrollStyleScriptId = null;

    if (cleanupError != null) {
      Error.throwWithStackTrace(
        cleanupError,
        cleanupStackTrace ?? StackTrace.current,
      );
    }
  }

  Future<void> _openWebView2DownloadPage() {
    return native_webview.WebviewController.openWebView2DownloadPage();
  }

  void _handleUrlChanged(String url) {
    _currentUrl = url;
    _pageStartedUrl ??= url;
    _currentNavigationDelegate?._onUrlChange?.call(UrlChange(url: url));
  }

  void _handleLoadingStateChanged(native_types.LoadingState state) {
    switch (state) {
      case native_types.LoadingState.none:
        break;
      case native_types.LoadingState.loading:
        final url = _currentUrl ?? _pageStartedUrl ?? '';
        _pageStartedUrl = url;
        _currentNavigationDelegate?._onProgress?.call(0);
        _currentNavigationDelegate?._onPageStarted?.call(url);
        break;
      case native_types.LoadingState.navigationCompleted:
        final url = _currentUrl ?? _pageStartedUrl ?? '';
        _currentNavigationDelegate?._onProgress?.call(100);
        _currentNavigationDelegate?._onPageFinished?.call(url);
        _pageStartedUrl = null;
        break;
    }
  }

  void _handleLoadError(native_types.WebErrorStatus status) {
    _currentNavigationDelegate?._onWebResourceError?.call(
      WindowsWebResourceError(status, url: _currentUrl, isForMainFrame: true),
    );
  }

  void _handleHttpResponseError(native_webview.WebviewHttpResponseError error) {
    final Uri? uri = Uri.tryParse(error.url);
    _currentNavigationDelegate?._onHttpError?.call(
      HttpResponseError(
        request: uri == null
            ? null
            : WindowsWebResourceRequest._(
                uri: uri,
                method: error.method,
                headers: error.requestHeaders,
              ),
        response: WindowsWebResourceResponse._(
          uri: uri,
          statusCode: error.statusCode,
          headers: error.responseHeaders,
          reasonPhrase: error.reasonPhrase,
          mimeType: _mimeTypeFromResponseHeaders(error.responseHeaders),
        ),
      ),
    );
  }

  void _handleWebMessage(dynamic message) {
    if (message is! Map) {
      return;
    }

    final type = message[_channelMessageType] as String?;
    switch (type) {
      case _javaScriptChannelMessageType:
        final channelName = message['channelName'] as String?;
        final params = channelName == null
            ? null
            : _javaScriptChannelParams[channelName];
        if (params != null) {
          params.onMessageReceived(
            JavaScriptMessage(message: '${message['message'] ?? ''}'),
          );
        }
        break;
      case _consoleMessageType:
        final callback = _onConsoleMessageCallback;
        if (callback != null) {
          callback(
            JavaScriptConsoleMessage(
              level: _parseJavaScriptLogLevel(message['level'] as String?),
              message: '${message['message'] ?? ''}',
            ),
          );
        }
        break;
      case _scrollMessageType:
        final callback = _onScrollPositionChangeCallback;
        if (callback != null) {
          callback(
            ScrollPositionChange(
              (message['x'] as num?)?.toDouble() ?? 0.0,
              (message['y'] as num?)?.toDouble() ?? 0.0,
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  Future<Map<String, Object?>?> _handleJavaScriptDialogRequested(
    String dialogType,
    String url,
    String message,
    String? defaultText,
  ) async {
    switch (dialogType) {
      case 'alert':
        final callback = _onJavaScriptAlertDialogCallback;
        if (callback == null) {
          return null;
        }
        return _awaitPendingRequest<Map<String, Object?>?>(
          () =>
              callback(
                JavaScriptAlertDialogRequest(message: message, url: url),
              ).then<Map<String, Object?>?>(
                (_) => <String, Object?>{'action': 'accept'},
              ),
          fallback: null,
          requestName: 'JavaScript alert callback',
        );
      case 'confirm':
        final callback = _onJavaScriptConfirmDialogCallback;
        if (callback == null) {
          return null;
        }
        return _awaitPendingRequest<Map<String, Object?>?>(
          () =>
              callback(
                JavaScriptConfirmDialogRequest(message: message, url: url),
              ).then<Map<String, Object?>?>(
                (bool confirmed) => <String, Object?>{
                  'action': confirmed ? 'confirm' : 'cancel',
                },
              ),
          fallback: null,
          requestName: 'JavaScript confirm callback',
        );
      case 'prompt':
        final callback = _onJavaScriptTextInputDialogCallback;
        if (callback == null) {
          return null;
        }
        return _awaitPendingRequest<Map<String, Object?>?>(
          () =>
              callback(
                JavaScriptTextInputDialogRequest(
                  message: message,
                  url: url,
                  defaultText: defaultText,
                ),
              ).then<Map<String, Object?>?>(
                (String text) => <String, Object?>{
                  'action': 'confirm',
                  'text': text,
                },
              ),
          fallback: null,
          requestName: 'JavaScript prompt callback',
        );
    }

    return null;
  }

  Future<Map<String, Object?>?> _handleHttpAuthRequested(
    String url,
    String challenge,
  ) async {
    final callback = _currentNavigationDelegate?._onHttpAuthRequest;
    if (callback == null) {
      return <String, Object?>{'action': 'cancel'};
    }

    final completer = Completer<Map<String, Object?>>();
    final Uri? uri = Uri.tryParse(url);
    try {
      callback(
        HttpAuthRequest(
          host: uri?.host ?? url,
          realm: _parseHttpAuthRealm(challenge),
          onProceed: (WebViewCredential credential) {
            if (completer.isCompleted) {
              return;
            }
            completer.complete(<String, Object?>{
              'action': 'proceed',
              'user': credential.user,
              'password': credential.password,
            });
          },
          onCancel: () {
            if (!completer.isCompleted) {
              completer.complete(<String, Object?>{'action': 'cancel'});
            }
          },
        ),
      );
    } catch (error) {
      if (completer.isCompleted) {
        debugPrint(
          'webview_all_windows: HTTP authentication callback failed after '
          'completing its decision; the completed decision was preserved: '
          '${_singleLineWindowsLogValue(error)}',
        );
        return completer.future;
      }
      debugPrint(
        'webview_all_windows: HTTP authentication callback failed; the request '
        'was canceled: ${_singleLineWindowsLogValue(error)}',
      );
      return <String, Object?>{'action': 'cancel'};
    }
    return _awaitPendingRequest<Map<String, Object?>>(
      () => completer.future,
      fallback: <String, Object?>{'action': 'cancel'},
      requestName: 'HTTP authentication callback',
    );
  }

  String? _parseHttpAuthRealm(String challenge) {
    final match = RegExp(
      r'realm=(?:"([^"]*)"|([^,\s]+))',
      caseSensitive: false,
    ).firstMatch(challenge);
    return match?.group(1) ?? match?.group(2);
  }

  String? _mimeTypeFromResponseHeaders(Map<String, String> headers) {
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.toLowerCase() != 'content-type') {
        continue;
      }
      final String mimeType = header.value
          .split(';')
          .first
          .trim()
          .toLowerCase();
      return mimeType.isEmpty ? null : mimeType;
    }
    return null;
  }

  Future<Map<String, Object?>?> _handleSslAuthError(
    String url,
    int errorStatus,
  ) async {
    final callback = _currentNavigationDelegate?._onSslAuthError;
    if (callback == null) {
      return <String, Object?>{'action': 'cancel'};
    }

    final completer = Completer<Map<String, Object?>>();
    final status = _webErrorStatusFromIndex(errorStatus);
    try {
      callback(
        WindowsPlatformSslAuthError(
          description: _sslAuthErrorDescription(url, status),
          onProceed: () async {
            if (!completer.isCompleted) {
              completer.complete(<String, Object?>{'action': 'proceed'});
            }
          },
          onCancel: () async {
            if (!completer.isCompleted) {
              completer.complete(<String, Object?>{'action': 'cancel'});
            }
          },
        ),
      );
    } catch (error) {
      if (completer.isCompleted) {
        debugPrint(
          'webview_all_windows: SSL authentication callback failed after '
          'completing its decision; the completed decision was preserved: '
          '${_singleLineWindowsLogValue(error)}',
        );
        return completer.future;
      }
      debugPrint(
        'webview_all_windows: SSL authentication callback failed; the request '
        'was canceled: ${_singleLineWindowsLogValue(error)}',
      );
      return <String, Object?>{'action': 'cancel'};
    }
    return _awaitPendingRequest<Map<String, Object?>>(
      () => completer.future,
      fallback: <String, Object?>{'action': 'cancel'},
      requestName: 'SSL authentication callback',
    );
  }

  native_types.WebErrorStatus _webErrorStatusFromIndex(int index) {
    if (index < 0 || index >= native_types.WebErrorStatus.values.length) {
      return native_types.WebErrorStatus.WebErrorStatusUnknown;
    }
    return native_types.WebErrorStatus.values[index];
  }

  String _sslAuthErrorDescription(
    String url,
    native_types.WebErrorStatus status,
  ) {
    return 'SSL certificate error for $url: ${status.name}.';
  }

  Future<void> _updateJavaScriptDialogCallbacksEnabled() {
    return _webviewController.setJavaScriptDialogCallbacksEnabled(
      alert: _onJavaScriptAlertDialogCallback != null,
      confirm: _onJavaScriptConfirmDialogCallback != null,
      prompt: _onJavaScriptTextInputDialogCallback != null,
    );
  }

  JavaScriptLogLevel _parseJavaScriptLogLevel(String? level) {
    switch (level) {
      case 'debug':
        return JavaScriptLogLevel.debug;
      case 'error':
        return JavaScriptLogLevel.error;
      case 'info':
        return JavaScriptLogLevel.info;
      case 'warning':
        return JavaScriptLogLevel.warning;
      default:
        return JavaScriptLogLevel.log;
    }
  }

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    await _ensureInitialized();
    if (!path.isAbsolute(absoluteFilePath)) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'File path must be absolute.',
      );
    }
    final file = File(absoluteFilePath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'File does not exist.',
      );
    }

    final String resolvedFilePath = file.resolveSymbolicLinksSync();
    final folderPath = path.dirname(resolvedFilePath);
    final fileName = path.basename(resolvedFilePath);
    final url = Uri(
      scheme: 'https',
      host: _fileVirtualHost,
      pathSegments: <String>[fileName],
    ).toString();
    if (!await _shouldNavigate(url)) {
      return;
    }
    await _setVirtualHostMapping(_fileVirtualHost, folderPath);
    await _webviewController.loadUrl(url);
  }

  @override
  Future<void> loadFileWithParams(LoadFileParams params) {
    return loadFile(params.absoluteFilePath);
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    await _ensureInitialized();
    final List<String> assetSegments = _validateFlutterAssetKey(key);
    final String assetRootPath = _flutterAssetsRootPath();
    final assetPath = path.joinAll(<String>[assetRootPath, ...assetSegments]);
    final file = File(assetPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(key, 'key', 'Asset for key "$key" not found.');
    }

    final String resolvedRootPath = Directory(
      assetRootPath,
    ).resolveSymbolicLinksSync();
    final String resolvedAssetPath = file.resolveSymbolicLinksSync();
    if (!path.isWithin(resolvedRootPath, resolvedAssetPath)) {
      throw ArgumentError.value(
        key,
        'key',
        'Asset path resolves outside the Flutter asset bundle.',
      );
    }

    final url = Uri(
      scheme: 'https',
      host: _assetVirtualHost,
      pathSegments: assetSegments,
    ).toString();
    if (!await _shouldNavigate(url)) {
      return;
    }
    await _setVirtualHostMapping(_assetVirtualHost, resolvedRootPath);
    await _webviewController.loadUrl(url);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    await _ensureInitialized();
    await _clearManagedVirtualHostMappings();
    final content = baseUrl == null ? html : _injectBaseUrl(html, baseUrl);
    await _webviewController.loadStringContent(content);
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    await _ensureInitialized();
    if (!params.uri.hasScheme) {
      throw ArgumentError(
        'LoadRequestParams#uri is required to have a scheme.',
      );
    }

    if (!await _shouldNavigate(params.uri.toString())) {
      return;
    }

    await _webviewController.loadRequest(
      url: params.uri.toString(),
      method: params.method.serialize(),
      headers: _serializeRequestHeaders(params.headers),
      body: params.body,
    );
  }

  @override
  Future<String?> currentUrl() async {
    await _ensureInitialized();
    return _currentUrl;
  }

  @override
  Future<bool> canGoBack() async {
    await _ensureInitialized();
    return _canGoBack;
  }

  @override
  Future<bool> canGoForward() async {
    await _ensureInitialized();
    return _canGoForward;
  }

  @override
  Future<void> goBack() async {
    await _ensureInitialized();
    await _webviewController.goBack();
  }

  @override
  Future<void> goForward() async {
    await _ensureInitialized();
    await _webviewController.goForward();
  }

  @override
  Future<void> reload() async {
    await _ensureInitialized();
    await _webviewController.reload();
  }

  @override
  Future<void> clearCache() async {
    await _ensureInitialized();
    await _webviewController.clearCache();
  }

  @override
  Future<void> clearLocalStorage() async {
    await _ensureInitialized();
    await _webviewController.clearLocalStorage();
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    await _ensureInitialized();
    final WindowsNavigationDelegate delegate =
        handler as WindowsNavigationDelegate;
    final Future<void> Function(bool enabled)? previousListener =
        _navigationRequestListener;
    if (previousListener != null) {
      _currentNavigationDelegate?._removeNavigationRequestListener(
        previousListener,
      );
    }

    _currentNavigationDelegate = delegate;
    final WeakReference<WindowsWebViewController> weakThis =
        WeakReference<WindowsWebViewController>(this);
    final Future<void> Function(bool enabled) listener = (bool enabled) async {
      final WindowsWebViewController? target = weakThis.target;
      if (target == null) {
        return;
      }
      try {
        await target._webviewController.setNavigationRequestCallbacksEnabled(
          enabled,
        );
      } catch (error) {
        debugPrint(
          'webview_all_windows: failed to update navigation request '
          'callbacks: ${_singleLineWindowsLogValue(error)}',
        );
        rethrow;
      }
    };
    _navigationRequestListener = listener;
    delegate._addNavigationRequestListener(listener);
    await _webviewController.setNavigationRequestCallbacksEnabled(
      delegate._onNavigationRequest != null,
    );
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    await _ensureInitialized();
    await _webviewController.executeScript(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    await _ensureInitialized();
    final dynamic result = await _webviewController.executeScript(javaScript);
    if (result == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }
    return result as Object;
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    await _ensureInitialized();
    final name = javaScriptChannelParams.name;
    if (name.isEmpty) {
      throw ArgumentError.value(
        name,
        'javaScriptChannelParams.name',
        'JavaScript channel name must not be empty.',
      );
    }
    if (_javaScriptChannelParams.containsKey(name)) {
      throw ArgumentError(
        'A JavaScriptChannel with name `$name` already exists.',
      );
    }

    _javaScriptChannelParams[name] = javaScriptChannelParams;
    final String encodedName = jsonEncode(name);
    final String script =
        '''
      (function() {
      const channelName = $encodedName;
      window[channelName] = {
        postMessage: function(message) {
          window.chrome.webview.postMessage({
            ${jsonEncode(_channelMessageType)}: ${jsonEncode(_javaScriptChannelMessageType)},
            "channelName": channelName,
            "message": String(message)
          });
        }
      };
      })();
    ''';
    final scriptId = await _webviewController
        .addScriptToExecuteOnDocumentCreated(script);
    if (scriptId != null) {
      _javaScriptChannelScriptIds[name] = scriptId;
    }
    await _executeScriptBestEffort('JavaScript channel "$name"', script);
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    await _ensureInitialized();
    _javaScriptChannelParams.remove(javaScriptChannelName);
    final scriptId = _javaScriptChannelScriptIds.remove(javaScriptChannelName);
    if (scriptId != null) {
      await _webviewController.removeScriptToExecuteOnDocumentCreated(scriptId);
    }
    await _executeScriptBestEffort(
      'JavaScript channel "$javaScriptChannelName" removal',
      'delete window[${jsonEncode(javaScriptChannelName)}];',
    );
  }

  @override
  Future<String?> getTitle() async {
    await _ensureInitialized();
    return _title;
  }

  @override
  Future<void> scrollTo(int x, int y) async {
    await runJavaScript('window.scrollTo($x, $y);');
  }

  @override
  Future<void> scrollBy(int x, int y) async {
    await runJavaScript('window.scrollBy($x, $y);');
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {
    await _ensureInitialized();
    if (_verticalScrollBarEnabled == enabled) {
      return;
    }

    _verticalScrollBarEnabled = enabled;
    await _updateScrollBarStyle();
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {
    await _ensureInitialized();
    if (_horizontalScrollBarEnabled == enabled) {
      return;
    }

    _horizontalScrollBarEnabled = enabled;
    await _updateScrollBarStyle();
  }

  @override
  bool supportsSetScrollBarsEnabled() {
    return true;
  }

  @override
  Future<Offset> getScrollPosition() async {
    final value = await runJavaScriptReturningResult(
      '({x: window.scrollX || window.pageXOffset || 0, '
      'y: window.scrollY || window.pageYOffset || 0})',
    );
    final position = value as Map<Object?, Object?>;
    return Offset(
      (position['x'] as num?)?.toDouble() ?? 0,
      (position['y'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    await _ensureInitialized();
    await _webviewController.setZoomControlEnabled(enabled);
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    await _ensureInitialized();
    await _webviewController.setBackgroundColor(color);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    await _ensureInitialized();
    await _webviewController.setJavaScriptEnabled(
      javaScriptMode == JavaScriptMode.unrestricted,
    );
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    await _ensureInitialized();
    _userAgent = userAgent;
    await _webviewController.setUserAgent(userAgent);
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    await _ensureInitialized();
    _onPlatformPermissionRequestCallback = onPermissionRequest;
    final WeakReference<WindowsWebViewController> weakThis =
        WeakReference<WindowsWebViewController>(this);
    _webviewController.setPermissionRequestedDelegate((
      String url,
      native_types.WebviewPermissionKind permissionKind,
      bool isUserInitiated,
    ) async {
      final WindowsWebViewController? target = weakThis.target;
      if (target == null) {
        return native_types.WebviewPermissionDecision.none;
      }
      final Set<WebViewPermissionResourceType> types = target
          ._toPermissionTypes(permissionKind);
      if (types.isEmpty) {
        return native_types.WebviewPermissionDecision.none;
      }
      final request = _WindowsWebViewPermissionRequest(types: types);
      try {
        target._onPlatformPermissionRequestCallback?.call(request);
      } catch (error) {
        if (request.decision.isCompleted) {
          debugPrint(
            'webview_all_windows: permission callback failed after completing '
            'its decision; the completed decision was preserved: '
            '${_singleLineWindowsLogValue(error)}',
          );
          return target
              ._awaitPendingRequest<native_types.WebviewPermissionDecision>(
                () => request.decision.future,
                fallback: native_types.WebviewPermissionDecision.deny,
                requestName: 'permission callback',
              );
        }
        debugPrint(
          'webview_all_windows: permission callback failed; the safe default '
          'was used: ${_singleLineWindowsLogValue(error)}',
        );
        return native_types.WebviewPermissionDecision.deny;
      }
      return target
          ._awaitPendingRequest<native_types.WebviewPermissionDecision>(
            () => request.decision.future,
            fallback: native_types.WebviewPermissionDecision.deny,
            requestName: 'permission callback',
          );
    });
  }

  @override
  Future<String?> getUserAgent() async {
    await _ensureInitialized();
    return _userAgent ?? await _webviewController.getUserAgent();
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    await _ensureInitialized();
    _onConsoleMessageCallback = onConsoleMessage;
    if (_consoleBridgeScriptId != null) {
      return;
    }

    final script =
        '''
      (function() {
        if (window.__flutterWindowsConsoleHookInstalled) {
          return;
        }
        window.__flutterWindowsConsoleHookInstalled = true;
        function stringifyArg(arg) {
          if (typeof arg === 'string') {
            return arg;
          }
          try {
            const json = JSON.stringify(arg);
            return json === undefined ? String(arg) : json;
          } catch (_) {
            return String(arg);
          }
        }
        function emit(level, args) {
          window.chrome.webview.postMessage({
            "$_channelMessageType": "$_consoleMessageType",
            "level": level,
            "message": Array.from(args).map(stringifyArg).join(' ')
          });
        }
        ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
          const original = console[level];
          console[level] = function() {
            emit(level === 'warn' ? 'warning' : level, arguments);
            if (original) {
              original.apply(console, arguments);
            }
          };
        });
      })();
    ''';
    _consoleBridgeScriptId = await _webviewController
        .addScriptToExecuteOnDocumentCreated(script);
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) async {
    await _ensureInitialized();
    _onScrollPositionChangeCallback = onScrollPositionChange;
    if (_scrollBridgeInstalled || onScrollPositionChange == null) {
      return;
    }

    _scrollBridgeInstalled = true;
    await _webviewController.addScriptToExecuteOnDocumentCreated('''
      (function() {
        if (window.__flutterWindowsScrollHookInstalled) {
          return;
        }
        window.__flutterWindowsScrollHookInstalled = true;
        window.addEventListener('scroll', function() {
          window.chrome.webview.postMessage({
            "$_channelMessageType": "$_scrollMessageType",
            "x": window.scrollX || window.pageXOffset || 0,
            "y": window.scrollY || window.pageYOffset || 0
          });
        }, { passive: true });
      })();
      ''');
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    await _ensureInitialized();
    _onJavaScriptAlertDialogCallback = onJavaScriptAlertDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    await _ensureInitialized();
    _onJavaScriptConfirmDialogCallback = onJavaScriptConfirmDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    await _ensureInitialized();
    _onJavaScriptTextInputDialogCallback = onJavaScriptTextInputDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    await _ensureInitialized();
    if (_overScrollMode == mode) {
      return;
    }

    _overScrollMode = mode;
    await _updateOverScrollStyle();
  }

  /// Opens the browser devtools for this WebView.
  Future<void> openDevTools() async {
    await _ensureInitialized();
    await _webviewController.openDevTools();
  }

  /// Suspends the WebView.
  Future<void> suspend() async {
    await _ensureInitialized();
    await _webviewController.suspend();
  }

  /// Resumes a suspended WebView.
  Future<void> resume() async {
    await _ensureInitialized();
    await _webviewController.resume();
  }

  /// Sets the popup policy for this WebView.
  Future<void> setPopupWindowPolicy(WindowsPopupWindowPolicy policy) async {
    await _ensureInitialized();
    await _webviewController.setPopupWindowPolicy(switch (policy) {
      WindowsPopupWindowPolicy.allow =>
        native_types.WebviewPopupWindowPolicy.allow,
      WindowsPopupWindowPolicy.deny =>
        native_types.WebviewPopupWindowPolicy.deny,
      WindowsPopupWindowPolicy.sameWindow =>
        native_types.WebviewPopupWindowPolicy.sameWindow,
    });
  }

  /// Sets the WebView2 zoom factor.
  Future<void> setZoomFactor(double zoomFactor) async {
    await _ensureInitialized();
    await _webviewController.setZoomFactor(zoomFactor);
  }

  /// Toggles whether the network cache is ignored for requests.
  Future<void> setCacheDisabled(bool disabled) async {
    await _ensureInitialized();
    await _webviewController.setCacheDisabled(disabled);
  }

  Future<void> _setVirtualHostMapping(String host, String folderPath) async {
    final normalizedPath = path.normalize(folderPath);
    if (_virtualHostMappings[host] == normalizedPath) {
      return;
    }

    if (_virtualHostMappings.containsKey(host)) {
      await _webviewController.removeVirtualHostNameMapping(host);
      _virtualHostMappings.remove(host);
    }
    await _webviewController.addVirtualHostNameMapping(
      host,
      normalizedPath,
      native_types.WebviewHostResourceAccessKind.deny,
    );
    _virtualHostMappings[host] = normalizedPath;
  }

  Future<void> _clearManagedVirtualHostMappings() async {
    for (final String host in _virtualHostMappings.keys.toList()) {
      await _webviewController.removeVirtualHostNameMapping(host);
      _virtualHostMappings.remove(host);
    }
  }

  bool _isManagedVirtualHost(String url) {
    final Uri? uri = Uri.tryParse(url);
    return uri != null &&
        (uri.host == _fileVirtualHost || uri.host == _assetVirtualHost);
  }

  Future<bool> _shouldNavigate(String url) async {
    final callback = _currentNavigationDelegate?._onNavigationRequest;
    final bool shouldNavigate = callback == null
        ? true
        : await _awaitPendingRequest<bool>(
            () async {
              final NavigationDecision decision = await callback(
                NavigationRequest(url: url, isMainFrame: true),
              );
              return decision == NavigationDecision.navigate;
            },
            fallback: false,
            requestName: 'navigation request',
          );
    if (shouldNavigate && !_isManagedVirtualHost(url)) {
      await _clearManagedVirtualHostMappings();
    }
    return shouldNavigate;
  }

  Future<void> _executeScriptBestEffort(String operation, String script) async {
    try {
      await _webviewController.executeScript(script);
    } catch (error) {
      debugPrint(
        'webview_all_windows: failed to apply $operation to the current '
        'document: ${_singleLineWindowsLogValue(error)}',
      );
    }
  }

  List<String> _validateFlutterAssetKey(String key) {
    final List<String> segments = key.split(RegExp(r'[/\\]'));
    if (key.isEmpty ||
        path.isAbsolute(key) ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        key,
        'key',
        'Asset key must be a non-empty relative path without traversal.',
      );
    }
    return segments;
  }

  String _flutterAssetsRootPath() {
    return path.joinAll(<String>[
      path.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
    ]);
  }

  String _escapeHtmlAttribute(String value) {
    return const HtmlEscape(HtmlEscapeMode.attribute).convert(value);
  }

  String _injectBaseUrl(String html, String baseUrl) {
    final baseTag = '<base href="${_escapeHtmlAttribute(baseUrl)}">';
    final headExp = RegExp(r'<head[^>]*>', caseSensitive: false);
    final match = headExp.firstMatch(html);
    if (match != null) {
      return html.replaceRange(match.end, match.end, baseTag);
    }
    return '<head>$baseTag</head>$html';
  }

  Set<WebViewPermissionResourceType> _toPermissionTypes(
    native_types.WebviewPermissionKind permissionKind,
  ) {
    switch (permissionKind) {
      case native_types.WebviewPermissionKind.camera:
        return <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.camera,
        };
      case native_types.WebviewPermissionKind.microphone:
        return <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
        };
      case native_types.WebviewPermissionKind.otherSensors:
      case native_types.WebviewPermissionKind.clipboardRead:
      case native_types.WebviewPermissionKind.geoLocation:
      case native_types.WebviewPermissionKind.notifications:
      case native_types.WebviewPermissionKind.unknown:
        return const <WebViewPermissionResourceType>{};
    }
  }

  String _serializeRequestHeaders(Map<String, String> headers) {
    final buffer = StringBuffer();
    for (final MapEntry<String, String> header in headers.entries) {
      if (header.key.isEmpty ||
          header.key.contains('\r') ||
          header.key.contains('\n') ||
          header.value.contains('\r') ||
          header.value.contains('\n')) {
        throw ArgumentError.value(
          headers,
          'headers',
          'HTTP request headers must not be empty or contain CR/LF.',
        );
      }
      buffer.write(header.key);
      buffer.write(': ');
      buffer.write(header.value);
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  Future<void> _updateScrollBarStyle() async {
    if (_scrollBarStyleScriptId != null) {
      await _webviewController.removeScriptToExecuteOnDocumentCreated(
        _scrollBarStyleScriptId!,
      );
      _scrollBarStyleScriptId = null;
    }

    final script = _scrollBarStyleScript();
    if (!_verticalScrollBarEnabled || !_horizontalScrollBarEnabled) {
      _scrollBarStyleScriptId = await _webviewController
          .addScriptToExecuteOnDocumentCreated(script);
    }
    await _webviewController.executeScript(script);
  }

  String _scrollBarStyleScript() {
    final css = StringBuffer();
    if (!_verticalScrollBarEnabled) {
      css.writeln('*::-webkit-scrollbar:vertical { width: 0 !important; }');
    }
    if (!_horizontalScrollBarEnabled) {
      css.writeln('*::-webkit-scrollbar:horizontal { height: 0 !important; }');
    }

    return '''
      (function() {
        const styleId = '__flutter_webview_all_scrollbars';
        const css = ${jsonEncode(css.toString())};
        let style = document.getElementById(styleId);
        if (!css) {
          if (style) {
            style.remove();
          }
          return;
        }
        if (!style) {
          style = document.createElement('style');
          style.id = styleId;
          (document.head || document.documentElement).appendChild(style);
        }
        style.textContent = css;
      })();
      ''';
  }

  Future<void> _updateOverScrollStyle() async {
    if (_overScrollStyleScriptId != null) {
      await _webviewController.removeScriptToExecuteOnDocumentCreated(
        _overScrollStyleScriptId!,
      );
      _overScrollStyleScriptId = null;
    }

    final script = _overScrollStyleScript();
    if (_overScrollMode != WebViewOverScrollMode.always) {
      _overScrollStyleScriptId = await _webviewController
          .addScriptToExecuteOnDocumentCreated(script);
    }
    await _webviewController.executeScript(script);
  }

  String _overScrollStyleScript() {
    final String value = switch (_overScrollMode) {
      WebViewOverScrollMode.always => '',
      WebViewOverScrollMode.ifContentScrolls => 'contain',
      WebViewOverScrollMode.never => 'none',
    };

    return '''
      (function() {
        const styleId = '__flutter_webview_all_overscroll';
        const value = ${jsonEncode(value)};
        let style = document.getElementById(styleId);
        if (!value) {
          if (style) {
            style.remove();
          }
          return;
        }
        if (!style) {
          style = document.createElement('style');
          style.id = styleId;
          (document.head || document.documentElement).appendChild(style);
        }
        style.textContent =
            'html, body { overscroll-behavior: ' + value + ' !important; }';
      })();
      ''';
  }
}

/// WebView widget implementation for Windows.
class WindowsWebViewWidget extends PlatformWebViewWidget {
  /// Creates a [WindowsWebViewWidget].
  WindowsWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(
        params is WindowsWebViewWidgetCreationParams
            ? params
            : WindowsWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                params,
              ),
      );

  WindowsWebViewWidgetCreationParams get _windowsParams =>
      params as WindowsWebViewWidgetCreationParams;

  @override
  Widget build(BuildContext context) {
    final controller = params.controller as WindowsWebViewController;
    return _WindowsWebView(
      key: params.key,
      controller: controller,
      scaleFactor: _windowsParams.scaleFactor,
      filterQuality: _windowsParams.filterQuality,
    );
  }
}

class _WindowsWebView extends StatefulWidget {
  const _WindowsWebView({
    super.key,
    required this.controller,
    required this.scaleFactor,
    required this.filterQuality,
  });

  final WindowsWebViewController controller;
  final double? scaleFactor;
  final FilterQuality filterQuality;

  @override
  State<_WindowsWebView> createState() => _WindowsWebViewState();
}

class _WindowsWebViewState extends State<_WindowsWebView> {
  late Future<void> _initializationFuture;

  @override
  void initState() {
    super.initState();
    _initializationFuture = widget.controller._ensureInitialized();
  }

  @override
  void didUpdateWidget(_WindowsWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      _initializationFuture = widget.controller._ensureInitialized();
    }
  }

  void _retry() {
    setState(() {
      _initializationFuture = widget.controller._retryInitialization();
    });
  }

  Future<void> _openWebView2DownloadPage() async {
    try {
      await widget.controller._openWebView2DownloadPage();
    } catch (error) {
      debugPrint(
        'webview_all_windows: failed to open the WebView2 download page: $error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
        if (snapshot.hasError) {
          return Material(
            type: MaterialType.transparency,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'WebView2 failed to initialize: ${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: <Widget>[
                        FilledButton(
                          onPressed: () {
                            unawaited(_openWebView2DownloadPage());
                          },
                          child: const Text('Install Webview2'),
                        ),
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        return native_webview.Webview(
          widget.controller._webviewController,
          scaleFactor: widget.scaleFactor,
          filterQuality: widget.filterQuality,
        );
      },
    );
  }
}

/// Windows implementation of [PlatformNavigationDelegate].
class WindowsNavigationDelegate extends PlatformNavigationDelegate {
  /// Creates a [WindowsNavigationDelegate].
  WindowsNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(
        params is WindowsNavigationDelegateCreationParams
            ? params
            : WindowsNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
                params,
              ),
      );

  PageEventCallback? _onPageFinished;
  PageEventCallback? _onPageStarted;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  HttpResponseErrorCallback? _onHttpError;
  HttpAuthRequestCallback? _onHttpAuthRequest;
  SslAuthErrorCallback? _onSslAuthError;
  NavigationRequestCallback? _onNavigationRequest;
  UrlChangeCallback? _onUrlChange;
  final Set<Future<void> Function(bool enabled)> _navigationRequestListeners =
      <Future<void> Function(bool enabled)>{};

  void _addNavigationRequestListener(
    Future<void> Function(bool enabled) listener,
  ) {
    _navigationRequestListeners.add(listener);
  }

  void _removeNavigationRequestListener(
    Future<void> Function(bool enabled) listener,
  ) {
    _navigationRequestListeners.remove(listener);
  }

  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
    await Future.wait<void>(
      _navigationRequestListeners.toList().map(
        (Future<void> Function(bool enabled) listener) => listener(true),
      ),
    );
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    _onPageStarted = onPageStarted;
  }

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback onHttpError) async {
    _onHttpError = onHttpError;
  }

  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {
    _onProgress = onProgress;
  }

  @override
  Future<void> setOnWebResourceError(
    WebResourceErrorCallback onWebResourceError,
  ) async {
    _onWebResourceError = onWebResourceError;
  }

  @override
  Future<void> setOnUrlChange(UrlChangeCallback onUrlChange) async {
    _onUrlChange = onUrlChange;
  }

  @override
  Future<void> setOnHttpAuthRequest(
    HttpAuthRequestCallback onHttpAuthRequest,
  ) async {
    _onHttpAuthRequest = onHttpAuthRequest;
  }

  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback onSslAuthError) async {
    _onSslAuthError = onSslAuthError;
  }
}

/// Windows implementation of [PlatformSslAuthError].
class WindowsPlatformSslAuthError extends PlatformSslAuthError {
  /// Creates a [WindowsPlatformSslAuthError].
  WindowsPlatformSslAuthError({
    required String description,
    required Future<void> Function() onProceed,
    required Future<void> Function() onCancel,
  }) : _onProceed = onProceed,
       _onCancel = onCancel,
       super(certificate: null, description: description);

  final Future<void> Function() _onProceed;
  final Future<void> Function() _onCancel;

  @override
  Future<void> proceed() {
    return _onProceed();
  }

  @override
  Future<void> cancel() {
    return _onCancel();
  }
}

/// Windows implementation of [WebResourceRequest].
class WindowsWebResourceRequest extends WebResourceRequest {
  /// Creates a [WindowsWebResourceRequest].
  const WindowsWebResourceRequest._({
    required super.uri,
    this.method,
    this.headers = const <String, String>{},
  });

  /// The HTTP method reported by WebView2, when available.
  final String? method;

  /// The HTTP request headers reported by WebView2.
  final Map<String, String> headers;
}

/// Windows implementation of [WebResourceResponse].
class WindowsWebResourceResponse extends WebResourceResponse {
  /// Creates a [WindowsWebResourceResponse].
  const WindowsWebResourceResponse._({
    required super.uri,
    required super.statusCode,
    required super.headers,
    this.reasonPhrase,
    this.mimeType,
  });

  /// The HTTP reason phrase reported by WebView2, when available.
  final String? reasonPhrase;

  /// The response MIME type parsed from WebView2 headers, when available.
  final String? mimeType;
}

/// Windows error mapping for WebView2 load failures.
class WindowsWebResourceError extends WebResourceError {
  /// Creates a [WindowsWebResourceError].
  WindowsWebResourceError(
    native_types.WebErrorStatus status, {
    super.url,
    super.isForMainFrame,
  }) : super(
         errorCode: status.index,
         description: status.name,
         errorType: _toErrorType(status),
       );

  static WebResourceErrorType? _toErrorType(
    native_types.WebErrorStatus status,
  ) {
    switch (status) {
      case native_types.WebErrorStatus.WebErrorStatusTimeout:
        return WebResourceErrorType.timeout;
      case native_types.WebErrorStatus.WebErrorStatusCannotConnect:
      case native_types.WebErrorStatus.WebErrorStatusConnectionAborted:
      case native_types.WebErrorStatus.WebErrorStatusConnectionReset:
      case native_types.WebErrorStatus.WebErrorStatusServerUnreachable:
        return WebResourceErrorType.connect;
      case native_types.WebErrorStatus.WebErrorStatusDisconnected:
        return WebResourceErrorType.io;
      case native_types.WebErrorStatus.WebErrorStatusHostNameNotResolved:
        return WebResourceErrorType.hostLookup;
      case native_types.WebErrorStatus.WebErrorStatusOperationCanceled:
        return WebResourceErrorType.unknown;
      case native_types.WebErrorStatus.WebErrorStatusRedirectFailed:
        return WebResourceErrorType.redirectLoop;
      case native_types
          .WebErrorStatus
          .WebErrorStatusValidAuthenticationCredentialsRequired:
        return WebResourceErrorType.authentication;
      case native_types
          .WebErrorStatus
          .WebErrorStatusValidProxyAuthenticationRequired:
        return WebResourceErrorType.proxyAuthentication;
      case native_types
          .WebErrorStatus
          .WebErrorStatusCertificateCommonNameIsIncorrect:
      case native_types.WebErrorStatus.WebErrorStatusCertificateExpired:
      case native_types
          .WebErrorStatus
          .WebErrorStatusClientCertificateContainsErrors:
      case native_types.WebErrorStatus.WebErrorStatusCertificateRevoked:
      case native_types.WebErrorStatus.WebErrorStatusCertificateIsInvalid:
        return WebResourceErrorType.failedSslHandshake;
      case native_types
          .WebErrorStatus
          .WebErrorStatusErrorHTTPInvalidServerResponse:
      case native_types.WebErrorStatus.WebErrorStatusUnexpectedError:
      case native_types.WebErrorStatus.WebErrorStatusUnknown:
        return WebResourceErrorType.unknown;
    }
  }
}

class _WindowsWebViewPermissionRequest
    extends PlatformWebViewPermissionRequest {
  _WindowsWebViewPermissionRequest({required super.types});

  final Completer<native_types.WebviewPermissionDecision> decision =
      Completer<native_types.WebviewPermissionDecision>();

  @override
  Future<void> grant() async {
    if (!decision.isCompleted) {
      decision.complete(native_types.WebviewPermissionDecision.allow);
    }
  }

  @override
  Future<void> deny() async {
    if (!decision.isCompleted) {
      decision.complete(native_types.WebviewPermissionDecision.deny);
    }
  }
}

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'content_type.dart';
import 'http_request_factory.dart';
import 'web_navigation_delegate.dart';

Future<void> _disposeFinalizedWebWebView(_WebWebViewDisposal disposal) async {
  try {
    await disposal.dispose();
  } catch (_) {
    // The browser context can already be detached when a finalizer runs.
    return;
  }
}

@JS('JSON.stringify')
external JSString? _jsonStringify(JSAny? value);

@JS('Object.is')
external bool _isSameJavaScriptObject(JSAny? first, JSAny? second);

extension _WebWindowJavaScriptExtension on web.Window {
  @JS('eval')
  external JSAny? evaluateJavaScript(String script);
}

extension _WebHeadersExtension on web.Headers {
  external void forEach(JSFunction callback);
}

void _validateIFrameAttributeName(String name) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Attribute name must not be empty.',
    );
  }
}

void _setIFrameAttribute(
  web.HTMLIFrameElement iFrame,
  String name,
  String? value,
) {
  _validateIFrameAttributeName(name);
  if (value == null) {
    iFrame.removeAttribute(name);
  } else {
    iFrame.setAttribute(name, value);
  }
}

/// An implementation of [PlatformWebViewControllerCreationParams] using Flutter
/// for Web API.
@immutable
class WebWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Creates a new [WebWebViewControllerCreationParams] instance.
  WebWebViewControllerCreationParams({
    @visibleForTesting this.httpRequestFactory = const HttpRequestFactory(),
    this.iFrameAllow,
    this.iFrameSandbox,
    this.iFrameReferrerPolicy,
    Map<String, String?> iFrameAttributes = const <String, String?>{},
  }) : iFrameAttributes = Map<String, String?>.unmodifiable(iFrameAttributes),
       super() {
    _setIFrameAttribute(iFrame, 'allow', iFrameAllow);
    _setIFrameAttribute(iFrame, 'sandbox', iFrameSandbox);
    _setIFrameAttribute(iFrame, 'referrerpolicy', iFrameReferrerPolicy);
    this.iFrameAttributes.forEach((String name, String? value) {
      _setIFrameAttribute(iFrame, name, value);
    });
  }

  /// Creates a [WebWebViewControllerCreationParams] instance based on [PlatformWebViewControllerCreationParams].
  WebWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    PlatformWebViewControllerCreationParams params, {
    @visibleForTesting
    HttpRequestFactory httpRequestFactory = const HttpRequestFactory(),
    String? iFrameAllow,
    String? iFrameSandbox,
    String? iFrameReferrerPolicy,
    Map<String, String?> iFrameAttributes = const <String, String?>{},
  }) : this(
         httpRequestFactory: httpRequestFactory,
         iFrameAllow: iFrameAllow,
         iFrameSandbox: iFrameSandbox,
         iFrameReferrerPolicy: iFrameReferrerPolicy,
         iFrameAttributes: iFrameAttributes,
       );

  static int _nextIFrameId = 0;

  /// Handles creating and sending URL requests.
  final HttpRequestFactory httpRequestFactory;

  /// Value for the iframe `allow` attribute.
  final String? iFrameAllow;

  /// Value for the iframe `sandbox` attribute while JavaScript is unrestricted.
  final String? iFrameSandbox;

  /// Value for the iframe `referrerpolicy` attribute.
  final String? iFrameReferrerPolicy;

  /// Additional attributes applied to the underlying iframe.
  ///
  /// Values from this map override [iFrameAllow], [iFrameSandbox], and
  /// [iFrameReferrerPolicy] when the same attribute name is present.
  final Map<String, String?> iFrameAttributes;

  /// The underlying element used as the WebView.
  @visibleForTesting
  final web.HTMLIFrameElement iFrame = web.HTMLIFrameElement()
    ..id = 'webView${_nextIFrameId++}'
    ..style.width = '100%'
    ..style.height = '100%'
    ..style.border = 'none'
    ..style.borderStyle = 'none'
    ..style.borderWidth = '0';
}

/// An implementation of [PlatformWebViewController] using Flutter for Web API.
class WebWebViewController extends PlatformWebViewController {
  /// Constructs a [WebWebViewController].
  WebWebViewController(PlatformWebViewControllerCreationParams params)
    : super.implementation(
        params is WebWebViewControllerCreationParams
            ? params
            : WebWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
                params,
              ),
      ) {
    final WeakReference<WebWebViewController> weakThis =
        WeakReference<WebWebViewController>(this);
    _customSandbox = _webWebViewParams.iFrame.getAttribute('sandbox');
    _messageEventListener = ((web.Event event) {
      weakThis.target?._handleWindowMessage(event as web.MessageEvent);
    }).toJS;
    web.window.addEventListener('message', _messageEventListener);
    _loadEventSubscription = _webWebViewParams.iFrame.onLoad.listen((_) {
      final WebWebViewController? target = weakThis.target;
      if (target == null) {
        return;
      }
      final String? resolvedUrl = target._shouldPreserveLogicalUrl
          ? target._currentUrl
          : target._tryReadCurrentFrameUrl() ?? target._currentUrl;
      if (resolvedUrl != null) {
        target._currentUrl = resolvedUrl;
        target._navigationDelegate?.onUrlChange?.call(
          UrlChange(url: resolvedUrl),
        );
        target._navigationDelegate?.onPageFinished?.call(resolvedUrl);
      }
      target._applyScrollBarStyle();
      target._installJavaScriptChannels();
      target._installConsoleMessageHook();
      target._installJavaScriptAlertDialogHook();
      target._installJavaScriptConfirmDialogHook();
      target._installJavaScriptTextInputDialogHook();
      target._installPlatformPermissionRequestHook();
      target._attachScrollListenerToCurrentWindow();
      target._navigationDelegate?.onProgress?.call(100);
    });
    final String iFrameId = _webWebViewParams.iFrame.id;
    _nativeDisposal = _WebWebViewDisposal(
      iFrame: _webWebViewParams.iFrame,
      messageEventListener: _messageEventListener,
      loadEventSubscription: _loadEventSubscription,
      clearJavaScriptDialogBridge: () {
        WebWebViewController._javaScriptDialogBridgeRoot[iFrameId] = null;
      },
    );
    _finalizer.attach(this, _nativeDisposal, detach: this);
  }

  static final Finalizer<_WebWebViewDisposal> _finalizer =
      Finalizer<_WebWebViewDisposal>((_WebWebViewDisposal disposal) {
        unawaited(_disposeFinalizedWebWebView(disposal));
      });

  static const String _scrollBarStyleId = '__webview_all_scrollbars';
  static const String _channelMessageType = '__webview_all_type';
  static const String _javaScriptChannelMessageType = 'javascriptChannel';
  static const String _consoleMessageType = 'consoleMessage';
  static const String _javaScriptAlertDialogMessageType =
      'javaScriptAlertDialog';
  static const String _javaScriptDialogBridgeName = '__webviewAllDialogBridge';
  static final JSObject _javaScriptDialogBridgeRoot = JSObject();
  static bool _isJavaScriptDialogBridgeRootInstalled = false;
  static const String _platformPermissionRequestMessageType =
      'platformPermissionRequest';
  static const String _platformPermissionDecisionMessageType =
      'platformPermissionDecision';
  static const String _isolatedBridgeReadyMessageType = 'isolatedBridgeReady';
  static const String _isolatedBridgeRequestMessageType =
      'isolatedBridgeRequest';
  static const String _isolatedBridgeResponseMessageType =
      'isolatedBridgeResponse';
  static const String _isolatedBridgeScrollMessageType = 'isolatedBridgeScroll';
  static const Duration _isolatedBridgeTimeout = Duration(seconds: 10);
  static const String _javaScriptDisabledSandbox =
      'allow-same-origin allow-forms allow-popups allow-downloads allow-modals';

  WebWebViewControllerCreationParams get _webWebViewParams =>
      params as WebWebViewControllerCreationParams;

  final List<String> _history = <String>[];
  int _historyIndex = -1;
  String? _currentUrl;
  String? _userAgentOverride;
  String? _customSandbox;
  String? _lastHtmlStringContent;
  LoadRequestParams? _lastXhrRequestParams;
  WebNavigationDelegate? _navigationDelegate;
  _NavigationLoadType _lastLoadedType = _NavigationLoadType.none;
  bool _verticalScrollBarEnabled = true;
  bool _horizontalScrollBarEnabled = true;
  JavaScriptMode _javaScriptMode = JavaScriptMode.unrestricted;
  final Map<String, JavaScriptChannelParams> _javaScriptChannels =
      <String, JavaScriptChannelParams>{};
  void Function(JavaScriptConsoleMessage consoleMessage)? _onConsoleMessage;
  Future<void> Function(JavaScriptAlertDialogRequest request)?
  _onJavaScriptAlertDialog;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)?
  _onJavaScriptConfirmDialog;
  Future<String> Function(JavaScriptTextInputDialogRequest request)?
  _onJavaScriptTextInputDialog;
  void Function(PlatformWebViewPermissionRequest request)?
  _onPlatformPermissionRequest;
  void Function(ScrollPositionChange scrollPositionChange)?
  _onScrollPositionChange;
  late final web.EventListener _messageEventListener;
  late final StreamSubscription<web.Event> _loadEventSubscription;
  late final _WebWebViewDisposal _nativeDisposal;
  JSExportedDartFunction? _javaScriptConfirmDialogBridge;
  JSExportedDartFunction? _javaScriptTextInputDialogBridge;
  int _isolatedBridgeGeneration = 0;
  int _nextIsolatedBridgeRequestId = 0;
  Completer<void>? _isolatedBridgeReady;
  final Map<int, Completer<Object?>> _pendingIsolatedBridgeRequests =
      <int, Completer<Object?>>{};
  final Set<String> _reportedLimitations = <String>{};

  void _logLimitationOnce(String key, String message) {
    if (_reportedLimitations.add(key)) {
      debugPrint('webview_all_web: $message');
    }
  }

  @override
  Future<void> loadFile(String absoluteFilePath) {
    throw UnsupportedError(
      'loadFile is not supported on web. Use loadFlutterAsset or '
      'loadHtmlString instead.',
    );
  }

  @override
  Future<void> loadFileWithParams(LoadFileParams params) {
    return loadFile(params.absoluteFilePath);
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    final String assetUrl = _resolveFlutterAssetUrl(key);
    await _loadUrl(assetUrl, updateHistory: true);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) async {
    final String content = _injectBaseUrl(html, baseUrl);
    _navigationDelegate?.onPageStarted?.call(baseUrl ?? 'about:blank');
    _navigationDelegate?.onProgress?.call(0);
    _currentUrl = baseUrl ?? 'about:blank';
    _lastHtmlStringContent = content;
    _lastXhrRequestParams = null;
    _lastLoadedType = _NavigationLoadType.html;
    _markLogicalUrlHistoryEntry(_currentUrl!);
    _webWebViewParams.iFrame.srcdoc = _prepareInlineHtml(content).toJS;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError(
        'LoadRequestParams#uri is required to have a scheme.',
      );
    }

    if (params.headers.isEmpty &&
        (params.body == null || params.body!.isEmpty) &&
        params.method == LoadRequestMethod.get) {
      await _loadUrl(params.uri.toString(), updateHistory: true);
    } else {
      await _updateIFrameFromXhr(params);
    }
  }

  @override
  Future<String?> currentUrl() async {
    return _currentUrl;
  }

  @override
  Future<bool> canGoBack() async {
    return _historyIndex > 0;
  }

  @override
  Future<bool> canGoForward() async {
    return _historyIndex >= 0 && _historyIndex < _history.length - 1;
  }

  @override
  Future<void> goBack() async {
    if (!await canGoBack()) {
      return;
    }
    _historyIndex -= 1;
    await _loadUrl(_history[_historyIndex], updateHistory: false);
  }

  @override
  Future<void> goForward() async {
    if (!await canGoForward()) {
      return;
    }
    _historyIndex += 1;
    await _loadUrl(_history[_historyIndex], updateHistory: false);
  }

  @override
  Future<void> reload() async {
    if (_lastLoadedType == _NavigationLoadType.html) {
      _webWebViewParams.iFrame.srcdoc = _prepareInlineHtml(
        _lastHtmlStringContent ?? '',
      ).toJS;
      return;
    }

    if (_lastLoadedType == _NavigationLoadType.xhrResponse &&
        _lastXhrRequestParams != null) {
      await _updateIFrameFromXhr(_lastXhrRequestParams!, updateHistory: false);
      return;
    }

    if (_currentUrl != null) {
      await _loadUrl(_currentUrl!, updateHistory: false);
    }
  }

  @override
  Future<void> clearCache() async {
    try {
      final web.CacheStorage cacheStorage = web.window.caches;
      final JSArray<JSString> keys = await cacheStorage.keys().toDart;
      for (final JSString key in keys.toDart) {
        await cacheStorage.delete(key.toDart).toDart;
      }
    } catch (_) {
      // Best-effort only for the host origin.
    }
  }

  @override
  Future<void> clearLocalStorage() async {
    try {
      web.window.localStorage.clear();
      web.window.sessionStorage.clear();
    } catch (_) {
      // Best-effort only for the host origin.
    }
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigationDelegate = handler as WebNavigationDelegate;
  }

  @override
  Future<Offset> getScrollPosition() async {
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      return Offset(window.scrollX, window.scrollY);
    }
    if (_hasIsolatedBridge) {
      final Object? result = await _invokeIsolatedBridge('getScrollPosition');
      if (result case <String, Object?>{'x': final num x, 'y': final num y}) {
        return Offset(x.toDouble(), y.toDouble());
      }
      throw StateError(
        'The isolated frame returned an invalid scroll position.',
      );
    }
    _requireAccessibleContentWindow(
      'Reading scroll position is only supported for controllable iframe content.',
    );
    throw StateError('Unreachable.');
  }

  @override
  Future<void> scrollTo(int x, int y) async {
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      window.scrollTo(x.toJS, y);
      return;
    }
    if (_hasIsolatedBridge) {
      await _invokeIsolatedBridge(
        'scrollTo',
        payload: <String, Object?>{'x': x, 'y': y},
      );
      return;
    }
    _requireAccessibleContentWindow(
      'Scrolling iframe content is only supported for controllable iframe content.',
    );
  }

  @override
  Future<void> scrollBy(int x, int y) async {
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      window.scrollBy(x.toJS, y);
      return;
    }
    if (_hasIsolatedBridge) {
      await _invokeIsolatedBridge(
        'scrollBy',
        payload: <String, Object?>{'x': x, 'y': y},
      );
      return;
    }
    _requireAccessibleContentWindow(
      'Scrolling iframe content is only supported for controllable iframe content.',
    );
  }

  web.Window _requireAccessibleContentWindow(String message) {
    try {
      final web.Window? window = _webWebViewParams.iFrame.contentWindow;
      if (window == null) {
        throw UnsupportedError(message);
      }
      // Probe a property that is blocked for cross-origin frames.
      window.scrollX;
      return window;
    } catch (_) {
      throw UnsupportedError(message);
    }
  }

  web.Document? _tryReadContentDocument() {
    try {
      return _webWebViewParams.iFrame.contentDocument;
    } catch (_) {
      return null;
    }
  }

  web.Window? _tryReadAccessibleContentWindow() {
    try {
      final web.Window? window = _webWebViewParams.iFrame.contentWindow;
      if (window == null) {
        return null;
      }
      window.scrollX;
      return window;
    } catch (_) {
      return null;
    }
  }

  void _resetIsolatedBridge() {
    _isolatedBridgeGeneration += 1;
    final Completer<void>? ready = _isolatedBridgeReady;
    if (ready != null && !ready.isCompleted) {
      // Wake waiters so they can observe the generation change immediately.
      ready.complete();
    }
    _isolatedBridgeReady = null;

    final StateError error = StateError(
      'The WebView navigated before an isolated frame operation completed.',
    );
    for (final Completer<Object?> completer
        in _pendingIsolatedBridgeRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingIsolatedBridgeRequests.clear();
  }

  void _prepareIsolatedBridge() {
    _resetIsolatedBridge();
    _isolatedBridgeReady = Completer<void>();
  }

  bool get _hasIsolatedBridge => _isolatedBridgeReady != null;

  Set<String>? get _currentSandboxTokens {
    final String? sandbox = _webWebViewParams.iFrame.getAttribute('sandbox');
    if (sandbox == null) {
      return null;
    }
    return sandbox
        .split(RegExp(r'\s+'))
        .where((String token) => token.isNotEmpty)
        .map((String token) => token.toLowerCase())
        .toSet();
  }

  bool get _currentSandboxAllowsScripts {
    final Set<String>? tokens = _currentSandboxTokens;
    return tokens == null || tokens.contains('allow-scripts');
  }

  bool get _currentSandboxCreatesOpaqueOrigin {
    final Set<String>? tokens = _currentSandboxTokens;
    return tokens != null && !tokens.contains('allow-same-origin');
  }

  String _prepareInlineHtml(String html) {
    if (_javaScriptMode == JavaScriptMode.unrestricted &&
        _currentSandboxAllowsScripts &&
        _currentSandboxCreatesOpaqueOrigin) {
      _prepareIsolatedBridge();
      return _injectIntoDocumentHead(
        html,
        _isolatedBridgeBootstrap(_isolatedBridgeGeneration),
      );
    }
    _resetIsolatedBridge();
    return html;
  }

  Future<Object?> _invokeIsolatedBridge(
    String action, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) async {
    final int generation = _isolatedBridgeGeneration;
    final Completer<void>? ready = _isolatedBridgeReady;
    if (ready == null) {
      throw UnsupportedError(
        'The current iframe document does not provide the isolated WebView bridge.',
      );
    }

    await ready.future.timeout(
      _isolatedBridgeTimeout,
      onTimeout: () => throw TimeoutException(
        'Timed out waiting for the isolated WebView bridge to initialize.',
        _isolatedBridgeTimeout,
      ),
    );
    if (generation != _isolatedBridgeGeneration ||
        !identical(ready, _isolatedBridgeReady)) {
      throw StateError('The WebView navigated before the operation started.');
    }

    final int requestId = _nextIsolatedBridgeRequestId++;
    final Completer<Object?> completer = Completer<Object?>();
    _pendingIsolatedBridgeRequests[requestId] = completer;

    final web.Window? window = _webWebViewParams.iFrame.contentWindow;
    if (window == null) {
      _pendingIsolatedBridgeRequests.remove(requestId);
      throw StateError('The iframe content window is unavailable.');
    }
    window.postMessage(
      <String, Object?>{
        _channelMessageType: _isolatedBridgeRequestMessageType,
        'webViewId': _webWebViewParams.iFrame.id,
        'generation': generation,
        'requestId': requestId,
        'action': action,
        'payload': payload,
      }.jsify(),
      '*'.toJS,
    );

    return completer.future.timeout(
      _isolatedBridgeTimeout,
      onTimeout: () {
        _pendingIsolatedBridgeRequests.remove(requestId);
        throw TimeoutException(
          'Timed out waiting for the isolated WebView operation "$action".',
          _isolatedBridgeTimeout,
        );
      },
    );
  }

  Future<bool> _evaluateScriptInCurrentDocument(String script) async {
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      window.evaluateJavaScript(script);
      return true;
    }
    if (_hasIsolatedBridge) {
      await _invokeIsolatedBridge(
        'evaluate',
        payload: <String, Object?>{'script': script},
      );
      return true;
    }
    return false;
  }

  void _installScriptBestEffort(String feature, String script) {
    unawaited(
      _evaluateScriptInCurrentDocument(script).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          debugPrint(
            'webview_all_web: failed to install $feature in the current '
            'document: $error',
          );
        },
      ),
    );
  }

  void _applyScrollBarStyle() {
    final web.Document? document = _tryReadContentDocument();
    final StringBuffer css = StringBuffer();
    if (!_verticalScrollBarEnabled) {
      css.writeln('*::-webkit-scrollbar:vertical { width: 0 !important; }');
    }
    if (!_horizontalScrollBarEnabled) {
      css.writeln('*::-webkit-scrollbar:horizontal { height: 0 !important; }');
    }

    if (document == null) {
      if (_hasIsolatedBridge) {
        final String cssValue = jsonEncode(css.toString());
        _installScriptBestEffort('scrollbar styling', '''
          (function() {
            const styleId = ${jsonEncode(_scrollBarStyleId)};
            const css = $cssValue;
            const existing = document.getElementById(styleId);
            if (!css) {
              if (existing) existing.remove();
              return;
            }
            const style = existing || document.createElement('style');
            style.id = styleId;
            style.textContent = css;
            if (!existing) {
              (document.head || document.documentElement).appendChild(style);
            }
          })();
        ''');
      }
      return;
    }

    final web.Element? existing = document.getElementById(_scrollBarStyleId);
    if (css.isEmpty) {
      existing?.remove();
      return;
    }

    final web.Element style = existing ?? document.createElement('style');
    if (existing == null) {
      style.id = _scrollBarStyleId;
      (document.head ?? document.documentElement)?.append(style);
    }
    style.textContent = css.toString();
  }

  void _emitScrollPositionChange() {
    final callback = _onScrollPositionChange;
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (callback == null || window == null) {
      return;
    }

    callback(ScrollPositionChange(window.scrollX, window.scrollY));
  }

  void _detachScrollListener() {
    _nativeDisposal.detachScrollListener();
  }

  void _attachScrollListenerToCurrentWindow() {
    final callback = _onScrollPositionChange;
    if (callback == null) {
      _detachScrollListener();
      return;
    }

    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window == null ||
        identical(window, _nativeDisposal.scrollEventListenerWindow)) {
      return;
    }

    _detachScrollListener();
    final WeakReference<WebWebViewController> weakThis =
        WeakReference<WebWebViewController>(this);
    final web.EventListener listener = ((web.Event event) {
      weakThis.target?._emitScrollPositionChange();
    }).toJS;
    window.addEventListener('scroll', listener);
    _nativeDisposal.setScrollListener(window, listener);
  }

  void _setIframeScrollBarVisibility({
    bool? verticalEnabled,
    bool? horizontalEnabled,
  }) {
    _verticalScrollBarEnabled = verticalEnabled ?? _verticalScrollBarEnabled;
    _horizontalScrollBarEnabled =
        horizontalEnabled ?? _horizontalScrollBarEnabled;
    _applyScrollBarStyle();
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) async {
    _setIframeScrollBarVisibility(verticalEnabled: enabled);
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) async {
    _setIframeScrollBarVisibility(horizontalEnabled: enabled);
  }

  @override
  bool supportsSetScrollBarsEnabled() {
    return true;
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) async {
    _onScrollPositionChange = onScrollPositionChange;
    _attachScrollListenerToCurrentWindow();
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    if (enabled) {
      _webWebViewParams.iFrame.style.removeProperty('touch-action');
    } else {
      _webWebViewParams.iFrame.style.setProperty('touch-action', 'pan-x pan-y');
    }
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    _webWebViewParams.iFrame.style.backgroundColor = _cssColorFrom(color);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    _javaScriptMode = javaScriptMode;
    _applySandboxForJavaScriptMode();
  }

  /// Sets or removes an attribute on the underlying iframe element.
  ///
  /// Passing `null` removes the attribute. When [name] is `sandbox`, the value
  /// is preserved as the unrestricted-mode sandbox and will be restored when
  /// [setJavaScriptMode] switches JavaScript back to unrestricted mode.
  Future<void> setIFrameAttribute(String name, String? value) async {
    _validateIFrameAttributeName(name);
    if (name.toLowerCase() == 'sandbox') {
      _customSandbox = value;
      _applySandboxForJavaScriptMode();
      return;
    }

    _setIFrameAttribute(_webWebViewParams.iFrame, name, value);
  }

  /// Sets or removes the iframe `allow` attribute.
  Future<void> setIFrameAllow(String? allow) {
    return setIFrameAttribute('allow', allow);
  }

  /// Sets or removes the iframe `sandbox` attribute.
  Future<void> setIFrameSandbox(String? sandbox) {
    return setIFrameAttribute('sandbox', sandbox);
  }

  /// Sets or removes the iframe `referrerpolicy` attribute.
  Future<void> setIFrameReferrerPolicy(String? referrerPolicy) {
    return setIFrameAttribute('referrerpolicy', referrerPolicy);
  }

  void _applySandboxForJavaScriptMode() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      _webWebViewParams.iFrame.setAttribute(
        'sandbox',
        _javaScriptDisabledSandbox,
      );
    } else {
      _setIFrameAttribute(_webWebViewParams.iFrame, 'sandbox', _customSandbox);
    }
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    if (userAgent == null) {
      _userAgentOverride = null;
      return;
    }

    _logLimitationOnce(
      'setUserAgent',
      'The browser does not allow an iframe to override its User-Agent. '
          'The requested value was ignored.',
    );
  }

  @override
  Future<String?> getUserAgent() async {
    return _userAgentOverride ?? web.window.navigator.userAgent;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      throw StateError('JavaScript execution is disabled for this WebView.');
    }
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      window.evaluateJavaScript(javaScript);
      return;
    }
    if (_hasIsolatedBridge) {
      await _invokeIsolatedBridge(
        'evaluate',
        payload: <String, Object?>{'script': javaScript},
      );
      return;
    }
    _requireAccessibleContentWindow(
      'Running JavaScript is only supported for controllable iframe content.',
    );
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      throw StateError('JavaScript execution is disabled for this WebView.');
    }
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window != null) {
      final JSAny? result = window.evaluateJavaScript(javaScript);
      return _dartObjectFromJavaScriptResult(result);
    }
    if (_hasIsolatedBridge) {
      final Object? result = await _invokeIsolatedBridge(
        'evaluateReturningResult',
        payload: <String, Object?>{'script': javaScript},
      );
      if (result == null) {
        throw ArgumentError(
          'The JavaScript returned `null` or `undefined`, which is unsupported.',
        );
      }
      return result;
    }
    _requireAccessibleContentWindow(
      'Running JavaScript is only supported for controllable iframe content.',
    );
    throw StateError('Unreachable.');
  }

  Object _dartObjectFromJavaScriptResult(JSAny? result) {
    if (result == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }

    final JSString? jsonResult;
    try {
      jsonResult = _jsonStringify(result);
    } catch (error) {
      throw UnsupportedError(
        'The JavaScript result could not be serialized: $error',
      );
    }

    if (jsonResult == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }

    final Object? decoded = jsonDecode(jsonResult.toDart);
    if (decoded == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }
    return decoded;
  }

  void _handleWindowMessage(web.MessageEvent event) {
    final web.Window? contentWindow = _webWebViewParams.iFrame.contentWindow;
    if (contentWindow == null ||
        !_isSameJavaScriptObject(event.source, contentWindow)) {
      return;
    }

    final JSString? jsonData = _jsonStringify(event.data);
    if (jsonData == null) {
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(jsonData.toDart);
    } catch (_) {
      return;
    }

    if (decoded is! Map<String, dynamic> ||
        decoded['webViewId'] != _webWebViewParams.iFrame.id) {
      return;
    }

    switch (decoded[_channelMessageType]) {
      case _isolatedBridgeReadyMessageType:
        if (decoded['generation'] != _isolatedBridgeGeneration) {
          return;
        }
        final Completer<void>? ready = _isolatedBridgeReady;
        if (ready != null && !ready.isCompleted) {
          ready.complete();
        }
        return;
      case _isolatedBridgeResponseMessageType:
        if (decoded['generation'] != _isolatedBridgeGeneration) {
          return;
        }
        final int? requestId = (decoded['requestId'] as num?)?.toInt();
        final Completer<Object?>? completer = requestId == null
            ? null
            : _pendingIsolatedBridgeRequests.remove(requestId);
        if (completer == null || completer.isCompleted) {
          return;
        }
        if (decoded['ok'] == true) {
          completer.complete(decoded['result']);
        } else {
          final String errorName = '${decoded['errorName'] ?? 'Error'}';
          final String errorMessage =
              '${decoded['errorMessage'] ?? 'The isolated frame operation failed.'}';
          completer.completeError(StateError('$errorName: $errorMessage'));
        }
        return;
      case _isolatedBridgeScrollMessageType:
        final void Function(ScrollPositionChange scrollPositionChange)?
        callback = _onScrollPositionChange;
        final num? x = decoded['x'] as num?;
        final num? y = decoded['y'] as num?;
        if (callback != null && x != null && y != null) {
          callback(ScrollPositionChange(x.toDouble(), y.toDouble()));
        }
        return;
      case _javaScriptChannelMessageType:
        final String? channelName = decoded['channelName'] as String?;
        final JavaScriptChannelParams? channel = channelName == null
            ? null
            : _javaScriptChannels[channelName];
        if (channel == null) {
          return;
        }
        channel.onMessageReceived(
          JavaScriptMessage(message: '${decoded['message'] ?? ''}'),
        );
        return;
      case _consoleMessageType:
        final void Function(JavaScriptConsoleMessage consoleMessage)? callback =
            _onConsoleMessage;
        if (callback == null) {
          return;
        }
        callback(
          JavaScriptConsoleMessage(
            level: _javaScriptLogLevelFromString(decoded['level'] as String?),
            message: '${decoded['message'] ?? ''}',
          ),
        );
        return;
      case _javaScriptAlertDialogMessageType:
        final Future<void> Function(JavaScriptAlertDialogRequest request)?
        callback = _onJavaScriptAlertDialog;
        if (callback == null) {
          return;
        }
        unawaited(
          callback(
            JavaScriptAlertDialogRequest(
              message: '${decoded['message'] ?? ''}',
              url: '${decoded['url'] ?? _currentUrl ?? 'about:blank'}',
            ),
          ),
        );
        return;
      case _platformPermissionRequestMessageType:
        final void Function(PlatformWebViewPermissionRequest request)?
        callback = _onPlatformPermissionRequest;
        final String? requestId = decoded['requestId'] as String?;
        if (callback == null || requestId == null) {
          return;
        }
        callback(
          WebWebViewPermissionRequest._(
            types: _permissionTypesFromMessage(decoded['types']),
            onDecision: (bool granted) {
              _sendPlatformPermissionDecision(requestId, granted);
            },
          ),
        );
        return;
    }
  }

  Set<WebViewPermissionResourceType> _permissionTypesFromMessage(
    Object? value,
  ) {
    if (value is! List<Object?>) {
      return const <WebViewPermissionResourceType>{};
    }

    return value
        .map<WebViewPermissionResourceType?>((Object? type) {
          return switch (type) {
            'camera' => WebViewPermissionResourceType.camera,
            'microphone' => WebViewPermissionResourceType.microphone,
            _ => null,
          };
        })
        .whereType<WebViewPermissionResourceType>()
        .toSet();
  }

  void _sendPlatformPermissionDecision(String requestId, bool granted) {
    _webWebViewParams.iFrame.contentWindow?.postMessage(
      <String, Object?>{
        _channelMessageType: _platformPermissionDecisionMessageType,
        'webViewId': _webWebViewParams.iFrame.id,
        'requestId': requestId,
        'granted': granted,
      }.jsify(),
      '*'.toJS,
    );
  }

  JavaScriptLogLevel _javaScriptLogLevelFromString(String? level) {
    return switch (level) {
      'debug' => JavaScriptLogLevel.debug,
      'error' => JavaScriptLogLevel.error,
      'info' => JavaScriptLogLevel.info,
      'warning' => JavaScriptLogLevel.warning,
      _ => JavaScriptLogLevel.log,
    };
  }

  void _installJavaScriptChannels() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_javaScriptChannels.isEmpty) {
      return;
    }

    for (final JavaScriptChannelParams channel in _javaScriptChannels.values) {
      _installScriptBestEffort(
        'JavaScript channel "${channel.name}"',
        _javaScriptChannelScript(channel.name),
      );
    }
  }

  String _javaScriptChannelScript(String name) {
    return '''
      (function() {
        const channelName = ${jsonEncode(name)};
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
        window[channelName] = {
          postMessage: function(message) {
            window.parent.postMessage({
              "$_channelMessageType": "$_javaScriptChannelMessageType",
              "webViewId": webViewId,
              "channelName": channelName,
              "message": String(message)
            }, "*");
          }
        };
      })();
      ''';
  }

  String _removeJavaScriptChannelScript(String name) {
    return '''
      (function() {
        const channelName = ${jsonEncode(name)};
        try {
          delete window[channelName];
        } catch (_) {
          window[channelName] = undefined;
        }
      })();
      ''';
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) async {
    final String name = javaScriptChannelParams.name;
    if (name.isEmpty) {
      throw ArgumentError.value(
        name,
        'javaScriptChannelParams.name',
        'JavaScript channel names must not be empty.',
      );
    }
    if (_javaScriptChannels.containsKey(name)) {
      throw ArgumentError(
        'A JavaScriptChannel with name `$name` already exists.',
      );
    }

    _javaScriptChannels[name] = javaScriptChannelParams;
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    await _evaluateScriptInCurrentDocument(_javaScriptChannelScript(name));
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    _javaScriptChannels.remove(javaScriptChannelName);
    await _evaluateScriptInCurrentDocument(
      _removeJavaScriptChannelScript(javaScriptChannelName),
    );
  }

  void _installConsoleMessageHook() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_onConsoleMessage == null) {
      return;
    }

    _installScriptBestEffort('console forwarding', '''
      (function() {
        if (window.__webviewAllConsoleHookInstalled) {
          return;
        }
        window.__webviewAllConsoleHookInstalled = true;
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
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
          window.parent.postMessage({
            "$_channelMessageType": "$_consoleMessageType",
            "webViewId": webViewId,
            "level": level,
            "message": Array.from(args).map(stringifyArg).join(' ')
          }, "*");
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
      ''');
  }

  @override
  Future<String?> getTitle() async {
    try {
      final web.Document? document = _webWebViewParams.iFrame.contentDocument;
      if (document != null) {
        return document.title;
      }
    } catch (_) {
      // Fall through to the isolated bridge.
    }
    if (_hasIsolatedBridge) {
      return (await _invokeIsolatedBridge('getTitle')) as String?;
    }
    return null;
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    _onConsoleMessage = onConsoleMessage;
    _installConsoleMessageHook();
  }

  void _installJavaScriptAlertDialogHook() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_onJavaScriptAlertDialog == null) {
      return;
    }

    _installScriptBestEffort('JavaScript alert forwarding', '''
      (function() {
        if (window.__webviewAllAlertDialogHookInstalled) {
          return;
        }
        window.__webviewAllAlertDialogHookInstalled = true;
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
        window.alert = function(message) {
          window.parent.postMessage({
            "$_channelMessageType": "$_javaScriptAlertDialogMessageType",
            "webViewId": webViewId,
            "message": String(message),
            "url": window.location.href
          }, "*");
        };
      })();
      ''');
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    _onJavaScriptAlertDialog = onJavaScriptAlertDialog;
    _installJavaScriptAlertDialogHook();
  }

  JSObject _ensureJavaScriptDialogBridgeRoot() {
    if (!_isJavaScriptDialogBridgeRootInstalled) {
      globalContext[_javaScriptDialogBridgeName] = _javaScriptDialogBridgeRoot;
      _isJavaScriptDialogBridgeRootInstalled = true;
    }
    return _javaScriptDialogBridgeRoot;
  }

  void _updateJavaScriptDialogBridge() {
    if (_onJavaScriptConfirmDialog == null &&
        _onJavaScriptTextInputDialog == null) {
      return;
    }

    final JSObject bridge = JSObject();
    final WeakReference<WebWebViewController> weakThis =
        WeakReference<WebWebViewController>(this);
    if (_onJavaScriptConfirmDialog != null) {
      _javaScriptConfirmDialogBridge ??= ((JSString message, JSString url) {
        final WebWebViewController? target = weakThis.target;
        return (target?._handleJavaScriptConfirmDialog(
                  message.toDart,
                  url.toDart,
                ) ??
                false)
            .toJS;
      }).toJS;
      bridge['confirm'] = _javaScriptConfirmDialogBridge;
    }
    if (_onJavaScriptTextInputDialog != null) {
      _javaScriptTextInputDialogBridge ??=
          ((JSString message, JSString url, JSString? defaultText) {
            final String? fallback = defaultText?.toDart;
            final WebWebViewController? target = weakThis.target;
            return (target?._handleJavaScriptTextInputDialog(
                      message.toDart,
                      url.toDart,
                      fallback,
                    ) ??
                    fallback ??
                    '')
                .toJS;
          }).toJS;
      bridge['prompt'] = _javaScriptTextInputDialogBridge;
    }

    _ensureJavaScriptDialogBridgeRoot()[_webWebViewParams.iFrame.id] = bridge;
  }

  T _completeJavaScriptDialogSynchronously<T>(
    Future<T> future,
    String dialogName,
    T fallback,
  ) {
    bool completed = false;
    bool returned = false;
    T? result;
    Object? error;

    future.then(
      (T value) {
        completed = true;
        result = value;
        if (returned) {
          _logLimitationOnce(
            'late-$dialogName-dialog-result',
            'An asynchronous JavaScript $dialogName callback completed after '
                'the browser required its result. The safe fallback was '
                'already returned.',
          );
        }
      },
      onError: (Object exception, StackTrace stack) {
        completed = true;
        error = exception;
        debugPrint(
          'webview_all_web: JavaScript $dialogName callback failed: '
          '$exception\n$stack',
        );
      },
    );

    if (!completed) {
      returned = true;
      _logLimitationOnce(
        'async-$dialogName-dialog',
        'JavaScript $dialogName callbacks must complete synchronously in a '
            'browser. The safe fallback was returned; use SynchronousFuture '
            'when a custom decision is required.',
      );
      return fallback;
    }
    if (error != null) {
      return fallback;
    }
    return result as T;
  }

  bool _handleJavaScriptConfirmDialog(String message, String url) {
    final Future<bool> Function(JavaScriptConfirmDialogRequest request)?
    callback = _onJavaScriptConfirmDialog;
    if (callback == null) {
      return false;
    }

    return _completeJavaScriptDialogSynchronously<bool>(
      callback(JavaScriptConfirmDialogRequest(message: message, url: url)),
      'confirm',
      false,
    );
  }

  String _handleJavaScriptTextInputDialog(
    String message,
    String url,
    String? defaultText,
  ) {
    final Future<String> Function(JavaScriptTextInputDialogRequest request)?
    callback = _onJavaScriptTextInputDialog;
    if (callback == null) {
      return defaultText ?? '';
    }

    return _completeJavaScriptDialogSynchronously<String>(
      callback(
        JavaScriptTextInputDialogRequest(
          message: message,
          url: url,
          defaultText: defaultText,
        ),
      ),
      'prompt',
      defaultText ?? '',
    );
  }

  void _installJavaScriptConfirmDialogHook() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_onJavaScriptConfirmDialog == null) {
      return;
    }

    _updateJavaScriptDialogBridge();
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window == null) {
      if (_hasIsolatedBridge) {
        _logLimitationOnce(
          'isolated-confirm-dialog',
          'Custom confirm callbacks cannot synchronously cross an isolated '
              'iframe boundary. The browser-native confirm dialog is kept.',
        );
      }
      return;
    }
    window.evaluateJavaScript('''
      (function() {
        if (window.__webviewAllConfirmDialogHookInstalled) {
          return;
        }
        window.__webviewAllConfirmDialogHookInstalled = true;
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
        const originalConfirm = window.confirm.bind(window);
        window.confirm = function(message) {
          const bridgeRoot = window.parent &&
              window.parent[${jsonEncode(_javaScriptDialogBridgeName)}];
          const bridge = bridgeRoot && bridgeRoot[webViewId];
          if (!bridge || !bridge.confirm) {
            return originalConfirm(message);
          }
          return Boolean(bridge.confirm(String(message), window.location.href));
        };
      })();
      ''');
  }

  void _installJavaScriptTextInputDialogHook() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_onJavaScriptTextInputDialog == null) {
      return;
    }

    _updateJavaScriptDialogBridge();
    final web.Window? window = _tryReadAccessibleContentWindow();
    if (window == null) {
      if (_hasIsolatedBridge) {
        _logLimitationOnce(
          'isolated-prompt-dialog',
          'Custom prompt callbacks cannot synchronously cross an isolated '
              'iframe boundary. The browser-native prompt dialog is kept.',
        );
      }
      return;
    }
    window.evaluateJavaScript('''
      (function() {
        if (window.__webviewAllTextInputDialogHookInstalled) {
          return;
        }
        window.__webviewAllTextInputDialogHookInstalled = true;
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
        const originalPrompt = window.prompt.bind(window);
        window.prompt = function(message, defaultText) {
          const bridgeRoot = window.parent &&
              window.parent[${jsonEncode(_javaScriptDialogBridgeName)}];
          const bridge = bridgeRoot && bridgeRoot[webViewId];
          if (!bridge || !bridge.prompt) {
            return originalPrompt(message, defaultText);
          }
          const result = bridge.prompt(
            String(message),
            window.location.href,
            defaultText == null ? null : String(defaultText)
          );
          return result == null ? null : String(result);
        };
      })();
      ''');
  }

  void _installPlatformPermissionRequestHook() {
    if (_javaScriptMode == JavaScriptMode.disabled) {
      return;
    }
    if (_onPlatformPermissionRequest == null) {
      return;
    }

    _installScriptBestEffort('platform permission forwarding', '''
      (function() {
        if (window.__webviewAllPermissionRequestHookInstalled) {
          return;
        }
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
          return;
        }

        window.__webviewAllPermissionRequestHookInstalled = true;
        const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
        const originalGetUserMedia =
          navigator.mediaDevices.getUserMedia.bind(navigator.mediaDevices);
        const pending = new Map();
        let nextRequestId = 0;

        window.addEventListener('message', function(event) {
          if (event.source !== window.parent) {
            return;
          }
          const data = event.data;
          if (!data ||
              data["$_channelMessageType"] !== "$_platformPermissionDecisionMessageType" ||
              data.webViewId !== webViewId) {
            return;
          }

          const request = pending.get(data.requestId);
          if (!request) {
            return;
          }
          pending.delete(data.requestId);
          if (data.granted) {
            request.resolve();
          } else {
            request.reject(new DOMException(
              'Permission denied by host application.',
              'NotAllowedError'
            ));
          }
        });

        navigator.mediaDevices.getUserMedia = function(constraints) {
          const requestedTypes = [];
          if (constraints && constraints.video) {
            requestedTypes.push('camera');
          }
          if (constraints && constraints.audio) {
            requestedTypes.push('microphone');
          }
          if (requestedTypes.length === 0) {
            return originalGetUserMedia(constraints);
          }

          const requestId = String(++nextRequestId);
          const permission = new Promise(function(resolve, reject) {
            pending.set(requestId, { resolve: resolve, reject: reject });
          });
          window.parent.postMessage({
            "$_channelMessageType": "$_platformPermissionRequestMessageType",
            "webViewId": webViewId,
            "requestId": requestId,
            "types": requestedTypes
          }, "*");

          return permission.then(function() {
            return originalGetUserMedia(constraints);
          });
        };
      })();
      ''');
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    _onJavaScriptConfirmDialog = onJavaScriptConfirmDialog;
    _installJavaScriptConfirmDialogHook();
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    _onJavaScriptTextInputDialog = onJavaScriptTextInputDialog;
    _installJavaScriptTextInputDialogHook();
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    _onPlatformPermissionRequest = onPermissionRequest;
    _installPlatformPermissionRequestHook();
  }

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    _webWebViewParams.iFrame.style.setProperty(
      'overscroll-behavior',
      switch (mode) {
        WebViewOverScrollMode.always => 'auto',
        WebViewOverScrollMode.ifContentScrolls => 'contain',
        WebViewOverScrollMode.never => 'none',
      },
    );
  }

  Future<void> _loadUrl(String url, {required bool updateHistory}) async {
    if (!await _shouldNavigate(url)) {
      return;
    }

    _currentUrl = url;
    _navigationDelegate?.onPageStarted?.call(url);
    _navigationDelegate?.onProgress?.call(0);
    _navigationDelegate?.onUrlChange?.call(UrlChange(url: url));

    if (updateHistory) {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(url);
      _historyIndex = _history.length - 1;
    }

    _lastLoadedType = _NavigationLoadType.url;
    _lastXhrRequestParams = null;
    _resetIsolatedBridge();
    _webWebViewParams.iFrame.src = url;
  }

  Future<bool> _shouldNavigate(String url) async {
    final NavigationRequestCallback? callback =
        _navigationDelegate?.onNavigationRequest;
    if (callback == null) {
      return true;
    }

    final NavigationDecision decision = await callback(
      NavigationRequest(url: url, isMainFrame: true),
    );
    return decision == NavigationDecision.navigate;
  }

  /// Performs an AJAX request defined by [params].
  Future<void> _updateIFrameFromXhr(
    LoadRequestParams params, {
    bool updateHistory = true,
  }) async {
    if (!await _shouldNavigate(params.uri.toString())) {
      return;
    }

    _currentUrl = params.uri.toString();
    _navigationDelegate?.onPageStarted?.call(_currentUrl!);
    _navigationDelegate?.onProgress?.call(0);
    _navigationDelegate?.onUrlChange?.call(UrlChange(url: _currentUrl));

    final web.Response response;
    try {
      response =
          await _webWebViewParams.httpRequestFactory.request(
                params.uri.toString(),
                method: params.method.serialize(),
                requestHeaders: params.headers,
                sendData: params.body,
              )
              as web.Response;
    } catch (error) {
      _navigationDelegate?.onWebResourceError?.call(
        WebResourceError(
          errorCode: 0,
          description: error.toString(),
          errorType: WebResourceErrorType.connect,
          isForMainFrame: true,
          url: params.uri.toString(),
        ),
      );
      rethrow;
    }

    final Map<String, String> responseHeaders = _headersFromResponse(response);
    final String? contentTypeHeader = responseHeaders['content-type'];
    final String header = contentTypeHeader ?? 'text/html';

    if (response.status >= 400) {
      _navigationDelegate?.onHttpError?.call(
        HttpResponseError(
          request: WebWebResourceRequest._(
            uri: params.uri,
            method: params.method.serialize().toUpperCase(),
            headers: params.headers,
            isForMainFrame: true,
          ),
          response: WebWebResourceResponse._(
            uri: params.uri,
            statusCode: response.status,
            headers: responseHeaders,
            mimeType: _mimeTypeFromContentTypeHeader(contentTypeHeader),
            reasonPhrase: response.statusText.isEmpty
                ? null
                : response.statusText,
          ),
        ),
      );
    }

    final contentType = ContentType.parse(header);
    final Encoding encoding = Encoding.getByName(contentType.charset) ?? utf8;
    final ByteBuffer responseBuffer =
        (await response.arrayBuffer().toDart).toDart;
    final String responseBody = _decodeResponseBody(
      encoding,
      responseBuffer.asUint8List(),
    );

    if (updateHistory) {
      _markLogicalUrlHistoryEntry(params.uri.toString());
    }

    _lastXhrRequestParams = params;
    _lastLoadedType = _NavigationLoadType.xhrResponse;
    final String mimeType = contentType.mimeType ?? 'text/html';
    final String renderedBody;
    if (_isHtmlMimeType(mimeType) &&
        _javaScriptMode == JavaScriptMode.unrestricted &&
        _currentSandboxAllowsScripts) {
      _prepareIsolatedBridge();
      renderedBody = _injectIntoDocumentHead(
        responseBody,
        '${_baseElement(params.uri.toString())}'
        '${_isolatedBridgeBootstrap(_isolatedBridgeGeneration)}',
      );
    } else {
      _resetIsolatedBridge();
      renderedBody = _isHtmlMimeType(mimeType)
          ? _injectIntoDocumentHead(
              responseBody,
              _baseElement(params.uri.toString()),
            )
          : responseBody;
    }
    _webWebViewParams.iFrame.src = Uri.dataFromString(
      renderedBody,
      mimeType: mimeType,
      encoding: encoding,
    ).toString();
  }

  String _injectBaseUrl(String html, String? baseUrl) {
    if (baseUrl == null || baseUrl.isEmpty) {
      return html;
    }

    return _injectIntoDocumentHead(html, _baseElement(baseUrl));
  }

  String _baseElement(String baseUrl) {
    final String escaped = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(baseUrl);
    return '<base href="$escaped">';
  }

  String _decodeResponseBody(Encoding encoding, Uint8List bytes) {
    try {
      return encoding.decode(bytes);
    } on FormatException catch (error) {
      debugPrint(
        'webview_all_web: response bytes were invalid for '
        '${encoding.name}; decoding as malformed UTF-8 instead: $error',
      );
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String _injectIntoDocumentHead(String html, String content) {
    final RegExp headExp = RegExp(r'<head[^>]*>', caseSensitive: false);
    final Match? match = headExp.firstMatch(html);
    if (match != null) {
      return html.replaceRange(match.end, match.end, content);
    }

    final RegExp htmlExp = RegExp(r'<html[^>]*>', caseSensitive: false);
    final Match? htmlMatch = htmlExp.firstMatch(html);
    if (htmlMatch != null) {
      return html.replaceRange(
        htmlMatch.end,
        htmlMatch.end,
        '<head>$content</head>',
      );
    }

    final RegExp doctypeExp = RegExp(
      r'^\s*<!doctype[^>]*>',
      caseSensitive: false,
    );
    final Match? doctypeMatch = doctypeExp.firstMatch(html);
    if (doctypeMatch != null) {
      return html.replaceRange(
        doctypeMatch.end,
        doctypeMatch.end,
        '<head>$content</head>',
      );
    }
    return '<head>$content</head>$html';
  }

  bool _isHtmlMimeType(String mimeType) {
    return mimeType.trim().toLowerCase() == 'text/html';
  }

  String _isolatedBridgeBootstrap(int generation) {
    return '''
<script>
(function() {
  'use strict';
  const messageTypeKey = ${jsonEncode(_channelMessageType)};
  const requestType = ${jsonEncode(_isolatedBridgeRequestMessageType)};
  const responseType = ${jsonEncode(_isolatedBridgeResponseMessageType)};
  const readyType = ${jsonEncode(_isolatedBridgeReadyMessageType)};
  const scrollType = ${jsonEncode(_isolatedBridgeScrollMessageType)};
  const webViewId = ${jsonEncode(_webWebViewParams.iFrame.id)};
  const generation = $generation;

  function send(message) {
    message[messageTypeKey] = message.type;
    delete message.type;
    message.webViewId = webViewId;
    message.generation = generation;
    window.parent.postMessage(message, '*');
  }

  function respond(requestId, result) {
    send({type: responseType, requestId: requestId, ok: true, result: result});
  }

  function fail(requestId, error) {
    send({
      type: responseType,
      requestId: requestId,
      ok: false,
      errorName: error && error.name ? String(error.name) : 'Error',
      errorMessage: error && error.message ? String(error.message) : String(error)
    });
  }

  window.addEventListener('message', function(event) {
    if (event.source !== window.parent) {
      return;
    }
    const data = event.data;
    if (!data ||
        data[messageTypeKey] !== requestType ||
        data.webViewId !== webViewId ||
        data.generation !== generation) {
      return;
    }

    const requestId = data.requestId;
    const payload = data.payload || {};
    try {
      switch (data.action) {
        case 'evaluate':
          (0, eval)(String(payload.script || ''));
          respond(requestId, null);
          return;
        case 'evaluateReturningResult': {
          const value = (0, eval)(String(payload.script || ''));
          const encoded = JSON.stringify(value);
          respond(requestId, encoded === undefined ? null : JSON.parse(encoded));
          return;
        }
        case 'getScrollPosition':
          respond(requestId, {x: window.scrollX, y: window.scrollY});
          return;
        case 'scrollTo':
          window.scrollTo(Number(payload.x || 0), Number(payload.y || 0));
          respond(requestId, null);
          return;
        case 'scrollBy':
          window.scrollBy(Number(payload.x || 0), Number(payload.y || 0));
          respond(requestId, null);
          return;
        case 'getTitle':
          respond(requestId, document.title || null);
          return;
        default:
          throw new Error('Unknown isolated WebView action: ' + data.action);
      }
    } catch (error) {
      fail(requestId, error);
    }
  });

  window.addEventListener('scroll', function() {
    send({type: scrollType, x: window.scrollX, y: window.scrollY});
  }, {passive: true});

  send({type: readyType});
})();
</script>
''';
  }

  String? _tryReadCurrentFrameUrl() {
    try {
      final String? href =
          _webWebViewParams.iFrame.contentWindow?.location.href;
      if (href == null || href.startsWith('data:')) {
        return _currentUrl;
      }
      return href;
    } catch (_) {
      return _currentUrl;
    }
  }

  bool get _shouldPreserveLogicalUrl {
    return _lastLoadedType == _NavigationLoadType.html ||
        _lastLoadedType == _NavigationLoadType.xhrResponse;
  }

  void _markLogicalUrlHistoryEntry(String url) {
    if (_historyIndex < _history.length - 1) {
      _history.removeRange(_historyIndex + 1, _history.length);
    }
    _history.add(url);
    _historyIndex = _history.length - 1;
  }

  String _resolveFlutterAssetUrl(String key) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Asset key must not be empty.');
    }

    final String normalized = key.startsWith('/') ? key.substring(1) : key;
    if (normalized.isEmpty) {
      throw ArgumentError.value(key, 'key', 'Asset key must not be empty.');
    }

    final String encodedKey = normalized
        .split('/')
        .map(Uri.encodeComponent)
        .join('/');
    return Uri.base.resolve('assets/$encodedKey').toString();
  }

  Map<String, String> _headersFromResponse(web.Response response) {
    final Map<String, String> headers = <String, String>{};
    response.headers.forEach(
      ((JSString value, JSString name, JSAny _) {
        headers[name.toDart] = value.toDart;
      }).toJS,
    );
    return headers;
  }

  String? _mimeTypeFromContentTypeHeader(String? header) {
    final String? mimeType = header?.split(';').first.trim().toLowerCase();
    return mimeType == null || mimeType.isEmpty ? null : mimeType;
  }

  String _cssColorFrom(Color color) {
    final int alpha = (color.a * 255.0).round().clamp(0, 255);
    final int red = (color.r * 255.0).round().clamp(0, 255);
    final int green = (color.g * 255.0).round().clamp(0, 255);
    final int blue = (color.b * 255.0).round().clamp(0, 255);
    return 'rgba($red, $green, $blue, ${alpha / 255})';
  }
}

enum _NavigationLoadType { none, url, html, xhrResponse }

/// Web implementation of [WebResourceRequest] for XHR-backed loads.
class WebWebResourceRequest extends WebResourceRequest {
  /// Creates a new [WebWebResourceRequest].
  const WebWebResourceRequest._({
    required super.uri,
    this.method,
    this.headers = const <String, String>{},
    this.isForMainFrame,
  });

  /// The HTTP method used for the request, when known.
  final String? method;

  /// The request headers used for the request.
  final Map<String, String> headers;

  /// Whether this request was made for the main frame, when known.
  final bool? isForMainFrame;
}

/// Web implementation of [WebResourceResponse] for Fetch-backed loads.
class WebWebResourceResponse extends WebResourceResponse {
  /// Creates a new [WebWebResourceResponse].
  const WebWebResourceResponse._({
    required super.uri,
    required super.statusCode,
    required super.headers,
    this.mimeType,
    this.reasonPhrase,
  });

  /// The MIME type parsed from the response `content-type` header, when known.
  final String? mimeType;

  /// The HTTP status text reported by Fetch, when available.
  final String? reasonPhrase;
}

/// Web implementation of [PlatformWebViewPermissionRequest].
class WebWebViewPermissionRequest extends PlatformWebViewPermissionRequest {
  WebWebViewPermissionRequest._({
    required super.types,
    required void Function(bool granted) onDecision,
  }) : _decision = _WebWebViewPermissionDecision(onDecision);

  final _WebWebViewPermissionDecision _decision;

  @override
  Future<void> grant() async {
    _decision.decide(true);
  }

  @override
  Future<void> deny() async {
    _decision.decide(false);
  }
}

class _WebWebViewPermissionDecision {
  _WebWebViewPermissionDecision(this._onDecision);

  final void Function(bool granted) _onDecision;
  bool _hasDecision = false;

  void decide(bool granted) {
    if (_hasDecision) {
      return;
    }
    _hasDecision = true;
    _onDecision(granted);
  }
}

/// Web-specific creation parameters for [WebWebViewWidget].
@immutable
class WebWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  /// Creates a new [WebWebViewWidgetCreationParams].
  const WebWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
  });

  /// Creates a [WebWebViewWidgetCreationParams] from generic params.
  WebWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params,
  ) : this(
        key: params.key,
        controller: params.controller,
        layoutDirection: params.layoutDirection,
        gestureRecognizers: params.gestureRecognizers,
      );
}

/// An implementation of [PlatformWebViewWidget] using Flutter for Web API.
class WebWebViewWidget extends PlatformWebViewWidget {
  /// Constructs a [WebWebViewWidget].
  WebWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(
        params is WebWebViewWidgetCreationParams
            ? params
            : WebWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                params,
              ),
      ) {
    final controller = params.controller as WebWebViewController;
    final WeakReference<_WebWebViewDisposal> weakDisposal =
        WeakReference<_WebWebViewDisposal>(controller._nativeDisposal);
    ui_web.platformViewRegistry.registerViewFactory(
      controller._webWebViewParams.iFrame.id,
      (int viewId) {
        return weakDisposal.target?.iFrame ??
            (throw StateError('The Web WebView controller was disposed.'));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(
      key: params.key,
      viewType: (params.controller as WebWebViewController)
          ._webWebViewParams
          .iFrame
          .id,
    );
  }
}

class _WebWebViewDisposal {
  _WebWebViewDisposal({
    required this.iFrame,
    required this.messageEventListener,
    required this.loadEventSubscription,
    required this.clearJavaScriptDialogBridge,
  });

  final web.HTMLIFrameElement iFrame;
  final web.EventListener messageEventListener;
  final StreamSubscription<web.Event> loadEventSubscription;
  final void Function() clearJavaScriptDialogBridge;
  web.EventListener? _scrollEventListener;
  web.Window? scrollEventListenerWindow;
  Future<void>? _disposeFuture;

  void setScrollListener(web.Window window, web.EventListener listener) {
    scrollEventListenerWindow = window;
    _scrollEventListener = listener;
  }

  void detachScrollListener() {
    final web.Window? window = scrollEventListenerWindow;
    final web.EventListener? listener = _scrollEventListener;
    if (window != null && listener != null) {
      try {
        window.removeEventListener('scroll', listener);
      } catch (_) {}
    }
    scrollEventListenerWindow = null;
    _scrollEventListener = null;
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    web.window.removeEventListener('message', messageEventListener);
    detachScrollListener();
    try {
      await loadEventSubscription.cancel();
    } finally {
      clearJavaScriptDialogBridge();
      iFrame.remove();
    }
  }
}

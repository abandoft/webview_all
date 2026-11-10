// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show Widget;
import 'package:flutter/services.dart' show PlatformException;
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'platform_navigation_delegate.dart';
import 'platform_webview_cookie_manager.dart';
import 'platform_webview_data_manager.dart';
import 'types/types.dart';
import 'webview_platform.dart' show WebViewPlatform;
import 'webview_javascript_bridge.dart';
import 'javascript_world_invocation.dart';

/// Interface for a platform implementation of a web view controller.
///
/// Platform implementations should extend this class rather than implement it
/// as `webview_all` does not consider newly added methods to be breaking
/// changes. Extending this class (using `extends`) ensures that the subclass
/// will get the default implementation, while platform implementations that
/// `implements` this interface will be broken by newly added
/// [PlatformWebViewController] methods.
abstract class PlatformWebViewController extends PlatformInterface {
  Future<WebViewNetworkCapabilities> getNetworkCapabilities() async =>
      const WebViewNetworkCapabilities();
  Future<bool> setContentRules(List<WebViewContentRule> rules) async {
    debugPrint(
      'webview_all: native resource content rules are unavailable on this platform.',
    );
    return false;
  }

  Future<bool> setRequestDelegate(WebViewRequestDelegate? delegate) async {
    debugPrint(
      'webview_all: native HTTP(S) request interception is unavailable on this platform. No JavaScript fetch/XHR replacement was installed.',
    );
    return false;
  }

  Future<bool> setCustomSchemeDelegate(
    WebViewResourceDelegate? delegate,
  ) async {
    debugPrint(
      'webview_all: custom URL scheme handling is unavailable on this platform.',
    );
    return false;
  }

  Future<Uint8List?> createArchive({
    required WebViewArchiveFormat format,
  }) async {
    debugPrint(
      'webview_all: native ${format.name} page archives are unavailable on this platform.',
    );
    return null;
  }

  Future<bool> setContextMenuEnabled(bool enabled) async {
    debugPrint(
      'webview_all: native context-menu control is unavailable on this platform. Existing native behavior was retained.',
    );
    return false;
  }

  Future<bool> setAudioMuted(bool muted) async {
    debugPrint(
      'webview_all: per-view native audio muting is unavailable on this platform.',
    );
    return false;
  }

  Future<bool> pauseMedia() async {
    debugPrint(
      'webview_all: pausing all native media in this view is unavailable on this platform.',
    );
    return false;
  }

  Future<bool> setMediaPlaybackSuspended(bool suspended) async {
    debugPrint(
      'webview_all: suspending and preventing media playback in this view is unavailable on this platform.',
    );
    return false;
  }

  /// Creates a separately configured view in exactly the same native store.
  /// The caller owns its lifetime; closing either view must retain the other.
  Future<PlatformWebViewController?> createRelatedController() async {
    debugPrint(
      'webview_all: creating another controller in this data store is unavailable.',
    );
    return null;
  }

  Future<WebViewPrintJob?> printPage({String jobName = 'Web page'}) async {
    debugPrint(
      'webview_all: the system print flow is unavailable on this platform.',
    );
    return null;
  }

  @protected
  Future<WebViewPrintJob?> startNativePrint(
    String jobName,
    Future<Object?> Function(String method, Map<String, Object?> arguments)
    invoke,
  ) async {
    if (jobName.trim().isEmpty || jobName.length > 256) {
      debugPrint('webview_all: print job names must contain 1–256 characters.');
      return null;
    }
    WebViewPrintState parse(Object? value) =>
        WebViewPrintState.values.firstWhere(
          (v) => v.name == value,
          orElse: () => WebViewPrintState.unknown,
        );
    try {
      // A user may leave a native print panel open; do not time it out.
      final raw = await invoke('printPage', {'jobName': jobName});
      if (raw is! Map) {
        debugPrint(
          'webview_all: the engine could not open a system print flow. The view may need an attached native window.',
        );
        return null;
      }
      final id = raw['jobId'];
      final args = <String, Object?>{'jobId': id};
      return WebViewPrintJob(
        initialState: parse(raw['state']),
        readState: raw['canQuery'] == true
            ? () async => parse(await invoke('printJobState', args))
            : null,
        cancel: raw['canCancel'] == true
            ? () async => await invoke('cancelPrintJob', args) == true
            : null,
        release: id is String
            ? () async {
                await invoke('releasePrintJob', args);
              }
            : null,
      );
    } catch (error) {
      debugPrint('webview_all: opening the print flow failed: $error');
      return null;
    }
  }

  /// Clears this view's native back/forward history, retaining its current page.
  Future<bool> clearNavigationHistory() async {
    debugPrint(
      'webview_all: clearing native navigation history is unavailable on this platform. The history was retained.',
    );
    return false;
  }

  Future<WebViewNavigationState?> saveNavigationState() async {
    debugPrint(
      'webview_all: native navigation-state snapshots are unavailable on this platform. No URL-only substitute was created.',
    );
    return null;
  }

  Future<bool> restoreNavigationState(WebViewNavigationState state) async {
    debugPrint(
      'webview_all: restoring native navigation state is unavailable on this platform. The current page was retained.',
    );
    return false;
  }

  @protected
  bool acceptsNavigationState(WebViewNavigationState state, String platform) {
    if (state.isDisposed || state.platform != platform) {
      debugPrint(
        'webview_all: this navigation snapshot is disposed or belongs to another platform. The current page was retained.',
      );
      return false;
    }
    return true;
  }

  /// Bounds native browser operations and contains unsupported/runtime errors.
  @protected
  Future<T> browserOperation<T>(
    String name,
    T fallback,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation().timeout(const Duration(seconds: 30));
    } catch (error) {
      debugPrint('webview_all: $name failed: $error');
      return fallback;
    }
  }

  WebViewFullscreenDelegate? _fullscreenDelegate;
  WebViewFullscreenRequest? _fullscreenRequest;
  FutureOr<void> Function(WebViewProcessFailure)? _onProcessFailed;

  Future<void> setFullscreenDelegate(
    WebViewFullscreenDelegate? delegate,
  ) async {
    debugPrint(
      'webview_all: native fullscreen notifications are unavailable on this platform. Existing platform behavior is retained.',
    );
  }

  Future<bool> exitFullscreen() async {
    debugPrint(
      'webview_all: exiting native fullscreen is unavailable on this platform.',
    );
    return false;
  }

  /// Requests DOM fullscreen exit without affecting other system media UI.
  /// The native exit event confirms completion; true means the request was sent.
  @protected
  Future<bool> exitDocumentFullscreen() async {
    try {
      final result = await runJavaScriptReturningResult('''
(() => {
  if (!(document.fullscreenElement || document.webkitFullscreenElement)) return false;
  const exit = document.exitFullscreen || document.webkitExitFullscreen || document.webkitCancelFullScreen;
  if (typeof exit !== 'function') return false;
  const pending = exit.call(document);
  if (pending && typeof pending.catch === 'function') pending.catch(() => {});
  return true;
})()
''');
      final accepted = result == true || result == 'true';
      if (!accepted) {
        debugPrint(
          'webview_all: this fullscreen presentation has no DOM exit API. Use the platform media controls to dismiss system video UI.',
        );
      }
      return accepted;
    } catch (error) {
      debugPrint('webview_all: exiting document fullscreen failed: $error');
      return false;
    }
  }

  Future<void> setOnProcessFailed(
    FutureOr<void> Function(WebViewProcessFailure)? callback,
  ) async {
    debugPrint(
      'webview_all: renderer process failures cannot be observed on this platform.',
    );
  }

  @protected
  bool get hasFullscreenDelegate => _fullscreenDelegate != null;

  @protected
  bool get isFullscreenActive => _fullscreenRequest != null;

  @protected
  Future<void> updateFullscreenDelegate(
    WebViewFullscreenDelegate? delegate,
  ) async {
    if (identical(_fullscreenDelegate, delegate)) return;
    if (_fullscreenRequest != null) {
      await _fullscreenRequest!.exit();
      unawaited(notifyFullscreenExited());
    }
    _fullscreenDelegate = delegate;
  }

  @protected
  Future<void> notifyFullscreenEntered({Widget? content}) async {
    final delegate = _fullscreenDelegate;
    if (delegate == null || _fullscreenRequest != null) return;
    late final WebViewFullscreenRequest request;
    request = WebViewFullscreenRequest(
      content: content,
      onExit: () async {
        if (!identical(_fullscreenRequest, request)) return false;
        try {
          return await exitFullscreen().timeout(const Duration(seconds: 10));
        } catch (error) {
          debugPrint('webview_all: exiting fullscreen failed: $error');
          return false;
        }
      },
    );
    _fullscreenRequest = request;
    try {
      await delegate.onEnter(request);
    } catch (error) {
      debugPrint('webview_all: the fullscreen enter callback failed: $error');
      await request.exit();
    }
  }

  @protected
  Future<void> notifyFullscreenExited() async {
    if (_fullscreenRequest == null) return;
    _fullscreenRequest = null;
    try {
      await _fullscreenDelegate?.onExit();
    } catch (error) {
      debugPrint('webview_all: the fullscreen exit callback failed: $error');
    }
  }

  @protected
  void updateProcessFailureCallback(
    FutureOr<void> Function(WebViewProcessFailure)? callback,
  ) {
    _onProcessFailed = callback;
  }

  /// Call after ending any presentation. Application callbacks must never keep
  /// native controller disposal pending (they may themselves await disposal).
  @protected
  void disposeBrowserLifecycleCallbacks() {
    _capturesClosed = true;
    _cancelPageCaptures();
    if (_fullscreenRequest != null) unawaited(notifyFullscreenExited());
    _fullscreenDelegate = null;
    _onProcessFailed = null;
  }

  @protected
  Future<void> notifyProcessFailed(WebViewProcessFailure failure) async {
    if (failure.recovery != WebViewProcessRecovery.none) {
      _cancelPageCaptures();
      cancelJavaScriptHandlerCalls();
      unawaited(notifyFullscreenExited());
    }
    try {
      if (_onProcessFailed != null) {
        await _onProcessFailed!(failure);
      } else {
        debugPrint(
          'webview_all: ${failure.kind.name}; recovery: ${failure.recovery.name}. ${failure.description ?? ''}',
        );
      }
    } catch (error) {
      debugPrint('webview_all: the process-failure callback failed: $error');
    }
  }

  Future<void> _textSearchTail = Future<void>.value();

  /// Serializes engines whose search notifications carry no request identifier.
  @protected
  Future<T> serializeTextSearch<T>(Future<T> Function() operation) {
    final result = _textSearchTail.then((_) => operation());
    _textSearchTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  /// Installs native child-window handling; null restores the popup policy.
  Future<void> setNewWindowDelegate(
    FutureOr<void> Function(WebViewNewWindowRequest<PlatformWebViewController>)?
    delegate,
  ) async {
    debugPrint(
      'webview_all: native child-window attachment is unavailable on this platform; the existing popup policy is retained.',
    );
  }

  /// Receives native window.close requests. The app owns view removal/disposal.
  Future<void> setOnWindowCloseRequested(VoidCallback? callback) async {
    debugPrint(
      'webview_all: native window-close notifications are unavailable on this platform.',
    );
  }

  Future<void> _captureTail = Future<void>.value();
  int _captureGeneration = 0;
  final _captureCancellations = <Completer<Uint8List?>>{};
  bool _capturesClosed = false;

  void _cancelPageCaptures() {
    _captureGeneration++;
    for (final cancellation in _captureCancellations) {
      cancellation.complete(null);
    }
    _captureCancellations.clear();
  }

  /// Serializes capture/printing operations and reports native failures safely.
  @protected
  Future<Uint8List?> capturePageData(
    String operation,
    Future<Uint8List?> Function() capture,
  ) {
    final generation = _captureGeneration;
    final result = _captureTail.then((_) async {
      if (_capturesClosed || generation != _captureGeneration) return null;
      try {
        final cancellation = Completer<Uint8List?>();
        _captureCancellations.add(cancellation);
        final timedOut = Completer<Uint8List?>();
        final timer = Timer(const Duration(seconds: 40), () {
          timedOut.completeError(TimeoutException('$operation timed out.'));
        });
        final Uint8List? bytes;
        try {
          bytes = await Future.any<Uint8List?>([
            Future<Uint8List?>.sync(capture),
            cancellation.future,
            timedOut.future,
          ]);
        } finally {
          timer.cancel();
          _captureCancellations.remove(cancellation);
        }
        if (_capturesClosed || generation != _captureGeneration) return null;
        if (bytes == null) {
          debugPrint(
            'webview_all: $operation returned no data; the page may be unavailable or the engine may not support this operation.',
          );
        }
        return bytes;
      } catch (error) {
        debugPrint('webview_all: $operation failed: $error');
        return null;
      }
    });
    _captureTail = result.then<void>((_) {});
    return result;
  }

  /// Captures the visible native page as PNG, or warns and returns null.
  Future<Uint8List?> takeScreenshot({
    WebViewScreenshotOptions options = const WebViewScreenshotOptions(),
  }) async {
    debugPrint(
      'webview_all: native page screenshots are unavailable on this platform.',
    );
    return null;
  }

  /// Exports PDF bytes using native layout defaults, or warns and returns null.
  Future<Uint8List?> createPdf({WebViewPdfOptions? options}) async {
    debugPrint(
      'webview_all: native PDF export is unavailable on this platform.',
    );
    return null;
  }

  @protected
  Future<Uint8List?> captureScreenshot(
    WebViewScreenshotOptions options,
    Future<Uint8List?> Function() capture,
  ) => capturePageData('Screenshot', () async {
    if (options.fullDocument &&
        !(await getBrowserCapabilities()).fullDocumentScreenshot) {
      debugPrint(
        'webview_all: native full-document screenshots are unavailable on this platform/runtime.',
      );
      return null;
    }
    if (!options.scale.isFinite || options.scale <= 0) {
      throw ArgumentError('Screenshot scale must be finite and positive.');
    }
    final region = options.region;
    if (region != null &&
        (!region.isFinite ||
            region.isEmpty ||
            region.left < 0 ||
            region.top < 0)) {
      throw ArgumentError(
        'Screenshot region must be a finite positive rectangle.',
      );
    }
    final bytes = await capture();
    if (bytes == null || options.isDefault) return bytes;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? source;
    ui.Image? output;
    ui.Picture? picture;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > 16 * 1024 * 1024) {
        throw StateError(
          'The source image exceeds the screenshot pixel limit.',
        );
      }
      if (options.region == null && options.scale == 1) return bytes;
      final rect =
          options.region ??
          ui.Rect.fromLTWH(
            0,
            0,
            descriptor.width.toDouble(),
            descriptor.height.toDouble(),
          );
      if (!rect.isFinite ||
          rect.isEmpty ||
          rect.left < 0 ||
          rect.top < 0 ||
          rect.right > descriptor.width ||
          rect.bottom > descriptor.height) {
        throw ArgumentError(
          'Screenshot region must be inside the captured image.',
        );
      }
      final width = (rect.width * options.scale).round();
      final height = (rect.height * options.scale).round();
      if (width <= 0 || height <= 0 || width * height > 16 * 1024 * 1024) {
        throw ArgumentError('The scaled screenshot exceeds the pixel limit.');
      }
      codec = await descriptor.instantiateCodec();
      source = (await codec.getNextFrame()).image;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        rect,
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      picture = recorder.endRecording();
      output = await picture.toImage(width, height);
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      output?.dispose();
      picture?.dispose();
      source?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  });

  /// Queries browser operations without invoking unsupported APIs.
  Future<WebViewBrowserCapabilities> getBrowserCapabilities() async =>
      const WebViewBrowserCapabilities();

  Future<void> stopLoading() async {
    debugPrint(
      'webview_all: stopping page loading is unavailable on this platform.',
    );
  }

  Future<WebViewNavigationHistory?> getNavigationHistory() async {
    debugPrint(
      'webview_all: the native navigation history is unavailable on this platform.',
    );
    return null;
  }

  Future<bool> goToHistoryIndex(int index) async {
    debugPrint(
      'webview_all: navigating to a history index is unavailable on this platform.',
    );
    return false;
  }

  /// Finds rendered text. Repeating the same query advances the selected match.
  Future<WebViewFindResult?> findText(
    String text, {
    bool forward = true,
    bool caseSensitive = false,
    bool wrapAround = true,
  }) async {
    debugPrint('webview_all: text search is unavailable on this platform.');
    return null;
  }

  Future<void> clearFindMatches() async {
    debugPrint(
      'webview_all: clearing text search is unavailable on this platform.',
    );
  }

  Future<void> setPopupPolicy(WebViewPopupWindowPolicy policy) async {
    debugPrint(
      'webview_all: popup policy ${policy.name} is unavailable on this platform.',
    );
  }

  Future<void> setFileSelector(WebViewFileSelector? selector) async {
    if (selector != null) {
      debugPrint(
        'webview_all: custom file selection is unavailable on this platform; the engine retains its normal file input behavior.',
      );
    }
  }

  Future<void> setMediaPlaybackRequiresUserGesture(bool require) async {
    debugPrint(
      'webview_all: changing the media user-gesture requirement is unavailable on this platform.',
    );
  }

  /// Creates a new [PlatformWebViewController]
  factory PlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    assert(
      WebViewPlatform.instance != null,
      'A platform implementation for `webview_all` has not been set. Please '
      'ensure that an implementation of `WebViewPlatform` has been set to '
      '`WebViewPlatform.instance` before use. For unit testing, '
      '`WebViewPlatform.instance` can be set with your own test implementation.',
    );
    final PlatformWebViewController webViewControllerDelegate = WebViewPlatform
        .instance!
        .createPlatformWebViewController(params);
    PlatformInterface.verify(webViewControllerDelegate, _token);
    return webViewControllerDelegate;
  }

  /// Used by the platform implementation to create a new [PlatformWebViewController].
  ///
  /// Should only be used by platform implementations because they can't extend
  /// a class that only contains a factory constructor.
  @protected
  PlatformWebViewController.implementation(this.params) : super(token: _token);

  static final Object _token = Object();

  /// The parameters used to initialize the [PlatformWebViewController].
  final PlatformWebViewControllerCreationParams params;

  WebViewJavaScriptBridge? _javaScriptHandlerBridge;
  final Set<String> _javaScriptBridgeScripts = {};
  int _javaScriptDocumentGeneration = 0;
  bool _javaScriptHandlersDisposed = false;

  /// Features available in this engine. Unsupported additions warn and return
  /// without changing the existing page-world JavaScript APIs.
  Future<WebViewJavaScriptCapabilities> getJavaScriptCapabilities({
    WebViewJavaScriptWorld world = WebViewJavaScriptWorld.page,
  }) async => const WebViewJavaScriptCapabilities();

  Future<bool> addJavaScriptHandler(WebViewJavaScriptHandlerParams params) {
    if (_javaScriptHandlersDisposed) {
      debugPrint(
        'webview_all: JavaScript handler registration was skipped because the WebView is closed.',
      );
      return Future<bool>.value(false);
    }
    return (_javaScriptHandlerBridge ??= WebViewJavaScriptBridge(
      this,
    )).add(params);
  }

  Future<void> removeJavaScriptHandler(
    String name, {
    WebViewJavaScriptWorld world = WebViewJavaScriptWorld.page,
  }) async {
    await _javaScriptHandlerBridge?.remove(name, world);
  }

  Future<void> removeAllJavaScriptHandlers() async {
    await _javaScriptHandlerBridge?.removeAll();
  }

  /// Invalidates Dart-to-JavaScript evaluations when navigation is requested.
  /// Pending JavaScript-to-Dart handlers stay alive until navigation starts.
  @protected
  void prepareJavaScriptForNavigation() {
    _javaScriptDocumentGeneration++;
  }

  @protected
  void cancelJavaScriptHandlerCalls() {
    prepareJavaScriptForNavigation();
    _javaScriptHandlerBridge?.documentChanged();
  }

  @protected
  void disposeJavaScriptHandlers() {
    _javaScriptHandlersDisposed = true;
    _javaScriptDocumentGeneration++;
    _javaScriptHandlerBridge?.close();
  }

  @protected
  bool isJavaScriptBridgeScript(String identifier) =>
      _javaScriptBridgeScripts.contains(identifier);

  /// Installs an internal script kept by removeAllUserScripts.
  Future<String?> installJavaScriptBridgeScript(
    WebViewUserScript script,
  ) async {
    final identifier = await addUserScript(script);
    _javaScriptBridgeScripts.add(identifier);
    return identifier;
  }

  @protected
  Future<Object?> invokeAsyncJavaScriptInWorld(
    JavaScriptInvocationParams params,
  ) async {
    final caps = await getJavaScriptCapabilities(world: params.world);
    if (!caps.supportsWorld(params.world)) {
      debugPrint(
        'webview_all: Isolated JavaScript execution was skipped because it is unavailable.',
      );
      return null;
    }
    final generation = _javaScriptDocumentGeneration;
    try {
      return await invokeJavaScriptInWorld(
        params,
        evaluate: (source) => evaluateJavaScriptInWorld(source, params.world),
        isCurrentDocument: () =>
            !_javaScriptHandlersDisposed &&
            generation == _javaScriptDocumentGeneration,
      );
    } on PlatformException catch (error) {
      if (error.code != 'javascript-world-unavailable') rethrow;
      debugPrint(
        'webview_all: Isolated JavaScript invocation was skipped. ${error.message}',
      );
      return null;
    }
  }

  /// Internal world-aware channel hook. Native adapters override for isolation.
  Future<void> addJavaScriptChannelInWorld(
    JavaScriptChannelParams params,
    WebViewJavaScriptWorld world,
  ) {
    if (world.isPage) return addJavaScriptChannel(params);
    throw UnsupportedError('Isolated JavaScript channels are unavailable.');
  }

  /// Internal world-aware execution hook.
  Future<Object?> evaluateJavaScriptInWorld(
    String source,
    WebViewJavaScriptWorld world,
  ) {
    if (world.isPage) return runJavaScriptReturningResult(source);
    throw UnsupportedError('Isolated JavaScript execution is unavailable.');
  }

  Future<void> runJavaScriptInWorld(
    String source,
    WebViewJavaScriptWorld world,
  ) async {
    if (world.isPage) {
      await runJavaScript(source);
    } else {
      await evaluateJavaScriptInWorld(source, world);
    }
  }

  /// Uses a document-start listener on engines without native document-end.
  @protected
  String buildDocumentEndScript(String source) =>
      '''
(function() {
  const run = function() { $source\n };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run, {once: true});
  } else { run(); }
})();
''';

  /// Waits for native creation, including applying the requested data policy.
  Future<void> prepareSession() async {}

  /// Features available for controller-issued application resource URLs.
  WebViewResourceCapabilities get resourceCapabilities =>
      const WebViewResourceCapabilities();

  /// Supplies application resources without changing ordinary network requests.
  Future<void> setResourceDelegate(WebViewResourceDelegate? delegate) async {
    if (delegate != null) {
      debugPrint(
        'webview_all: Application resource URLs are unavailable on this '
        'platform. Browser iframes cannot register native resource handlers. '
        'Use assets hosted by your website instead.',
      );
    }
  }

  /// Creates a resource URL for this controller, or null when unsupported.
  Uri? getResourceUri(String path) {
    debugPrint('webview_all: getResourceUri is unavailable on this platform.');
    return null;
  }

  /// Permanently releases an owned controller, whether displayed or offscreen.
  Future<void> closeWebViewSession() => closeOffscreenWebView();

  PlatformWebViewCookieManager createSessionCookieManager() {
    const message =
        'Session-scoped cookies are not supported on this platform.';
    debugPrint('webview_all: $message');
    return _UnsupportedSessionCookieManager();
  }

  PlatformWebViewDataManager createSessionDataManager() {
    const message =
        'Session-scoped website data is not supported on this platform.';
    debugPrint('webview_all: $message');
    return _UnsupportedSessionDataManager();
  }

  /// Sets optional download handling independently of navigation callbacks.
  /// Removing a delegate restores the platform's existing behavior. Download
  /// observation and available actions differ between engines.
  Future<void> setDownloadDelegate(WebViewDownloadDelegate? delegate) {
    if (delegate == null) return Future<void>.value();
    throw UnsupportedError(
      'Download delegates are not supported on this platform.',
    );
  }

  /// Loads the file located on the specified [absoluteFilePath].
  ///
  /// The [absoluteFilePath] parameter should contain the absolute path to the
  /// file as it is stored on the device. For example:
  /// `/Users/username/Documents/www/index.html`.
  ///
  /// Throws an ArgumentError if the [absoluteFilePath] does not exist.
  Future<void> loadFile(String absoluteFilePath) {
    throw UnimplementedError(
      'loadFile is not implemented on the current platform',
    );
  }

  /// Loads a local HTML file using the provided [params].
  ///
  /// The [params.absoluteFilePath] should contain the absolute path to the file
  /// on the device.
  /// For example: `/Users/username/Documents/www/index.html`.
  ///
  /// Platform-specific implementations may extend [LoadFileParams] to support
  /// additional parameters, such as iOS/macOS-specific read access options.
  Future<void> loadFileWithParams(LoadFileParams params) {
    return loadFile(params.absoluteFilePath);
  }

  /// Loads the Flutter asset specified in the pubspec.yaml file.
  ///
  /// Throws an ArgumentError if [key] is not part of the specified assets
  /// in the pubspec.yaml file.
  Future<void> loadFlutterAsset(String key) {
    throw UnimplementedError(
      'loadFlutterAsset is not implemented on the current platform',
    );
  }

  /// Loads the supplied HTML string.
  ///
  /// The [baseUrl] parameter is used when resolving relative URLs within the
  /// HTML string.
  Future<void> loadHtmlString(String html, {String? baseUrl}) {
    throw UnimplementedError(
      'loadHtmlString is not implemented on the current platform',
    );
  }

  /// Makes a specific HTTP request ands loads the response in the webview.
  ///
  /// [WebViewRequest.method] must be one of the supported HTTP methods
  /// in [WebViewRequestMethod].
  ///
  /// If [WebViewRequest.headers] is not empty, its key-value pairs will be
  /// added as the headers for the request.
  ///
  /// If [WebViewRequest.body] is not null, it will be added as the body
  /// for the request.
  ///
  /// Throws an ArgumentError if [WebViewRequest.uri] has empty scheme.
  Future<void> loadRequest(LoadRequestParams params) {
    throw UnimplementedError(
      'loadRequest is not implemented on the current platform',
    );
  }

  /// Accessor to the current URL that the WebView is displaying.
  ///
  /// If no URL was ever loaded, returns `null`.
  Future<String?> currentUrl() {
    throw UnimplementedError(
      'currentUrl is not implemented on the current platform',
    );
  }

  /// Checks whether there's a back history item.
  Future<bool> canGoBack() {
    throw UnimplementedError(
      'canGoBack is not implemented on the current platform',
    );
  }

  /// Checks whether there's a forward history item.
  Future<bool> canGoForward() {
    throw UnimplementedError(
      'canGoForward is not implemented on the current platform',
    );
  }

  /// Goes back in the history of this WebView.
  ///
  /// If there is no back history item this is a no-op.
  Future<void> goBack() {
    throw UnimplementedError(
      'goBack is not implemented on the current platform',
    );
  }

  /// Goes forward in the history of this WebView.
  ///
  /// If there is no forward history item this is a no-op.
  Future<void> goForward() {
    throw UnimplementedError(
      'goForward is not implemented on the current platform',
    );
  }

  /// Reloads the current URL.
  Future<void> reload() {
    throw UnimplementedError(
      'reload is not implemented on the current platform',
    );
  }

  /// Clears all caches used by the [WebView].
  ///
  /// The following caches are cleared:
  ///	1. Browser HTTP Cache.
  ///	2. [Cache API](https://developers.google.com/web/fundamentals/instant-and-offline/web-storage/cache-api) caches.
  ///    These are not yet supported in iOS WkWebView. Service workers tend to use this cache.
  ///	3. Application cache.
  Future<void> clearCache() {
    throw UnimplementedError(
      'clearCache is not implemented on the current platform',
    );
  }

  /// Clears the local storage used by the [WebView].
  Future<void> clearLocalStorage() {
    throw UnimplementedError(
      'clearLocalStorage is not implemented on the current platform',
    );
  }

  /// Sets the [PlatformNavigationDelegate] containing the callback methods that
  /// are called during navigation events.
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) {
    throw UnimplementedError(
      'setPlatformNavigationDelegate is not implemented on the current platform',
    );
  }

  /// Runs the given JavaScript in the context of the current page.
  ///
  /// The Future completes with an error if a JavaScript error occurred.
  Future<void> runJavaScript(String javaScript) {
    throw UnimplementedError(
      'runJavaScript is not implemented on the current platform',
    );
  }

  /// Runs the given JavaScript in the context of the current page, and returns the result.
  ///
  /// The Future completes with an error if a JavaScript error occurred, or if the
  /// type the given expression evaluates to is unsupported. Unsupported values include
  /// certain non-primitive types on iOS, as well as `undefined` or `null` on iOS 14+.
  Future<Object> runJavaScriptReturningResult(String javaScript) {
    throw UnimplementedError(
      'runJavaScriptReturningResult is not implemented on the current platform',
    );
  }

  /// Invokes an asynchronous JavaScript function and waits for its result.
  Future<Object?> callAsyncJavaScript(JavaScriptInvocationParams params) {
    throw UnsupportedError(
      'Asynchronous JavaScript invocation is not supported on the current platform.',
    );
  }

  /// Whether this controller can operate without a platform WebView widget.
  Future<bool> isOffscreenWebViewSupported() async {
    return false;
  }

  /// Releases a controller owned by an offscreen session.
  ///
  /// This lifecycle hook is for the app-facing offscreen-session abstraction;
  /// it does not define the lifetime of controllers attached to widgets.
  Future<void> closeOffscreenWebView() {
    throw UnsupportedError(
      'Offscreen WebView lifecycle management is not supported on the current platform.',
    );
  }

  /// Whether deterministic user-script injection is supported.
  Future<bool> isUserScriptInjectionSupported(
    WebViewUserScriptInjectionTime injectionTime,
  ) async {
    return false;
  }

  /// Builds the source installed by a platform user-script implementation.
  ///
  /// Registered scripts execute in a consistent private function scope. Scripts that
  /// need to expose state to later page code must assign it explicitly through
  /// `globalThis`. Set [platformHandlesMainFrameOnly] when the native API can
  /// perform frame filtering without changing the script source.
  @protected
  String buildUserScriptSource(
    WebViewUserScript userScript, {
    required bool platformHandlesMainFrameOnly,
  }) {
    final String scopedSource =
        '''
(function() {
${userScript.source}
}).call(globalThis);
''';
    final String globalThisCompatibility = '''
if (typeof globalThis === 'undefined') {
  window.globalThis = window;
}
''';
    if (userScript.forMainFrameOnly && !platformHandlesMainFrameOnly) {
      return '''
(function() {
$globalThisCompatibility
  if (globalThis.top !== globalThis) {
    return;
  }
$scopedSource
}).call(globalThis);
''';
    }
    return '''
$globalThisCompatibility
$scopedSource''';
  }

  /// Registers [userScript] for injection into future documents.
  ///
  /// Returns an opaque identifier that can be passed to [removeUserScript].
  Future<String> addUserScript(WebViewUserScript userScript) {
    throw UnsupportedError(
      'User-script injection is not supported on the current platform.',
    );
  }

  /// Removes a user script previously registered by [addUserScript].
  Future<void> removeUserScript(String identifier) async {}

  /// Removes all scripts registered through [addUserScript].
  ///
  /// Scripts managed internally by the platform implementation are preserved.
  Future<void> removeAllUserScripts() async {}

  /// Adds a new JavaScript channel to the set of enabled channels.
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) {
    throw UnimplementedError(
      'addJavaScriptChannel is not implemented on the current platform',
    );
  }

  /// Removes the JavaScript channel with the matching name from the set of
  /// enabled channels.
  ///
  /// This disables the channel with the matching name if it was previously
  /// enabled through the [addJavaScriptChannel].
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) {
    throw UnimplementedError(
      'removeJavaScriptChannel is not implemented on the current platform',
    );
  }

  /// Returns the title of the currently loaded page.
  Future<String?> getTitle() {
    throw UnimplementedError(
      'getTitle is not implemented on the current platform',
    );
  }

  /// Set the scrolled position of this view.
  ///
  /// The parameters `x` and `y` specify the position to scroll to in WebView pixels.
  Future<void> scrollTo(int x, int y) {
    throw UnimplementedError(
      'scrollTo is not implemented on the current platform',
    );
  }

  /// Move the scrolled position of this view.
  ///
  /// The parameters `x` and `y` specify the amount of WebView pixels to scroll by.
  Future<void> scrollBy(int x, int y) {
    throw UnimplementedError(
      'scrollBy is not implemented on the current platform',
    );
  }

  /// Whether the vertical scrollbar should be drawn or not.
  Future<void> setVerticalScrollBarEnabled(bool enabled) {
    throw UnimplementedError(
      'setVerticalScrollBarEnabled is not implemented on the current platform',
    );
  }

  /// Whether the horizontal scrollbar should be drawn or not.
  Future<void> setHorizontalScrollBarEnabled(bool enabled) {
    throw UnimplementedError(
      'setHorizontalScrollBarEnabled is not implemented on the current platform',
    );
  }

  /// Returns true if the current platform supports setting whether scrollbars
  /// should be drawn or not.
  ///
  /// See [setVerticalScrollBarEnabled] and [setHorizontalScrollBarEnabled].
  bool supportsSetScrollBarsEnabled() {
    return false;
  }

  /// Return the current scroll position of this view.
  ///
  /// Scroll position is measured from the top left.
  Future<Offset> getScrollPosition() {
    throw UnimplementedError(
      'getScrollPosition is not implemented on the current platform',
    );
  }

  /// Whether to support zooming using its on-screen zoom controls and gestures.
  Future<void> enableZoom(bool enabled) {
    throw UnimplementedError(
      'enableZoom is not implemented on the current platform',
    );
  }

  /// Set the current background color of this view.
  Future<void> setBackgroundColor(Color color) {
    throw UnimplementedError(
      'setBackgroundColor is not implemented on the current platform',
    );
  }

  /// Sets the JavaScript execution mode to be used by the webview.
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) {
    throw UnimplementedError(
      'setJavaScriptMode is not implemented on the current platform',
    );
  }

  /// Sets the value used for the HTTP `User-Agent:` request header.
  Future<void> setUserAgent(String? userAgent) {
    throw UnimplementedError(
      'setUserAgent is not implemented on the current platform',
    );
  }

  /// Sets a callback that notifies the host application that web content is
  /// requesting permission to access the specified resources.
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) {
    throw UnimplementedError(
      'setOnPlatformPermissionRequest is not implemented on the current platform',
    );
  }

  /// Gets the value used for the HTTP `User-Agent:` request header.
  Future<String?> getUserAgent() {
    throw UnimplementedError(
      'getUserAgent is not implemented on the current platform',
    );
  }

  /// Sets a callback that notifies the host application of any console messages
  /// written to the JavaScript console.
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) {
    throw UnimplementedError(
      'setOnConsoleMessage is not implemented on the current platform',
    );
  }

  /// Sets the listener for content offset changes.
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) {
    throw UnimplementedError(
      'setOnScrollPositionChange is not implemented on the current platform',
    );
  }

  /// Sets a callback that notifies the host application that the web page
  /// wants to display a JavaScript alert() dialog.
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    throw UnimplementedError(
      'setOnJavaScriptAlertDialog is not implemented on the current platform',
    );
  }

  /// Sets a callback that notifies the host application that the web page
  /// wants to display a JavaScript confirm() dialog.
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    throw UnimplementedError(
      'setOnJavaScriptConfirmDialog is not implemented on the current platform',
    );
  }

  /// Sets a callback that notifies the host application that the web page
  /// wants to display a JavaScript prompt() dialog.
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    throw UnimplementedError(
      'setOnJavaScriptTextInputDialog is not implemented on the current platform',
    );
  }

  /// Sets the over-scroll mode for the WebView.
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    throw UnimplementedError(
      'setOverScrollMode is not implemented on the current platform',
    );
  }
}

/// Describes the parameters necessary for registering a JavaScript channel.
@immutable
class JavaScriptChannelParams {
  /// Creates a new [JavaScriptChannelParams] object.
  const JavaScriptChannelParams({
    required this.name,
    required this.onMessageReceived,
  });

  /// The name that identifies the JavaScript channel.
  final String name;

  /// The callback method that is invoked when a [JavaScriptMessage] is
  /// received.
  final void Function(JavaScriptMessage) onMessageReceived;
}

class _UnsupportedSessionCookieManager extends PlatformWebViewCookieManager {
  _UnsupportedSessionCookieManager()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
  @override
  Future<bool> clearCookies() async => false;
  @override
  Future<void> setCookie(WebViewCookie cookie) async {}
  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async => const [];
}

class _UnsupportedSessionDataManager extends PlatformWebViewDataManager {
  _UnsupportedSessionDataManager()
    : super.implementation(const PlatformWebViewDataManagerCreationParams());
}

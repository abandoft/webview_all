import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show RRect;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_resource_server.dart';
import 'linux_webview_cookie_manager.dart';
import 'linux_webview_data_manager.dart';
import 'linux_webview_constants.dart';
import 'linux_webview_creation_params.dart';
import 'linux_webview_requests.dart';

part 'linux_webview_events.dart';

String _createLinuxOpaqueIdentifier(String prefix) {
  final Random random = Random.secure();
  final String token = List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    growable: false,
  ).join();
  return '${prefix}_$token';
}

Future<void> _disposeFinalizedLinuxWebView(
  _LinuxWebViewDisposal disposal,
) async {
  try {
    await disposal.dispose();
  } catch (_) {
    // The Flutter engine can already be detached when a finalizer runs.
    return;
  }
}

class LinuxWebViewController extends PlatformWebViewController
    with WebViewResourceControllerMixin, WebViewNetworkControllerMixin {
  WebViewFileSelector? _fileSelector;
  FutureOr<void> Function(WebViewNewWindowRequest<PlatformWebViewController>)?
  _newWindowDelegate;
  VoidCallback? _onWindowCloseRequested;
  bool _nativeFullscreen = false;

  @override
  Future<WebViewNetworkCapabilities> getNetworkCapabilities() async {
    if (_disposed) return const WebViewNetworkCapabilities();
    var body = false;
    try {
      body =
          (await _invoke<Map<Object?, Object?>>(
            'getNetworkCapabilities',
          ))?['customSchemeRequestBodies'] ==
          true;
    } catch (_) {}
    return WebViewNetworkCapabilities(
      contentRules: true,
      ruleActions: {
        WebViewContentRuleAction.block,
        WebViewContentRuleAction.allow,
        WebViewContentRuleAction.hideElements,
        WebViewContentRuleAction.upgradeToHttps,
      },
      ruleConditions: {
        WebViewContentRuleCondition.domain,
        WebViewContentRuleCondition.topUrl,
        WebViewContentRuleCondition.loadType,
      },
      customSchemes: true,
      customSchemeFetch: true,
      customSchemeRequestBodies: body,
      streamingResponses: true,
      resourceTypes: {
        WebViewNetworkResourceType.document,
        WebViewNetworkResourceType.image,
        WebViewNetworkResourceType.styleSheet,
        WebViewNetworkResourceType.script,
        WebViewNetworkResourceType.font,
        WebViewNetworkResourceType.media,
        WebViewNetworkResourceType.raw,
        WebViewNetworkResourceType.svgDocument,
      },
      limitation:
          'WebKitGTK content filters run natively. Its public UI-process API does not provide asynchronous pass-through HTTP request interception.',
    );
  }

  @override
  Future<bool> configureContentRules(List<Map<String, Object?>> rules) async {
    if (_disposed) return false;
    const names = {
      'document': 'document',
      'image': 'image',
      'styleSheet': 'style-sheet',
      'script': 'script',
      'font': 'font',
      'media': 'media',
      'raw': 'raw',
      'svgDocument': 'svg-document',
    };
    final json = jsonEncode(
      rules
          .map(
            (r) => {
              'trigger': {
                'url-filter': r['urlFilter'],
                'url-filter-is-case-sensitive': r['caseSensitive'],
                if ((r['ifDomains'] as List? ?? const []).isNotEmpty)
                  'if-domain': r['ifDomains'],
                if ((r['unlessDomains'] as List? ?? const []).isNotEmpty)
                  'unless-domain': r['unlessDomains'],
                if ((r['ifTopUrls'] as List? ?? const []).isNotEmpty)
                  'if-top-url': r['ifTopUrls'],
                if ((r['unlessTopUrls'] as List? ?? const []).isNotEmpty)
                  'unless-top-url': r['unlessTopUrls'],
                if ((r['loadTypes'] as List? ?? const []).isNotEmpty)
                  'load-type': r['loadTypes'],
                if ((r['resourceTypes']! as List).isNotEmpty)
                  'resource-type': (r['resourceTypes']! as List)
                      .map((v) => names[v])
                      .toList(),
              },
              'action': {
                'type': switch (r['action']) {
                  'block' => 'block',
                  'allow' => 'ignore-previous-rules',
                  'hideElements' => 'css-display-none',
                  'upgradeToHttps' => 'make-https',
                  _ => throw ArgumentError('Unknown native rule action.'),
                },
                if (r['selector'] != null) 'selector': r['selector'],
              },
            },
          )
          .toList(),
    );
    return await _invoke<bool>('setContentRules', {'json': json}) ?? false;
  }

  final Map<String, LinuxResourceServer> _schemeServers = {};
  @override
  Future<bool> configureNetworkBridge(
    Map<String, Object?> configuration,
  ) async {
    if (configuration['kind'] != 'schemes') return false;
    final name = configuration['channel']! as String;
    if (configuration['enabled'] != true) {
      try {
        if (!_disposed) {
          await _invoke<bool>('configureCustomSchemes', configuration);
        }
      } finally {
        await _schemeServers.remove(name)?.close();
      }
      return true;
    }
    if (_disposed) return false;
    final bridge = networkBridgeForChannel(name);
    if (bridge == null) return false;
    final server = await LinuxResourceServer.bind(bridge, bodyTransport: true);
    _schemeServers[name] = server;
    try {
      final accepted =
          await _invoke<bool>('configureCustomSchemes', {
            ...configuration,
            'baseUri': server.baseUri.toString(),
          }) ??
          false;
      if (!accepted) {
        _schemeServers.remove(name);
        await server.close();
      }
      return accepted;
    } catch (_) {
      _schemeServers.remove(name);
      await server.close();
      rethrow;
    }
  }

  @override
  Future<PlatformWebViewController?> createRelatedController() =>
      browserOperation<PlatformWebViewController?>(
        'createRelatedController',
        null,
        () async {
          if (_disposed) return null;
          await _ensureReady();
          final id = await rootChannel.invokeMethod<int>(
            'createRelatedWebView',
            {'parentId': _sessionViewId},
          );
          if (id == null) return null;
          final child = LinuxWebViewController._(params, adoptedViewId: id);
          try {
            await child._ensureReady();
            return child;
          } catch (_) {
            await child.closeWebViewSession();
            rethrow;
          }
        },
      );

  @override
  Future<WebViewNavigationState?> saveNavigationState() =>
      browserOperation<WebViewNavigationState?>(
        'saveNavigationState',
        null,
        () async {
          if (_disposed) return null;
          final id = await _invoke<String>('saveNavigationState');
          return id == null
              ? null
              : WebViewNavigationState(
                  platform: 'linux',
                  identifier: id,
                  onDispose: () => rootChannel.invokeMethod<void>(
                    'releaseNavigationState',
                    {'stateId': id},
                  ),
                );
        },
      );

  @override
  Future<bool> restoreNavigationState(WebViewNavigationState state) =>
      browserOperation('restoreNavigationState', false, () async {
        if (_disposed || !acceptsNavigationState(state, 'linux')) return false;
        prepareJavaScriptForNavigation();
        return await _invoke<bool>('restoreNavigationState', {
              'stateId': state.identifier,
            }) ??
            false;
      });

  Future<void> _handleFullscreenChanged(bool active) {
    _nativeFullscreen = active;
    return active ? notifyFullscreenEntered() : notifyFullscreenExited();
  }

  Future<void> _handleProcessFailure(Map<Object?, Object?> event) {
    _nativeFullscreen = false;
    _cancelPendingAsyncJavaScriptInvocations(
      const JavaScriptExecutionException(
        name: 'ProcessError',
        message: 'The renderer process exited.',
      ),
    );
    return notifyProcessFailed(
      WebViewProcessFailure(
        kind: WebViewProcessFailureKind.rendererExited,
        recovery: WebViewProcessRecovery.reload,
        didCrash: event['didCrash'] as bool?,
        nativeCode: (event['nativeCode'] as num?)?.toInt(),
        description:
            'The WebKit renderer process exited. Reload the page to recover.',
      ),
    );
  }

  @override
  Future<void> setFullscreenDelegate(
    WebViewFullscreenDelegate? delegate,
  ) async {
    if (_disposed) return;
    await updateFullscreenDelegate(delegate);
    await _invoke<void>('setFullscreenDelegateEnabled', {
      'enabled': delegate != null,
    });
  }

  @override
  Future<bool> exitFullscreen() async {
    if (_disposed || !_nativeFullscreen) return false;
    return exitDocumentFullscreen();
  }

  @override
  Future<void> setOnProcessFailed(
    FutureOr<void> Function(WebViewProcessFailure)? callback,
  ) async {
    if (!_disposed) updateProcessFailureCallback(callback);
  }

  @override
  Future<void> setNewWindowDelegate(
    FutureOr<void> Function(WebViewNewWindowRequest<PlatformWebViewController>)?
    delegate,
  ) async {
    final previous = _newWindowDelegate;
    _newWindowDelegate = delegate;
    try {
      await _invoke<void>('setNewWindowDelegateEnabled', {
        'enabled': delegate != null,
      });
    } catch (error) {
      _newWindowDelegate = previous;
      debugPrint(
        'webview_all_linux: new-window delegation is unavailable: $error',
      );
    }
  }

  @override
  Future<void> setOnWindowCloseRequested(VoidCallback? callback) async {
    if (!_disposed) _onWindowCloseRequested = callback;
  }

  Future<void> _handleNewWindowRequest(Map<Object?, Object?> args) async {
    final id = (args['requestId']! as num).toInt();
    LinuxWebViewController? created;
    final request = WebViewNewWindowRequest<PlatformWebViewController>(
      url: Uri.tryParse(args['url'] as String? ?? ''),
      isUserGesture: args['isUserGesture'] as bool?,
      onCreateController: () async {
        final childId = await _invoke<int>('claimNewWindow', {'requestId': id});
        if (childId == null) return null;
        final child = LinuxWebViewController._(params, adoptedViewId: childId);
        await child._readyFuture;
        return created = child;
      },
      onAttach: (child) async {
        final valid =
            identical(child, created) &&
            !_disposed &&
            created != null &&
            !created!._disposed;
        if (!valid) {
          debugPrint(
            'webview_all_linux: use request.createController() to obtain the related native child; independent controllers cannot preserve the opener and POST request.',
          );
        }
        return await _invoke<bool>('attachNewWindow', {
              'requestId': id,
              'childWebViewId': valid ? created!._sessionViewId : null,
            }) ??
            false;
      },
      onReject: () => _invoke<void>('attachNewWindow', {'requestId': id}),
    );
    await dispatchWebViewNewWindowRequest(
      _disposed ? null : _newWindowDelegate,
      request,
    );
  }

  static Future<Object?> Function(MethodCall) _fileSelectorReceiver(
    WeakReference<LinuxWebViewController> owner,
  ) => (call) async {
    if (call.method != 'fileSelectorRequested') throw MissingPluginException();
    final selector = owner.target?._fileSelector;
    if (selector == null || owner.target?._disposed != false) return <String>[];
    final args = call.arguments as Map<Object?, Object?>;
    try {
      return await selector(
        WebViewFileSelectorParams(
          mode: args['multiple'] == true
              ? WebViewFileSelectorMode.openMultiple
              : WebViewFileSelectorMode.open,
          acceptTypes: (args['acceptTypes'] as List<Object?>? ?? [])
              .whereType<String>(),
        ),
      );
    } catch (error) {
      debugPrint('webview_all_linux: the custom file selector failed: $error');
      return <String>[];
    }
  };

  @override
  Future<void> setFileSelector(WebViewFileSelector? selector) async {
    final previous = _fileSelector;
    _fileSelector = selector;
    try {
      await _invoke<void>('setFileSelectorEnabled', {
        'enabled': selector != null,
      });
    } catch (_) {
      _fileSelector = previous;
      rethrow;
    }
  }

  @override
  Future<WebViewBrowserCapabilities> getBrowserCapabilities() async =>
      WebViewBrowserCapabilities(
        newWindowDelegate: true,
        windowCloseRequests: true,
        fullscreenEvents: true,
        processFailureEvents: true,
        navigationState: true,
        stopLoading: true,
        viewportScreenshot: true,
        archiveFormats: const {WebViewArchiveFormat.mhtml},
        contextMenuControl: true,
        audioMuting: true,
        printing: true,
        printJobState: true,
        fullDocumentScreenshot: true,
        screenshotRegion: true,
        screenshotScale: true,
        pdfExport: true,
        pdfPageLayout: true,
        mediaPlaybackPolicyAtCreation: true,
        navigationHistory: true,
        historyNavigation: true,
        findText: true,
        findCaseSensitive: true,
        findWithoutWrapping: true,
        findMatchCount: true,
        fileSelector: true,
        mediaPlaybackRequiresUserGesture: true,
        popupWindowPolicies: {
          WebViewPopupWindowPolicy.platformDefault,
          WebViewPopupWindowPolicy.deny,
          WebViewPopupWindowPolicy.sameView,
        },
      );

  @override
  Future<bool> setAudioMuted(
    bool muted,
  ) => browserOperation('setAudioMuted', false, () async {
    final accepted =
        await _invoke<bool>('setAudioMuted', {'muted': muted}) ?? false;
    if (!accepted) {
      debugPrint(
        'webview_all_linux: setAudioMuted is unavailable in this engine or the native view is closed.',
      );
    }
    return accepted;
  });

  @override
  Future<bool> setContextMenuEnabled(
    bool enabled,
  ) => browserOperation('setContextMenuEnabled', false, () async {
    final accepted =
        await _invoke<bool>('setContextMenuEnabled', {'enabled': enabled}) ??
        false;
    if (!accepted) {
      debugPrint(
        'webview_all_linux: setContextMenuEnabled is unavailable in this engine or the native view is closed.',
      );
    }
    return accepted;
  });

  @override
  Future<Uint8List?> createArchive({required WebViewArchiveFormat format}) {
    if (format != WebViewArchiveFormat.mhtml) {
      return super.createArchive(format: format);
    }
    return capturePageData('Page archive', () async {
      if (_disposed) return null;
      return _invoke<Uint8List>('createArchive', {'format': format.name});
    });
  }

  @override
  Future<WebViewPrintJob?> printPage({String jobName = 'Web page'}) async {
    return startNativePrint(
      jobName,
      (method, args) => method == 'printPage'
          ? _invoke<Object?>(method, args)
          : rootChannel.invokeMethod<Object?>(method, args),
    );
  }

  @override
  Future<Uint8List?> takeScreenshot({
    WebViewScreenshotOptions options = const WebViewScreenshotOptions(),
  }) => captureScreenshot(
    options,
    () => _invoke<Uint8List>('takeScreenshot', {
      'fullDocument': options.fullDocument,
    }),
  );

  @override
  Future<Uint8List?> createPdf({WebViewPdfOptions? options}) =>
      capturePageData('createPdf', () {
        if (options != null && !options.isValid) {
          throw ArgumentError('Invalid PDF paper size or margins.');
        }
        return _invoke<Uint8List>('createPdf', {'options': options?.toMap()});
      });

  @override
  Future<void> stopLoading() => _invoke<void>('stopLoading');

  @override
  Future<WebViewNavigationHistory> getNavigationHistory() async =>
      WebViewNavigationHistory.fromMap(
        (await _invoke<Map<Object?, Object?>>('getNavigationHistory')) ??
            const {},
      );

  @override
  Future<bool> goToHistoryIndex(int index) async =>
      await _invoke<bool>('goToHistoryIndex', {'index': index}) ?? false;

  @override
  Future<WebViewFindResult?> findText(
    String text, {
    bool forward = true,
    bool caseSensitive = false,
    bool wrapAround = true,
  }) async {
    if (text.isEmpty) {
      await clearFindMatches();
      return const WebViewFindResult(matchFound: false, matchCount: 0);
    }
    return serializeTextSearch(() async {
      final result =
          await _invoke<Map<Object?, Object?>>('findText', {
            'text': text,
            'forward': forward,
            'caseSensitive': caseSensitive,
            'wrapAround': wrapAround,
          }).timeout(
            const Duration(seconds: 10),
            onTimeout: () async {
              await _invoke<void>('clearFindMatches');
              debugPrint(
                'webview_all_linux: text search timed out and was cancelled.',
              );
              return null;
            },
          );
      return result == null ? null : WebViewFindResult.fromMap(result);
    });
  }

  @override
  Future<void> clearFindMatches() =>
      serializeTextSearch(() => _invoke<void>('clearFindMatches'));

  @override
  Future<void> setPopupPolicy(WebViewPopupWindowPolicy policy) =>
      _invoke<void>('setPopupWindowPolicy', {'policy': policy.index});

  @override
  String get resourceUrlScheme => 'http';

  @override
  Future<void> configureResourceBridge(
    String channel,
    String host,
    bool enabled,
  ) async {
    if (_disposed) throw StateError('The Linux WebView was disposed.');
    await _readyFuture;
    if (_disposed) throw StateError('The Linux WebView was disposed.');
    if (_resourceServer == null && enabled) {
      final server = await LinuxResourceServer.bind(resourceBridge);
      if (_disposed) {
        await server.close();
        throw StateError('The Linux WebView was disposed.');
      }
      _resourceServer = server;
    }
  }

  LinuxResourceServer? _resourceServer;
  LinuxWebViewController(PlatformWebViewControllerCreationParams params)
    : this._(params);

  LinuxWebViewController._(
    PlatformWebViewControllerCreationParams params, {
    int? adoptedViewId,
  }) : super.implementation(
         params is LinuxWebViewControllerCreationParams
             ? params
             : LinuxWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
                 params,
               ),
       ) {
    _readyFuture = _initialize(
      WeakReference<LinuxWebViewController>(this),
      adoptedViewId: adoptedViewId,
    );
  }

  static final Finalizer<_LinuxWebViewDisposal> _finalizer =
      Finalizer<_LinuxWebViewDisposal>((_LinuxWebViewDisposal disposal) {
        unawaited(_disposeFinalizedLinuxWebView(disposal));
      });

  static const MethodChannel rootChannel = MethodChannel(
    linuxWebViewChannelPrefix,
  );

  /// Initializes the shared WebKitGTK environment or reuses its configuration.
  ///
  /// Configure custom directories before creating a controller or using cookie
  /// and website-data managers. With no options, an existing environment is
  /// reused; otherwise WebKitGTK's default directories are used.
  ///
  /// [userDataPath] stores persistent website data and [cachePath] stores cache
  /// files. Relative paths are resolved against the current working directory.
  /// Explicit options must match the active configuration, including omitted
  /// paths, which select platform defaults. Empty paths also select defaults.
  /// Conflicting options throw a [PlatformException] with code
  /// `environment_configuration_conflict` without replacing the environment.
  /// Existing website data is not moved when custom directories are selected.
  static Future<void> ensureEnvironment({
    String? userDataPath,
    String? cachePath,
  }) => _configureEnvironment(
    'ensureEnvironment',
    userDataPath: userDataPath,
    cachePath: cachePath,
  );

  /// Explicitly initializes the shared WebKitGTK environment.
  ///
  /// Throws `environment_already_initialized` after the environment has been
  /// initialized, even with the same options. Prefer [ensureEnvironment] when
  /// independent components may initialize the shared environment.
  static Future<void> initializeEnvironment({
    String? userDataPath,
    String? cachePath,
  }) => _configureEnvironment(
    'initializeEnvironment',
    userDataPath: userDataPath,
    cachePath: cachePath,
  );

  static Future<void> _configureEnvironment(
    String method, {
    String? userDataPath,
    String? cachePath,
  }) async {
    for (final entry in <String, String?>{
      'userDataPath': userDataPath,
      'cachePath': cachePath,
    }.entries) {
      if (entry.value?.contains('\u0000') ?? false) {
        throw ArgumentError.value(
          entry.value,
          entry.key,
          'Contains a NUL byte',
        );
      }
    }
    await rootChannel.invokeMethod<void>(method, <String, Object?>{
      'userDataPath': userDataPath,
      'cachePath': cachePath,
    });
  }

  static final RegExp _javaScriptIdentifierPattern = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*$',
  );

  Future<void>? _readyFuture;
  MethodChannel? _channel;
  int? _sessionViewId;
  EventChannel? _eventChannel;
  StreamSubscription<dynamic>? _eventSubscription;
  _LinuxWebViewDisposal? _nativeDisposal;

  LinuxNavigationDelegate? _navigationDelegate;
  WebViewDownloadDelegate? _downloadDelegate;
  final Map<String, WebViewDownloadDelegate> _downloadDelegates =
      <String, WebViewDownloadDelegate>{};
  final Set<String> _finishedDownloads = <String>{};
  final Map<String, Completer<void>> _downloadDecisions =
      <String, Completer<void>>{};
  int _downloadDelegateGeneration = 0;
  final Map<String, JavaScriptChannelParams> _javaScriptChannels =
      <String, JavaScriptChannelParams>{};
  final Map<String, Completer<Object?>> _pendingAsyncJavaScriptInvocations =
      <String, Completer<Object?>>{};
  final Set<String> _userScriptIdentifiers = <String>{};

  String? _currentUrl;
  String? _title;
  String? _userAgent;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _disposed = false;
  int _frameSequence = 0;
  Future<void>? _disposeFuture;
  int _nextAsyncJavaScriptInvocationIdentifier = 0;
  int _nextUserScriptIdentifier = 0;

  void Function(JavaScriptConsoleMessage consoleMessage)? _onConsoleMessage;
  void Function(ScrollPositionChange scrollPositionChange)?
  _onScrollPositionChange;
  void Function(PlatformWebViewPermissionRequest request)? _onPermissionRequest;
  Future<void> Function(JavaScriptAlertDialogRequest request)?
  _onJavaScriptAlertDialog;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)?
  _onJavaScriptConfirmDialog;
  Future<String> Function(JavaScriptTextInputDialogRequest request)?
  _onJavaScriptTextInputDialog;

  Future<void> _initialize(
    WeakReference<LinuxWebViewController> weakThis, {
    int? adoptedViewId,
  }) async {
    final int id =
        adoptedViewId ??
        await rootChannel.invokeMethod<int>(
          'createWebView',
          _linuxParams.incognito || params.profileName != null
              ? {
                  if (_linuxParams.incognito) 'incognito': true,
                  if (params.profileName != null)
                    'profileName': params.profileName,
                }
              : null,
        ) ??
        (throw StateError('Failed to create Linux WebView instance.'));
    _sessionViewId = id;
    _channel = MethodChannel('$linuxWebViewChannelPrefix/$id');
    _channel!.setMethodCallHandler(_fileSelectorReceiver(weakThis));
    _eventChannel = EventChannel('$linuxWebViewChannelPrefix/$id/events');
    _eventSubscription = _eventChannel!.receiveBroadcastStream().listen(
      (dynamic event) {
        final LinuxWebViewController? target = weakThis.target;
        if (target == null) {
          return;
        }
        try {
          target._handleEvent(event);
        } catch (error, stackTrace) {
          target._reportEventError('event callback', error, stackTrace);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        weakThis.target?._reportEventError('event channel', error, stackTrace);
      },
      onDone: () {
        final LinuxWebViewController? target = weakThis.target;
        if (target != null && !target._disposed) {
          target._reportEventError(
            'event channel',
            StateError('The native Linux WebView event channel closed.'),
            StackTrace.current,
          );
        }
      },
    );
    final _LinuxWebViewDisposal disposal = _LinuxWebViewDisposal(
      channel: _channel!,
      eventSubscription: _eventSubscription!,
    );
    _nativeDisposal = disposal;
    _finalizer.attach(this, disposal, detach: this);
    try {
      await _applyCreationParams();
    } catch (_) {
      _finalizer.detach(this);
      await disposal.dispose();
      rethrow;
    }
  }

  LinuxWebViewControllerCreationParams get _linuxParams =>
      params as LinuxWebViewControllerCreationParams;

  @override
  Future<void> prepareSession() => _ensureReady();

  int get _sessionIdentifier {
    if (_disposed || _sessionViewId == null) {
      throw StateError('The WebView session is not ready or has closed.');
    }
    return _sessionViewId!;
  }

  @override
  PlatformWebViewCookieManager createSessionCookieManager() =>
      LinuxWebViewCookieManager(
        LinuxWebViewCookieManagerCreationParams(webViewId: _sessionIdentifier),
      );

  @override
  PlatformWebViewDataManager createSessionDataManager() =>
      LinuxWebViewDataManager(
        LinuxWebViewDataManagerCreationParams(webViewId: _sessionIdentifier),
      );

  @override
  Future<void> setDownloadDelegate(WebViewDownloadDelegate? delegate) async {
    await _ensureReady();
    final previous = _downloadDelegate;
    final generation = ++_downloadDelegateGeneration;
    for (final pending in _downloadDecisions.values) {
      if (!pending.isCompleted) pending.complete();
    }
    _downloadDecisions.clear();
    _downloadDelegate = delegate;
    try {
      await _channel!.invokeMethod<void>(
        'setDownloadDelegate',
        <String, Object?>{'enabled': delegate != null},
      );
      await _ensureReady();
    } catch (_) {
      if (!_disposed && generation == _downloadDelegateGeneration) {
        _downloadDelegate = previous;
      }
      rethrow;
    }
  }

  Future<void> _applyCreationParams() async {
    final Map<String, Object?> settings = <String, Object?>{
      if (_linuxParams.developerExtrasEnabled case final bool value)
        'developerExtrasEnabled': value,
      if (_linuxParams.downloadsEnabled case final bool value)
        'downloadsEnabled': value,
      if (_linuxParams.javascriptCanOpenWindowsAutomatically
          case final bool value)
        'javascriptCanOpenWindowsAutomatically': value,
      if ((_linuxParams.mediaPlaybackRequiresUserGesture ??
              (_linuxParams.mediaPlaybackPolicy == null
                  ? null
                  : _linuxParams.mediaPlaybackPolicy ==
                        WebViewMediaPlaybackPolicy.requireUserGesture))
          case final bool value)
        'mediaPlaybackRequiresUserGesture': value,
      if (_linuxParams.mediaPlaybackAllowsInline case final bool value)
        'mediaPlaybackAllowsInline': value,
      if (_linuxParams.pageCacheEnabled case final bool value)
        'pageCacheEnabled': value,
      if (_linuxParams.allowFileAccessFromFileUrls case final bool value)
        'allowFileAccessFromFileUrls': value,
      if (_linuxParams.allowUniversalAccessFromFileUrls case final bool value)
        'allowUniversalAccessFromFileUrls': value,
      if (_linuxParams.zoomTextOnly case final bool value)
        'zoomTextOnly': value,
      if (_linuxParams.defaultFontSize case final int value)
        'defaultFontSize': value,
      if (_linuxParams.defaultMonospaceFontSize case final int value)
        'defaultMonospaceFontSize': value,
      if (_linuxParams.minimumFontSize case final int value)
        'minimumFontSize': value,
      if (_linuxParams.zoomFactor case final double value) 'zoomFactor': value,
    };

    if (settings.isEmpty) {
      return;
    }

    await _channel!.invokeMethod<void>('applySettings', settings);
  }

  Future<void> _ensureReady() async {
    await _readyFuture;
    if (_disposed) {
      throw StateError(
        'This LinuxWebViewController has already been disposed.',
      );
    }
  }

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    await _ensureReady();
    return _channel!.invokeMethod<T>(method, arguments);
  }

  void _dispatchEventHandler(
    String operation,
    Future<void> Function() handler,
  ) {
    unawaited(
      handler().catchError((Object error, StackTrace stackTrace) {
        _reportEventError(operation, error, stackTrace);
      }),
    );
  }

  void _reportEventError(
    String operation,
    Object error,
    StackTrace stackTrace,
  ) {
    final String diagnostic = error.toString().replaceAll(
      RegExp(r'[\r\n]+'),
      ' ',
    );
    debugPrint('webview_all_linux: $operation failed: $diagnostic');
  }

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    if (!path.isAbsolute(absoluteFilePath)) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'Path must be absolute.',
      );
    }
    final File file = File(absoluteFilePath);
    if (!file.existsSync()) {
      throw ArgumentError.value(
        absoluteFilePath,
        'absoluteFilePath',
        'File does not exist.',
      );
    }
    final String canonicalPath = file.resolveSymbolicLinksSync();

    await _invoke<void>('loadFile', <String, Object?>{'path': canonicalPath});
  }

  @override
  Future<void> loadFileWithParams(LoadFileParams params) {
    return loadFile(params.absoluteFilePath);
  }

  @override
  Future<void> loadFlutterAsset(String key) async {
    final String assetPath = _resolveFlutterAssetPath(key);
    final File file = File(assetPath);
    if (!file.existsSync()) {
      throw ArgumentError.value(key, 'key', 'Asset for key "$key" not found.');
    }

    final String assetRoot = Directory(
      _flutterAssetsRootPath,
    ).resolveSymbolicLinksSync();
    final String canonicalAssetPath = file.resolveSymbolicLinksSync();
    if (!path.isWithin(assetRoot, canonicalAssetPath)) {
      throw ArgumentError.value(
        key,
        'key',
        'Asset resolves outside the Flutter asset directory.',
      );
    }

    await loadFile(canonicalAssetPath);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) {
    return _invoke<void>('loadHtmlString', <String, Object?>{
      'html': html,
      'baseUrl': baseUrl,
    });
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    if (!params.uri.hasScheme) {
      throw ArgumentError(
        'LoadRequestParams#uri is required to have a scheme.',
      );
    }

    await _invoke<void>('loadRequest', <String, Object?>{
      'url': params.uri.toString(),
      'method': params.method.serialize(),
      'headers': params.headers,
      'body': params.body,
    });
  }

  @override
  Future<String?> currentUrl() async {
    await _ensureReady();
    return _currentUrl ?? await _channel!.invokeMethod<String>('currentUrl');
  }

  @override
  Future<bool> canGoBack() async {
    await _ensureReady();
    return (await _channel!.invokeMethod<bool>('canGoBack')) ?? _canGoBack;
  }

  @override
  Future<bool> canGoForward() async {
    await _ensureReady();
    return (await _channel!.invokeMethod<bool>('canGoForward')) ??
        _canGoForward;
  }

  @override
  Future<void> goBack() => _invoke<void>('goBack');

  @override
  Future<void> goForward() => _invoke<void>('goForward');

  @override
  Future<void> reload() => _invoke<void>('reload');

  @override
  Future<void> clearCache() => _invoke<void>('clearCache');

  @override
  Future<void> clearLocalStorage() => _invoke<void>('clearLocalStorage');

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _navigationDelegate = handler as LinuxNavigationDelegate;
  }

  @override
  Future<void> runJavaScript(String javaScript) {
    return _invoke<void>('runJavaScript', <String, Object?>{
      'script': javaScript,
    });
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final Object? result = await _invoke<Object>(
      'runJavaScriptReturningResult',
      <String, Object?>{'script': javaScript},
    );

    if (result == null) {
      throw ArgumentError(
        'The JavaScript returned `null` or `undefined`, which is unsupported.',
      );
    }

    if (result case final Map<Object?, Object?> map
        when map['__json__'] is String) {
      final Object? decoded = jsonDecode(map['__json__']! as String);
      if (decoded == null) {
        throw ArgumentError(
          'The JavaScript returned `null` or `undefined`, which is unsupported.',
        );
      }
      return decoded;
    }

    return result;
  }

  @override
  Future<Object?> callAsyncJavaScript(JavaScriptInvocationParams params) async {
    if (!params.world.isPage) return invokeAsyncJavaScriptInWorld(params);
    await _ensureReady();
    final String identifier = _createLinuxOpaqueIdentifier(
      'async_${++_nextAsyncJavaScriptInvocationIdentifier}',
    );
    final Completer<Object?> completer = Completer<Object?>();
    _pendingAsyncJavaScriptInvocations[identifier] = completer;

    final Future<Object?> completion = completer.future.timeout(
      params.timeout,
      onTimeout: () {
        _pendingAsyncJavaScriptInvocations.remove(identifier);
        throw TimeoutException(
          'The asynchronous JavaScript invocation timed out.',
          params.timeout,
        );
      },
    );
    try {
      final List<Object?> values = await Future.wait<Object?>(<Future<Object?>>[
        _channel!.invokeMethod<void>('runJavaScript', <String, Object?>{
          'script': _buildAsyncJavaScriptInvocation(identifier, params),
        }),
        completion,
      ], eagerError: true);
      return values[1];
    } catch (error, stackTrace) {
      _pendingAsyncJavaScriptInvocations.remove(identifier);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
      rethrow;
    }
  }

  @override
  Future<bool> isOffscreenWebViewSupported() async => true;

  @override
  Future<void> closeOffscreenWebView() => dispose();

  @override
  Future<WebViewJavaScriptCapabilities> getJavaScriptCapabilities({
    WebViewJavaScriptWorld world = WebViewJavaScriptWorld.page,
  }) async => WebViewJavaScriptCapabilities(
    supportsPromiseHandlers: true,
    supportsIsolatedWorlds: true,
    userScriptInjectionTimes: const {
      WebViewUserScriptInjectionTime.documentStart,
      WebViewUserScriptInjectionTime.documentEnd,
    },
    supportsTrustedOrigins: world.isPage,
    supportsTrustedFrameInformation: world.isPage,
    limitation:
        'Handlers run in the main document. Isolated-world messages cannot provide verified origin/frame metadata.',
  );

  @override
  Future<Object?> evaluateJavaScriptInWorld(
    String source,
    WebViewJavaScriptWorld world,
  ) async {
    final result = await _invoke<Object?>('runJavaScriptReturningResult', {
      'script': source,
      'worldName': world.isPage ? null : 'webview_all.user.${world.name}',
    });
    if (result is Map && result['__json__'] is String) {
      return jsonDecode(result['__json__'] as String);
    }
    return result;
  }

  @override
  Future<void> addJavaScriptChannelInWorld(
    JavaScriptChannelParams params,
    WebViewJavaScriptWorld world,
  ) async {
    if (world.isPage) return addJavaScriptChannel(params);
    return _addJavaScriptChannel(
      params,
      worldName: 'webview_all.user.${world.name}',
    );
  }

  @override
  Future<bool> isUserScriptInjectionSupported(
    WebViewUserScriptInjectionTime injectionTime,
  ) async {
    await _ensureReady();
    return true;
  }

  @override
  Future<String> addUserScript(WebViewUserScript userScript) async {
    final String identifier = 'webview_all_${++_nextUserScriptIdentifier}';
    await _invoke<void>('addUserScript', <String, Object?>{
      'identifier': identifier,
      'source': buildUserScriptSource(
        userScript,
        platformHandlesMainFrameOnly: true,
      ),
      'mainFrameOnly': userScript.forMainFrameOnly,
      'worldName': userScript.world.isPage
          ? null
          : 'webview_all.user.${userScript.world.name}',
      'documentEnd':
          userScript.injectionTime ==
          WebViewUserScriptInjectionTime.documentEnd,
    });
    _userScriptIdentifiers.add(identifier);
    return identifier;
  }

  @override
  Future<void> removeUserScript(String identifier) async {
    if (!_userScriptIdentifiers.contains(identifier)) {
      return;
    }
    await _invoke<void>('removeUserScript', <String, Object?>{
      'identifier': identifier,
    });
    _userScriptIdentifiers.remove(identifier);
  }

  @override
  Future<void> removeAllUserScripts() async {
    for (final identifier in _userScriptIdentifiers.toList()) {
      if (!isJavaScriptBridgeScript(identifier)) {
        await removeUserScript(identifier);
      }
    }
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) => _addJavaScriptChannel(javaScriptChannelParams);

  Future<void> _addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams, {
    String? worldName,
  }) async {
    final String name = javaScriptChannelParams.name;
    if (!_javaScriptIdentifierPattern.hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'javaScriptChannelParams.name',
        'JavaScript channel names must be valid JavaScript identifiers.',
      );
    }

    if (_javaScriptChannels.containsKey(name)) {
      throw ArgumentError(
        'A JavaScriptChannel with name `$name` already exists.',
      );
    }

    _javaScriptChannels[name] = javaScriptChannelParams;
    try {
      await _invoke<void>('addJavaScriptChannel', <String, Object?>{
        'name': name,
        if (worldName != null) 'worldName': worldName,
      });
    } catch (_) {
      _javaScriptChannels.remove(name);
      rethrow;
    }
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    _javaScriptChannels.remove(javaScriptChannelName);
    await _invoke<void>('removeJavaScriptChannel', <String, Object?>{
      'name': javaScriptChannelName,
    });
  }

  @override
  Future<String?> getTitle() async {
    await _ensureReady();
    return _title ?? await _channel!.invokeMethod<String>('getTitle');
  }

  @override
  Future<void> scrollTo(int x, int y) {
    return _invoke<void>('scrollTo', <String, Object?>{'x': x, 'y': y});
  }

  @override
  Future<void> scrollBy(int x, int y) {
    return _invoke<void>('scrollBy', <String, Object?>{'x': x, 'y': y});
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) {
    return _invoke<void>('setVerticalScrollBarEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) {
    return _invoke<void>('setHorizontalScrollBarEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  @override
  bool supportsSetScrollBarsEnabled() => true;

  @override
  Future<Offset> getScrollPosition() async {
    final Map<Object?, Object?>? offset = await _invoke<Map<Object?, Object?>>(
      'getScrollPosition',
    );
    return Offset(
      (offset?['x'] as num?)?.toDouble() ?? 0,
      (offset?['y'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Future<void> enableZoom(bool enabled) {
    return _invoke<void>('enableZoom', <String, Object?>{'enabled': enabled});
  }

  @override
  Future<void> setBackgroundColor(Color color) {
    return _invoke<void>('setBackgroundColor', <String, Object?>{
      'r': color.r,
      'g': color.g,
      'b': color.b,
      'a': color.a,
    });
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) {
    return _invoke<void>('setJavaScriptMode', <String, Object?>{
      'enabled': javaScriptMode == JavaScriptMode.unrestricted,
    });
  }

  @override
  Future<void> setUserAgent(String? userAgent) async {
    _userAgent = userAgent;
    await _invoke<void>('setUserAgent', <String, Object?>{
      'userAgent': userAgent,
    });
  }

  @override
  Future<String?> getUserAgent() async {
    await _ensureReady();
    return _userAgent ?? await _channel!.invokeMethod<String>('getUserAgent');
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    _onPermissionRequest = onPermissionRequest;
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    _onConsoleMessage = onConsoleMessage;
    await _invoke<void>('setOnConsoleMessage', <String, Object?>{
      'enabled': true,
    });
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) async {
    _onScrollPositionChange = onScrollPositionChange;
    await _invoke<void>('setOnScrollPositionChange', <String, Object?>{
      'enabled': onScrollPositionChange != null,
    });
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    _onJavaScriptAlertDialog = onJavaScriptAlertDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    _onJavaScriptConfirmDialog = onJavaScriptConfirmDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    _onJavaScriptTextInputDialog = onJavaScriptTextInputDialog;
    await _updateJavaScriptDialogCallbacksEnabled();
  }

  Future<void> _updateJavaScriptDialogCallbacksEnabled() {
    return _invoke<void>(
      'setJavaScriptDialogCallbacksEnabled',
      <String, Object?>{
        'alert': _onJavaScriptAlertDialog != null,
        'confirm': _onJavaScriptConfirmDialog != null,
        'prompt': _onJavaScriptTextInputDialog != null,
      },
    );
  }

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) async {
    await _invoke<void>('setOverScrollMode', <String, Object?>{
      'mode': switch (mode) {
        WebViewOverScrollMode.always => 'always',
        WebViewOverScrollMode.ifContentScrolls => 'ifContentScrolls',
        WebViewOverScrollMode.never => 'never',
      },
    });
  }

  Future<void> setFrame(
    Rect rect, {
    Rect? clipRect,
    List<RRect> roundedClips = const <RRect>[],
    required bool visible,
  }) {
    final Rect effectiveClip = clipRect ?? rect;
    final int sequence = ++_frameSequence;
    return _invoke<void>('setFrame', <String, Object?>{
      'x': rect.left,
      'y': rect.top,
      'width': rect.width,
      'height': rect.height,
      'clipX': effectiveClip.left,
      'clipY': effectiveClip.top,
      'clipWidth': effectiveClip.width,
      'clipHeight': effectiveClip.height,
      'roundedClips': <List<double>>[
        for (final clip in roundedClips.map((clip) => clip.scaleRadii()))
          <double>[
            clip.left,
            clip.top,
            clip.right,
            clip.bottom,
            clip.tlRadiusX,
            clip.tlRadiusY,
            clip.trRadiusX,
            clip.trRadiusY,
            clip.brRadiusX,
            clip.brRadiusY,
            clip.blRadiusX,
            clip.blRadiusY,
          ],
      ],
      'visible': visible,
      'sequence': sequence,
    });
  }

  /// Enables WebKitGTK developer extras for this WebView.
  Future<void> setDeveloperExtrasEnabled(bool enabled) {
    return _invoke<void>('setDeveloperExtrasEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  /// Opens the WebKitGTK web inspector for this WebView.
  Future<void> openDevTools() => _invoke<void>('openDevTools');

  /// Sets whether this WebView can start downloads. Enabled by default.
  ///
  /// When disabled, new downloads are cancelled before saving a file. Downloads
  /// already in progress are not cancelled. Other WebViews are not affected.
  Future<void> setDownloadsEnabled(bool enabled) {
    return _invoke<void>('setDownloadsEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  /// Sets whether JavaScript may open windows automatically.
  Future<void> setJavaScriptCanOpenWindowsAutomatically(bool enabled) {
    return _invoke<void>(
      'setJavaScriptCanOpenWindowsAutomatically',
      <String, Object?>{'enabled': enabled},
    );
  }

  /// Sets whether media playback requires a user gesture.
  @override
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) {
    return _invoke<void>(
      'setMediaPlaybackRequiresUserGesture',
      <String, Object?>{'require': require},
    );
  }

  /// Sets whether inline media playback is allowed.
  Future<void> setMediaPlaybackAllowsInline(bool allow) {
    return _invoke<void>('setMediaPlaybackAllowsInline', <String, Object?>{
      'allow': allow,
    });
  }

  /// Enables or disables WebKitGTK's page cache.
  Future<void> setPageCacheEnabled(bool enabled) {
    return _invoke<void>('setPageCacheEnabled', <String, Object?>{
      'enabled': enabled,
    });
  }

  /// Sets whether file URLs can read other file URLs.
  Future<void> setAllowFileAccessFromFileUrls(bool allow) {
    return _invoke<void>('setAllowFileAccessFromFileUrls', <String, Object?>{
      'allow': allow,
    });
  }

  /// Sets whether file URLs can access all origins.
  Future<void> setAllowUniversalAccessFromFileUrls(bool allow) {
    return _invoke<void>(
      'setAllowUniversalAccessFromFileUrls',
      <String, Object?>{'allow': allow},
    );
  }

  /// Sets whether zooming affects only text.
  Future<void> setZoomTextOnly(bool enabled) {
    return _invoke<void>('setZoomTextOnly', <String, Object?>{
      'enabled': enabled,
    });
  }

  /// Sets the default proportional font size in CSS pixels.
  Future<void> setDefaultFontSize(int fontSize) {
    return _invoke<void>('setDefaultFontSize', <String, Object?>{
      'fontSize': fontSize,
    });
  }

  /// Sets the default monospace font size in CSS pixels.
  Future<void> setDefaultMonospaceFontSize(int fontSize) {
    return _invoke<void>('setDefaultMonospaceFontSize', <String, Object?>{
      'fontSize': fontSize,
    });
  }

  /// Sets the minimum font size in CSS pixels.
  Future<void> setMinimumFontSize(int fontSize) {
    return _invoke<void>('setMinimumFontSize', <String, Object?>{
      'fontSize': fontSize,
    });
  }

  /// Sets the page zoom factor.
  Future<void> setZoomFactor(double zoomFactor) {
    return _invoke<void>('setZoomFactor', <String, Object?>{
      'zoomFactor': zoomFactor,
    });
  }

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    if (_nativeFullscreen) await exitFullscreen();
    disposeBrowserLifecycleCallbacks();
    _newWindowDelegate = null;
    _onWindowCloseRequested = null;
    _channel?.setMethodCallHandler(null);
    disposeJavaScriptHandlers();
    _disposed = true;
    final resourceServer = _resourceServer;
    _resourceServer = null;
    if (resourceServer != null) await resourceServer.close();
    final networkDisposal = disposeNetworkBridges();
    if (networkDisposal != null) await networkDisposal;
    final resourceDisposal = disposeResourceBridge();
    if (resourceDisposal != null) await resourceDisposal;
    _downloadDelegateGeneration++;
    for (final pending in _downloadDecisions.values) {
      if (!pending.isCompleted) pending.complete();
    }
    _downloadDecisions.clear();
    final downloads = Map<String, WebViewDownloadDelegate>.of(
      _downloadDelegates,
    );
    _downloadDelegates.clear();
    _finishedDownloads.clear();
    _downloadDelegate = null;
    for (final entry in downloads.entries) {
      entry.value.notifyResult(
        WebViewDownloadResult(
          id: entry.key,
          status: WebViewDownloadStatus.cancelled,
          description: 'The WebView controller was disposed.',
        ),
      );
    }
    _cancelPendingAsyncJavaScriptInvocations(
      const JavaScriptExecutionException(
        name: 'AbortError',
        message:
            'The WebView controller was disposed before JavaScript completed.',
      ),
    );
    _finalizer.detach(this);
    Object? initializationError;
    StackTrace? initializationStackTrace;
    try {
      await _readyFuture;
    } catch (error, stackTrace) {
      initializationError = error;
      initializationStackTrace = stackTrace;
    }
    await _nativeDisposal?.dispose();
    _eventSubscription = null;
    _javaScriptChannels.clear();
    _userScriptIdentifiers.clear();
    _navigationDelegate = null;
    _onConsoleMessage = null;
    _onScrollPositionChange = null;
    _onPermissionRequest = null;
    _onJavaScriptAlertDialog = null;
    _onJavaScriptConfirmDialog = null;
    _onJavaScriptTextInputDialog = null;
    if (initializationError != null) {
      Error.throwWithStackTrace(
        initializationError,
        initializationStackTrace ?? StackTrace.current,
      );
    }
  }

  void _cancelPendingAsyncJavaScriptInvocations(Object error) {
    cancelJavaScriptHandlerCalls();
    final List<Completer<Object?>> pending = _pendingAsyncJavaScriptInvocations
        .values
        .toList(growable: false);
    _pendingAsyncJavaScriptInvocations.clear();
    for (final Completer<Object?> completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  void _handleAsyncJavaScriptMessage(String message) {
    Object? decoded;
    try {
      decoded = jsonDecode(message);
    } on FormatException {
      return;
    }
    if (decoded is! Map<String, dynamic>) {
      return;
    }
    final Object? rawIdentifier = decoded['identifier'];
    if (rawIdentifier is! String) {
      return;
    }
    final String identifier = rawIdentifier;
    final Completer<Object?>? completer = _pendingAsyncJavaScriptInvocations
        .remove(identifier);
    if (completer == null || completer.isCompleted) {
      return;
    }
    if (decoded['success'] == true) {
      completer.complete(decoded['value']);
      return;
    }
    completer.completeError(
      JavaScriptExecutionException(
        name: decoded['name']?.toString(),
        message:
            decoded['message']?.toString() ?? 'JavaScript execution failed.',
        javaScriptStackTrace: decoded['stack']?.toString(),
      ),
    );
  }

  String _buildAsyncJavaScriptInvocation(
    String identifier,
    JavaScriptInvocationParams params,
  ) {
    final String argumentNames = params.arguments.keys.join(',');
    final String argumentValues = params.arguments.keys
        .map((String name) => '__arguments[${jsonEncode(name)}]')
        .join(',');
    return '''
(()=>{
  const __identifier=${jsonEncode(identifier)};
  const __arguments=JSON.parse(${jsonEncode(jsonEncode(params.arguments))});
  const __post=(payload)=>window.webkit.messageHandlers.__webview_all_async_javascript.postMessage(JSON.stringify(payload));
  const __postError=(error)=>__post({
    identifier:__identifier,
    success:false,
    name:error&&error.name?String(error.name):null,
    message:error&&error.message?String(error.message):String(error),
    stack:error&&error.stack?String(error.stack):null
  });
  Promise.resolve()
    .then(()=>(async function($argumentNames){
${params.functionBody}
    })($argumentValues))
    .then((value)=>{
      try {
        const encoded=JSON.stringify(value);
        __post({identifier:__identifier,success:true,value:encoded===undefined?null:JSON.parse(encoded)});
      } catch(error) {
        __postError(error);
      }
    },__postError);
})();
''';
  }

  String get _flutterAssetsRootPath {
    return path.joinAll(<String>[
      path.dirname(Platform.resolvedExecutable),
      'data',
      'flutter_assets',
    ]);
  }

  String _resolveFlutterAssetPath(String key) {
    final List<String> segments = key.split('/');
    if (key.isEmpty ||
        key.startsWith('/') ||
        key.contains(r'\') ||
        segments.any(
          (String segment) =>
              segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw ArgumentError.value(
        key,
        'key',
        'Asset key must be a normalized relative path.',
      );
    }
    return path.joinAll(<String>[_flutterAssetsRootPath, ...segments]);
  }
}

class _LinuxWebViewDisposal {
  _LinuxWebViewDisposal({
    required this.channel,
    required this.eventSubscription,
  });

  final MethodChannel channel;
  final StreamSubscription<dynamic> eventSubscription;
  Future<void>? _disposeFuture;

  Future<void> dispose() {
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    channel.setMethodCallHandler(null);
    Object? disposalError;
    StackTrace? disposalStackTrace;
    try {
      await eventSubscription.cancel();
    } catch (error, stackTrace) {
      disposalError = error;
      disposalStackTrace = stackTrace;
    }
    try {
      await channel.invokeMethod<void>('dispose');
    } catch (error, stackTrace) {
      disposalError ??= error;
      disposalStackTrace ??= stackTrace;
    }
    if (disposalError != null) {
      Error.throwWithStackTrace(
        disposalError,
        disposalStackTrace ?? StackTrace.current,
      );
    }
  }
}

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'common/platform_webview.dart';
import 'common/weak_reference_utils.dart';
import 'common/web_kit.g.dart';
import 'common/webkit_constants.dart';
import 'webkit_webview_cookie_manager.dart';
import 'webkit_webview_data_manager.dart';
import 'common/webkit_download_delegate.dart';
import 'webkit_ssl_auth_error.dart';

const String _webKitWebViewPlatformViewType =
    'com.abandoft.webview_all_wkwebview/webview';

final Expando<Set<VoidCallback>> _webKitNavigationStartCallbacks =
    Expando<Set<VoidCallback>>();

/// Controls how Flutter blocks the native iOS view's gesture recognizers.
///
/// See [WebKitWebViewWidgetCreationParams.uiKitGestureBlockingPolicy].
enum WebKitGestureBlockingPolicy {
  /// Uses the plugin's default gesture handling.
  fallbackToPluginDefault,

  /// Blocks native recognizers as soon as Flutter wins the gesture.
  eager,

  /// Delays blocking until the native recognizers receive the full touch sequence.
  waitUntilTouchesEnded,

  /// Uses hit testing instead of asynchronous gesture-arena blocking.
  ///
  /// Requires Flutter 3.47 or later. This can work around unresponsive touches,
  /// but may also let the WebView recognize a gesture claimed by Flutter.
  doNotBlockGesture,
}

// A new public SDK property provides a capability check without referring to
// its enum type, which does not exist in Flutter 3.35.
bool _detectUiKitGestureBlockingPolicySupport() {
  final dynamic view = const UiKitView(
    viewType: _webKitWebViewPlatformViewType,
  );
  try {
    return view.gestureBlockingPolicy is Enum;
  } on NoSuchMethodError {
    return false;
  }
}

final bool _supportsUiKitGestureBlockingPolicy =
    _detectUiKitGestureBlockingPolicySupport();

String _createWebKitOpaqueIdentifier(String prefix) {
  final Random random = Random.secure();
  final String token = List<String>.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    growable: false,
  ).join();
  return '${prefix}_$token';
}

/// Media types that can require a user gesture to begin playing.
///
/// See [WebKitWebViewControllerCreationParams.mediaTypesRequiringUserAction].
enum PlaybackMediaTypes {
  /// A media type that contains audio.
  audio,

  /// A media type that contains video.
  video;

  AudiovisualMediaType _toWKAudiovisualMediaType() {
    switch (this) {
      case PlaybackMediaTypes.audio:
        return AudiovisualMediaType.audio;
      case PlaybackMediaTypes.video:
        return AudiovisualMediaType.video;
    }
  }
}

/// Object specifying parameters for loading a local file in a
/// [WebKitWebViewController].
@immutable
base class WebKitLoadFileParams extends LoadFileParams {
  /// Constructs a [WebKitLoadFileParams], the subclass of a [LoadFileParams].
  WebKitLoadFileParams({
    required super.absoluteFilePath,
    String? readAccessPath,
  }) : readAccessPath = readAccessPath ?? path.dirname(absoluteFilePath),
       super();

  /// Constructs a [WebKitLoadFileParams] using a [LoadFileParams].
  factory WebKitLoadFileParams.fromLoadFileParams(
    LoadFileParams params, {
    String? readAccessPath,
  }) {
    return WebKitLoadFileParams(
      absoluteFilePath: params.absoluteFilePath,
      readAccessPath: readAccessPath,
    );
  }

  /// The directory to which the WebView is granted read access.
  ///
  /// If not provided at initialization time, it defaults to
  /// the parent directory of [absoluteFilePath].
  ///
  /// On iOS/macOS, this is required by WebKit to define the scope of readable
  /// files when loading a local HTML file. It must include the location of
  /// any resources (e.g., images, scripts) referenced by the HTML.
  final String readAccessPath;
}

class _WebKitPrivateStoreOwners {
  int owners = 0;
}

/// Object specifying creation parameters for a [WebKitWebViewController].
@immutable
class WebKitWebViewControllerCreationParams
    extends PlatformWebViewControllerCreationParams {
  /// Constructs a [WebKitWebViewControllerCreationParams].
  WebKitWebViewControllerCreationParams({
    super.sessionMode,
    super.mediaPlaybackPolicy,
    super.profileName,
    super.customSchemes,
    Set<PlaybackMediaTypes>? mediaTypesRequiringUserAction,
    this.allowsInlineMediaPlayback = false,
    this.limitsNavigationsToAppBoundDomains = false,
    this.javaScriptCanOpenWindowsAutomatically,
  }) : mediaTypesRequiringUserAction = Set.unmodifiable(
         mediaTypesRequiringUserAction ??
             (mediaPlaybackPolicy ==
                     WebViewMediaPlaybackPolicy.allowWithoutUserGesture
                 ? const <PlaybackMediaTypes>{}
                 : const <PlaybackMediaTypes>{
                     PlaybackMediaTypes.audio,
                     PlaybackMediaTypes.video,
                   }),
       ) {
    _configuration = WKWebViewConfiguration();
    if (customSchemes.isNotEmpty) {
      _configuration.setCustomSchemes(customSchemes);
    }
    if (profileName != null) {
      if (sessionMode != WebViewSessionMode.shared) {
        throw ArgumentError('Named profiles must use shared mode.');
      }
      _configuration.setWebsiteDataStore(
        WKWebsiteDataStore.named(name: profileName!),
      );
    }
    _privateOwners = sessionMode == WebViewSessionMode.shared
        ? null
        : _WebKitPrivateStoreOwners();
    if (sessionMode != WebViewSessionMode.shared) {
      _configuration.setWebsiteDataStore(WKWebsiteDataStore.nonPersistent());
    }

    if (this.mediaTypesRequiringUserAction.isEmpty) {
      _configuration.setMediaTypesRequiringUserActionForPlayback(
        AudiovisualMediaType.none,
      );
    } else if (this.mediaTypesRequiringUserAction.length == 1) {
      _configuration.setMediaTypesRequiringUserActionForPlayback(
        this.mediaTypesRequiringUserAction.single._toWKAudiovisualMediaType(),
      );
    } else {
      _configuration.setMediaTypesRequiringUserActionForPlayback(
        AudiovisualMediaType.all,
      );
    }
    _configuration.setAllowsInlineMediaPlayback(allowsInlineMediaPlayback);
    // This property is version-gated, so only request it when the non-default
    // value is needed and report unsupported systems without failing creation.
    if (limitsNavigationsToAppBoundDomains) {
      unawaited(
        _configuration
            .setLimitsNavigationsToAppBoundDomains(
              limitsNavigationsToAppBoundDomains,
            )
            .then(
              (bool supported) {
                if (!supported) {
                  final String requirement =
                      defaultTargetPlatform == TargetPlatform.macOS
                      ? 'macOS 11.0'
                      : 'iOS 14.0';
                  debugPrint(
                    'webview_all_wkwebview: '
                    'limitsNavigationsToAppBoundDomains requires $requirement '
                    'or later. The setting was ignored.',
                  );
                }
              },
              onError: (Object error, StackTrace stackTrace) {
                debugPrint(
                  'webview_all_wkwebview: failed to configure '
                  'limitsNavigationsToAppBoundDomains; the setting was ignored: '
                  '${error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ')}',
                );
              },
            ),
      );
    }
  }

  /// Constructs a [WebKitWebViewControllerCreationParams] using a
  /// [PlatformWebViewControllerCreationParams].
  WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewControllerCreationParams params, {
    Set<PlaybackMediaTypes>? mediaTypesRequiringUserAction,
    bool allowsInlineMediaPlayback = false,
    bool limitsNavigationsToAppBoundDomains = false,
    bool? javaScriptCanOpenWindowsAutomatically,
  }) : this(
         sessionMode: params.sessionMode,
         profileName: params.profileName,
         customSchemes: params.customSchemes,
         mediaPlaybackPolicy: params.mediaPlaybackPolicy,
         mediaTypesRequiringUserAction: mediaTypesRequiringUserAction,
         allowsInlineMediaPlayback: allowsInlineMediaPlayback,
         limitsNavigationsToAppBoundDomains: limitsNavigationsToAppBoundDomains,
         javaScriptCanOpenWindowsAutomatically:
             javaScriptCanOpenWindowsAutomatically,
       );

  late final WKWebViewConfiguration _configuration;
  late final _WebKitPrivateStoreOwners? _privateOwners;

  WebKitWebViewControllerCreationParams._adopt(
    WebKitWebViewControllerCreationParams parent,
    WKWebViewConfiguration configuration,
  ) : mediaTypesRequiringUserAction = parent.mediaTypesRequiringUserAction,
      allowsInlineMediaPlayback = parent.allowsInlineMediaPlayback,
      limitsNavigationsToAppBoundDomains =
          parent.limitsNavigationsToAppBoundDomains,
      javaScriptCanOpenWindowsAutomatically =
          parent.javaScriptCanOpenWindowsAutomatically,
      super(
        sessionMode: parent.sessionMode,
        profileName: parent.profileName,
        customSchemes: parent.customSchemes,
        mediaPlaybackPolicy: parent.mediaPlaybackPolicy,
      ) {
    _configuration = configuration;
    _privateOwners = parent._privateOwners;
  }

  /// Media types that require a user gesture to begin playing.
  ///
  /// Defaults to include [PlaybackMediaTypes.audio] and
  /// [PlaybackMediaTypes.video].
  final Set<PlaybackMediaTypes> mediaTypesRequiringUserAction;

  /// Whether inline playback of HTML5 videos is allowed.
  ///
  /// Defaults to false.
  final bool allowsInlineMediaPlayback;

  /// Whether to limit navigation to configured domains.
  ///
  /// See https://webkit.org/blog/10882/app-bound-domains/
  /// (Only available for iOS > 14.0)
  /// Defaults to false.
  final bool limitsNavigationsToAppBoundDomains;

  /// Whether JavaScript can open windows without user interaction.
  ///
  /// When `null`, the platform's native default is used
  /// (`false` on iOS, `true` on macOS).
  final bool? javaScriptCanOpenWindowsAutomatically;
}

/// An implementation of [PlatformWebViewController] with the WebKit api.
class WebKitWebViewController extends PlatformWebViewController
    with WebViewResourceControllerMixin, WebViewNetworkControllerMixin {
  static Future<List<String>?> Function(WKUIDelegate, bool, bool)
  _fileSelectorReceiver(WeakReference<WebKitWebViewController> owner) =>
      (_, multiple, directories) async {
        final selector = owner.target?._fileSelector;
        if (selector == null || owner.target?._offscreenCloseFuture != null) {
          return <String>[];
        }
        return invokeWebViewFileSelector(
          selector,
          WebViewFileSelectorParams(
            mode: multiple
                ? WebViewFileSelectorMode.openMultiple
                : WebViewFileSelectorMode.open,
            allowsDirectories: directories,
          ),
        );
      };

  WebViewFileSelector? _fileSelector;

  @override
  Future<void> setFileSelector(WebViewFileSelector? selector) async {
    if (selector != null && !await _webView.isFileSelectorSupported()) {
      debugPrint(
        'webview_all_wkwebview: custom file selection requires macOS or iOS 18.4+ with a compatible build SDK; the engine retains its native file input behavior.',
      );
      return;
    }
    final previous = _fileSelector;
    _fileSelector = selector;
    try {
      await _webView.setFileSelectorEnabled(selector != null);
    } catch (_) {
      _fileSelector = previous;
      rethrow;
    }
  }

  WebViewPopupWindowPolicy _popupWindowPolicy =
      WebViewPopupWindowPolicy.platformDefault;

  static const _browserChannel = MethodChannel(
    'com.abandoft.webview_all_wkwebview/browser',
  );

  @override
  Future<WebViewNetworkCapabilities>
  getNetworkCapabilities() async => const WebViewNetworkCapabilities(
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
    customSchemes: true,
    customSchemeFetch: true,
    customSchemeRequestBodies: true,
    streamingResponses: true,
    limitation:
        'WebKit cannot intercept ordinary HTTP(S) requests through public WKURLSchemeHandler APIs. Custom schemes must be declared at creation; a streamed or oversized request body is unavailable.',
  );
  @override
  Future<bool> configureContentRules(List<Map<String, Object?>> rules) async {
    if (_offscreenCloseFuture != null) return false;
    await _webView.getUrl();
    return await _browserChannel.invokeMethod<bool>('setContentRules', {
          'webViewId': webViewIdentifier,
          'rules': rules,
        }) ??
        false;
  }

  @override
  Future<bool> configureNetworkBridge(
    Map<String, Object?> configuration,
  ) async {
    if (_offscreenCloseFuture != null || configuration['kind'] != 'schemes') {
      return false;
    }
    await _webView.getUrl();
    return await const MethodChannel(
          'com.abandoft.webview_all/resources',
        ).invokeMethod<bool>('configureSchemes', {
          'webViewId': webViewIdentifier,
          ...configuration,
        }) ??
        false;
  }

  @override
  Future<PlatformWebViewController?> createRelatedController() =>
      browserOperation<PlatformWebViewController?>(
        'createRelatedController',
        null,
        () async {
          if (_offscreenCloseFuture != null) return null;
          await _webView.getUrl();
          final ids = await _browserChannel.invokeMapMethod<String, Object?>(
            'createRelatedView',
            {'webViewId': webViewIdentifier},
          );
          if (ids == null) return null;
          final manager = PigeonInstanceManager.instance;
          // ignore: invalid_use_of_protected_member
          final config = WKWebViewConfiguration.pigeon_detached();
          final configId = (ids['configurationId']! as num).toInt();
          manager.addHostCreatedInstance(config, configId);
          final child = WebKitWebViewController._(
            WebKitWebViewControllerCreationParams._adopt(
              _webKitParams,
              manager.getInstanceWithWeakReference(configId)!
                  as WKWebViewConfiguration,
            ),
            adoptedViewId: (ids['webViewId']! as num).toInt(),
          );
          try {
            await child._webView.getUrl();
            return child;
          } catch (_) {
            await child.closeWebViewSession();
            rethrow;
          }
        },
      );

  @override
  Future<WebViewNavigationState?>
  saveNavigationState() => browserOperation<WebViewNavigationState?>(
    'saveNavigationState',
    null,
    () async {
      if (_offscreenCloseFuture != null) return null;
      await _webView.getUrl();
      final id = await _browserChannel.invokeMethod<String>(
        'saveNavigationState',
        {'webViewId': webViewIdentifier},
      );
      if (id == null) {
        debugPrint(
          'webview_all_wkwebview: native navigation snapshots require iOS 15/macOS 12 and an available page. Dispose unused snapshots if the limit was reached.',
        );
        return null;
      }
      return WebViewNavigationState(
        platform: 'wkwebview',
        identifier: id,
        onDispose: () => _browserChannel.invokeMethod<void>(
          'releaseNavigationState',
          {'stateId': id},
        ),
      );
    },
  );

  @override
  Future<bool> restoreNavigationState(WebViewNavigationState state) =>
      browserOperation('restoreNavigationState', false, () async {
        if (_offscreenCloseFuture != null ||
            !acceptsNavigationState(state, 'wkwebview')) {
          return false;
        }
        await _webView.getUrl();
        prepareJavaScriptForNavigation();
        return await _browserChannel.invokeMethod<bool>(
              'restoreNavigationState',
              {'webViewId': webViewIdentifier, 'stateId': state.identifier},
            ) ??
            false;
      });
  static final _browserControllers =
      <int, WeakReference<WebKitWebViewController>>{};
  static bool _browserReceiverInstalled = false;
  bool _browserEventsObserved = false;
  FutureOr<void> Function(WebViewNewWindowRequest<PlatformWebViewController>)?
  _newWindowDelegate;
  VoidCallback? _onWindowCloseRequested;
  bool _nativeFullscreen = false;

  @override
  Future<void> setFullscreenDelegate(
    WebViewFullscreenDelegate? delegate,
  ) async {
    if (_offscreenCloseFuture != null) return;
    await _webView.getUrl();
    _observeBrowserEvents();
    await updateFullscreenDelegate(delegate);
    final supported = await _browserChannel.invokeMethod<bool>(
      'setFullscreenDelegateEnabled',
      {'webViewId': webViewIdentifier, 'enabled': delegate != null},
    );
    if (supported != true && delegate != null) {
      await updateFullscreenDelegate(null);
      debugPrint(
        'webview_all_wkwebview: fullscreen notifications require iOS 16 or macOS 13. Native video presentation remains system-managed.',
      );
    }
  }

  @override
  Future<bool> exitFullscreen() async {
    if (_offscreenCloseFuture != null || !_nativeFullscreen) return false;
    return exitDocumentFullscreen();
  }

  @override
  Future<void> setOnProcessFailed(
    FutureOr<void> Function(WebViewProcessFailure)? callback,
  ) async {
    if (_offscreenCloseFuture != null) return;
    await _webView.getUrl();
    _observeBrowserEvents();
    updateProcessFailureCallback(callback);
    await _browserChannel.invokeMethod<void>('observeProcessFailures', {
      'webViewId': webViewIdentifier,
    });
  }

  void _observeBrowserEvents() {
    _browserEventsObserved = true;
    _browserControllers.removeWhere((_, value) => value.target == null);
    _browserControllers[webViewIdentifier] = WeakReference(this);
    if (_browserReceiverInstalled) return;
    _browserReceiverInstalled = true;
    _browserChannel.setMethodCallHandler((call) async {
      final args = Map<Object?, Object?>.from(call.arguments as Map);
      final owner =
          _browserControllers[(args['webViewId'] as num?)?.toInt()]?.target;
      if (owner == null || owner._offscreenCloseFuture != null) return;
      if (call.method == 'newWindowRequested') {
        await owner._handleNewWindowRequest(args);
      } else if (call.method == 'windowCloseRequested') {
        try {
          owner._onWindowCloseRequested?.call();
        } catch (error) {
          debugPrint(
            'webview_all_wkwebview: window-close callback failed: $error',
          );
        }
      } else if (call.method == 'fullscreenChanged') {
        owner._nativeFullscreen = args['active'] == true;
        if (owner._nativeFullscreen) {
          await owner.notifyFullscreenEntered();
        } else {
          await owner.notifyFullscreenExited();
        }
      } else if (call.method == 'processFailed') {
        owner._nativeFullscreen = false;
        owner._navigationGeneration++;
        await owner.notifyProcessFailed(
          const WebViewProcessFailure(
            kind: WebViewProcessFailureKind.rendererExited,
            recovery: WebViewProcessRecovery.reload,
            description:
                'The WebKit content process exited. Reload the page to recover.',
          ),
        );
      }
    });
  }

  @override
  Future<void> setNewWindowDelegate(
    FutureOr<void> Function(WebViewNewWindowRequest<PlatformWebViewController>)?
    delegate,
  ) async {
    if (_offscreenCloseFuture != null) return;
    await _webView.getUrl();
    _observeBrowserEvents();
    final previous = _newWindowDelegate;
    _newWindowDelegate = delegate;
    try {
      await _browserChannel.invokeMethod<void>('setPopupWindowPolicy', {
        'webViewId': webViewIdentifier,
        'policy': _popupWindowPolicy.index,
      });
      await _browserChannel.invokeMethod<void>('setNewWindowDelegateEnabled', {
        'webViewId': webViewIdentifier,
        'enabled': delegate != null,
      });
    } catch (error) {
      _newWindowDelegate = previous;
      debugPrint(
        'webview_all_wkwebview: new-window delegation is unavailable: $error',
      );
    }
  }

  @override
  Future<void> setOnWindowCloseRequested(VoidCallback? callback) async {
    if (_offscreenCloseFuture != null) return;
    await _webView.getUrl();
    _observeBrowserEvents();
    _onWindowCloseRequested = callback;
    await _browserChannel.invokeMethod<void>('observeWindowClose', {
      'webViewId': webViewIdentifier,
    });
  }

  Future<void> _handleNewWindowRequest(Map<Object?, Object?> args) async {
    final id = args['requestId']! as String;
    WebKitWebViewController? created;
    final request = WebViewNewWindowRequest<PlatformWebViewController>(
      url: Uri.tryParse(args['url'] as String? ?? ''),
      onCreateController: () async {
        final identifiers = await _browserChannel
            .invokeMapMethod<String, Object?>('claimNewWindow', {
              'webViewId': webViewIdentifier,
              'requestId': id,
            });
        if (identifiers == null) return null;
        final manager = PigeonInstanceManager.instance;
        // ignore: invalid_use_of_protected_member
        final configuration = WKWebViewConfiguration.pigeon_detached();
        final configId = (identifiers['configurationId']! as num).toInt();
        manager.addHostCreatedInstance(configuration, configId);
        final weakConfiguration =
            manager.getInstanceWithWeakReference(configId)!
                as WKWebViewConfiguration;
        final child = WebKitWebViewController._(
          WebKitWebViewControllerCreationParams._adopt(
            _webKitParams,
            weakConfiguration,
          ),
          adoptedViewId: (identifiers['webViewId']! as num).toInt(),
        );
        try {
          await child._webView.getUrl();
        } catch (_) {
          try {
            await child.closeWebViewSession();
          } catch (_) {}
          rethrow;
        }
        return created = child;
      },
      onAttach: (child) async {
        final valid =
            identical(child, created) &&
            created != null &&
            created!._offscreenCloseFuture == null &&
            _offscreenCloseFuture == null;
        if (!valid) {
          debugPrint(
            'webview_all_wkwebview: use request.createController() to obtain WebKit\'s related child; independent controllers cannot preserve the opener and POST request.',
          );
        }
        return await _browserChannel.invokeMethod<bool>('attachNewWindow', {
              'webViewId': webViewIdentifier,
              'requestId': id,
              'childWebViewId': valid ? created!.webViewIdentifier : null,
            }) ??
            false;
      },
      onReject: () => _browserChannel.invokeMethod<void>('attachNewWindow', {
        'webViewId': webViewIdentifier,
        'requestId': id,
      }),
    );
    await dispatchWebViewNewWindowRequest(_newWindowDelegate, request);
  }

  @override
  Future<bool> setMediaPlaybackSuspended(
    bool suspended,
  ) => browserOperation('setMediaPlaybackSuspended', false, () async {
    await _webView.getUrl();
    final accepted =
        await _browserChannel.invokeMethod<bool>('setMediaPlaybackSuspended', {
          'webViewId': webViewIdentifier,
          ...{'suspended': suspended},
        }) ??
        false;
    if (!accepted) {
      debugPrint(
        'webview_all_wkwebview: setMediaPlaybackSuspended is unavailable in this engine or the native view is closed.',
      );
    }
    return accepted;
  });

  @override
  Future<bool> pauseMedia() => browserOperation('pauseMedia', false, () async {
    await _webView.getUrl();
    final accepted =
        await _browserChannel.invokeMethod<bool>('pauseMedia', {
          'webViewId': webViewIdentifier,
          ...{},
        }) ??
        false;
    if (!accepted) {
      debugPrint(
        'webview_all_wkwebview: pauseMedia is unavailable in this engine or the native view is closed.',
      );
    }
    return accepted;
  });

  @override
  Future<bool> setContextMenuEnabled(
    bool enabled,
  ) => browserOperation('setContextMenuEnabled', false, () async {
    await _webView.getUrl();
    final accepted =
        await _browserChannel.invokeMethod<bool>('setContextMenuEnabled', {
          'webViewId': webViewIdentifier,
          ...{'enabled': enabled},
        }) ??
        false;
    if (!accepted) {
      debugPrint(
        'webview_all_wkwebview: setContextMenuEnabled is unavailable in this engine or the native view is closed.',
      );
    }
    return accepted;
  });

  @override
  Future<Uint8List?> createArchive({required WebViewArchiveFormat format}) {
    if (format != WebViewArchiveFormat.webArchive) {
      return super.createArchive(format: format);
    }
    return capturePageData('Page archive', () async {
      if (_offscreenCloseFuture != null) return null;
      await _webView.getUrl();
      return _browserChannel.invokeMethod<Uint8List>('createArchive', {
        'webViewId': webViewIdentifier,
        'format': format.name,
      });
    });
  }

  @override
  Future<WebViewPrintJob?> printPage({String jobName = 'Web page'}) async {
    if (_offscreenCloseFuture != null) return null;
    await _webView.getUrl();
    return startNativePrint(
      jobName,
      (method, args) => _browserChannel.invokeMethod<Object?>(method, {
        ...args,
        'webViewId': webViewIdentifier,
      }),
    );
  }

  @override
  Future<Uint8List?> takeScreenshot({
    WebViewScreenshotOptions options = const WebViewScreenshotOptions(),
  }) => captureScreenshot(
    options,
    () => _offscreenCloseFuture != null
        ? Future<Uint8List?>.value()
        : _browserChannel.invokeMethod<Uint8List>('takeScreenshot', {
            'webViewId': PigeonInstanceManager.instance.getIdentifier(
              _webView.nativeWebView,
            )!,
          }),
  );

  @override
  Future<Uint8List?> createPdf({WebViewPdfOptions? options}) =>
      capturePageData('PDF export', () {
        if (options != null && !options.isValid) {
          throw ArgumentError('Invalid PDF paper size or margins.');
        }
        return _offscreenCloseFuture != null
            ? Future<Uint8List?>.value()
            : _browserChannel.invokeMethod<Uint8List>('createPdf', {
                'options': options?.toMap(),
                'webViewId': PigeonInstanceManager.instance.getIdentifier(
                  _webView.nativeWebView,
                )!,
              });
      });

  @override
  Future<WebViewBrowserCapabilities> getBrowserCapabilities() async {
    await _webView.getUrl();
    bool fullscreen = false;
    bool navigationState = false;
    try {
      final nativeCaps = await _browserChannel.invokeMapMethod<String, Object?>(
        'browserCapabilities',
        {'webViewId': webViewIdentifier},
      );
      fullscreen = nativeCaps?['fullscreenEvents'] == true;
      navigationState = nativeCaps?['navigationState'] == true;
    } catch (_) {
      /* An older host may not expose auxiliary browser operations. */
    }
    return WebViewBrowserCapabilities(
      newWindowDelegate: true,
      windowCloseRequests: true,
      fullscreenEvents: fullscreen,
      processFailureEvents: true,
      navigationState: navigationState,
      viewportScreenshot: true,
      archiveFormats: const {WebViewArchiveFormat.webArchive},
      contextMenuControl: defaultTargetPlatform == TargetPlatform.macOS,
      pauseMedia: navigationState,
      suspendMedia: navigationState,
      printing: true,
      printJobState: true,
      printCancellation: defaultTargetPlatform == TargetPlatform.iOS,
      screenshotRegion: true,
      screenshotScale: true,
      pdfExport: true,
      pdfPageLayout: true,
      stopLoading: true,
      mediaPlaybackPolicyAtCreation: true,
      navigationHistory: true,
      historyNavigation: true,
      findText: true,
      fileSelector: await _webView.isFileSelectorSupported(),
      popupWindowPolicies: const {
        WebViewPopupWindowPolicy.platformDefault,
        WebViewPopupWindowPolicy.deny,
        WebViewPopupWindowPolicy.sameView,
      },
      limitation:
          'WebKit does not report text-search match counts. Media playback gesture requirements must be configured before creating the WebView.',
    );
  }

  @override
  Future<void> stopLoading() => _webView.stopLoading();

  @override
  Future<WebViewNavigationHistory> getNavigationHistory() async =>
      WebViewNavigationHistory.fromMap(await _webView.getNavigationHistory());

  @override
  Future<bool> goToHistoryIndex(int index) => _webView.goToHistoryIndex(index);

  @override
  Future<WebViewFindResult?> findText(
    String text, {
    bool forward = true,
    bool caseSensitive = false,
    bool wrapAround = true,
  }) async {
    if (text.isEmpty) {
      await clearFindMatches();
      return const WebViewFindResult(matchFound: false);
    }
    return serializeTextSearch(() async {
      final data = await _webView
          .findText(text, forward, caseSensitive, wrapAround)
          .then<Map<String, Object?>?>((value) => value)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () async {
              await _webView.clearFindMatches();
              debugPrint(
                'webview_all_wkwebview: text search timed out and was cancelled.',
              );
              return null;
            },
          );
      return data == null ? null : WebViewFindResult.fromMap(data);
    });
  }

  @override
  Future<void> clearFindMatches() =>
      serializeTextSearch(() => _webView.clearFindMatches());

  @override
  Future<void> setPopupPolicy(WebViewPopupWindowPolicy policy) async {
    _popupWindowPolicy = policy;
    if (_browserEventsObserved) {
      await _browserChannel.invokeMethod<void>('setPopupWindowPolicy', {
        'webViewId': webViewIdentifier,
        'policy': policy.index,
      });
    }
  }

  @override
  String get resourceUrlScheme => 'webview-all-resource';

  @override
  Future<void> configureResourceBridge(
    String channel,
    String host,
    bool enabled,
  ) async {
    if (_offscreenCloseFuture != null) {
      throw StateError('The WebKit WebView was closed.');
    }
    await _webView.getUrl();
    await const MethodChannel(
      'com.abandoft.webview_all/resources',
    ).invokeMethod<void>('configure', <String, Object?>{
      'webViewId': webViewIdentifier,
      'channel': channel,
      'host': host,
      'enabled': enabled,
    });
  }

  WebKitDownloadDelegateBridge? _downloadBridge;
  Future<void> _downloadUpdateTail = Future<void>.value();

  @override
  Future<void> setDownloadDelegate(WebViewDownloadDelegate? delegate) {
    if (_offscreenCloseFuture != null) {
      throw StateError('This WebView controller has been closed.');
    }
    final update = _downloadUpdateTail.catchError((Object _) {}).then((
      _,
    ) async {
      if (_offscreenCloseFuture != null) return;
      if (_downloadBridge != null) {
        await _downloadBridge!.update(delegate);
      } else if (delegate != null) {
        final bridge = WebKitDownloadDelegateBridge(
          webViewIdentifier,
          delegate,
        );
        await bridge.enable();
        _downloadBridge = bridge;
      }
    });
    _downloadUpdateTail = update;
    return update;
  }

  /// Constructs a [WebKitWebViewController].
  WebKitWebViewController(PlatformWebViewControllerCreationParams params)
    : this._(params);

  WebKitWebViewController._(
    PlatformWebViewControllerCreationParams params, {
    int? adoptedViewId,
  }) : _adoptedViewId = adoptedViewId,
       super.implementation(
         adoptedViewId == null ? _paramsForController(params) : params,
       ) {
    final owners = _webKitParams._privateOwners;
    if (owners != null) owners.owners++;
    _webView.addObserver(
      _webView.nativeWebView,
      'estimatedProgress',
      <KeyValueObservingOptions>[KeyValueObservingOptions.newValue],
    );
    _webView.addObserver(
      _webView.nativeWebView,
      'URL',
      <KeyValueObservingOptions>[KeyValueObservingOptions.newValue],
    );

    _webView.addObserver(
      _webView.nativeWebView,
      'title',
      <KeyValueObservingOptions>[KeyValueObservingOptions.newValue],
    );

    _webView.addObserver(
      _webView.nativeWebView,
      'canGoBack',
      <KeyValueObservingOptions>[KeyValueObservingOptions.newValue],
    );

    final weakThis = WeakReference<WebKitWebViewController>(this);
    _uiDelegate = WKUIDelegate(
      onFileSelector: _fileSelectorReceiver(weakThis),
      onCreateWebView:
          (
            _,
            WKWebView webView,
            WKWebViewConfiguration configuration,
            WKNavigationAction navigationAction,
          ) {
            final owner = weakThis.target;
            if (owner == null || owner._offscreenCloseFuture != null) return;
            final bool isForMainFrame =
                navigationAction.targetFrame?.isMainFrame ?? false;
            if (!isForMainFrame &&
                owner._popupWindowPolicy != WebViewPopupWindowPolicy.deny) {
              PlatformWebView.fromNativeWebView(
                webView,
              ).load(navigationAction.request);
            }
          },
      requestMediaCapturePermission:
          (
            WKUIDelegate instance,
            WKWebView webView,
            WKSecurityOrigin origin,
            WKFrameInfo frame,
            MediaCaptureType type,
          ) async {
            final void Function(PlatformWebViewPermissionRequest)? callback =
                weakThis.target?._onPermissionRequestCallback;

            if (callback == null) {
              // The default response for iOS is to prompt. See
              // https://developer.apple.com/documentation/webkit/wkuidelegate/3763087-webview?language=objc
              return PermissionDecision.prompt;
            } else {
              late final Set<WebViewPermissionResourceType> types;
              switch (type) {
                case MediaCaptureType.camera:
                  types = <WebViewPermissionResourceType>{
                    WebViewPermissionResourceType.camera,
                  };
                case MediaCaptureType.cameraAndMicrophone:
                  types = <WebViewPermissionResourceType>{
                    WebViewPermissionResourceType.camera,
                    WebViewPermissionResourceType.microphone,
                  };
                case MediaCaptureType.microphone:
                  types = <WebViewPermissionResourceType>{
                    WebViewPermissionResourceType.microphone,
                  };
                case MediaCaptureType.unknown:
                  // The default response for iOS is to prompt. See
                  // https://developer.apple.com/documentation/webkit/wkuidelegate/3763087-webview?language=objc
                  return PermissionDecision.prompt;
              }

              final decisionCompleter = Completer<PermissionDecision>();

              callback(
                WebKitWebViewPermissionRequest._(
                  types: types,
                  onDecision: decisionCompleter.complete,
                ),
              );

              return decisionCompleter.future;
            }
          },
      runJavaScriptAlertPanel:
          (_, __, String message, WKFrameInfo frame) async {
            final Future<void> Function(JavaScriptAlertDialogRequest request)?
            callback = weakThis.target?._onJavaScriptAlertDialog;
            if (callback != null) {
              final request = JavaScriptAlertDialogRequest(
                message: message,
                url: await frame.request?.getUrl() ?? '',
              );
              await callback.call(request);
              return;
            }
          },
      runJavaScriptConfirmPanel:
          (_, __, String message, WKFrameInfo frame) async {
            final Future<bool> Function(JavaScriptConfirmDialogRequest request)?
            callback = weakThis.target?._onJavaScriptConfirmDialog;
            if (callback != null) {
              final request = JavaScriptConfirmDialogRequest(
                message: message,
                url: await frame.request?.getUrl() ?? '',
              );
              final bool result = await callback.call(request);
              return result;
            }

            return false;
          },
      runJavaScriptTextInputPanel:
          (_, __, String prompt, String? defaultText, WKFrameInfo frame) async {
            final Future<String> Function(
              JavaScriptTextInputDialogRequest request,
            )?
            callback = weakThis.target?._onJavaScriptTextInputDialog;
            if (callback != null) {
              final request = JavaScriptTextInputDialogRequest(
                message: prompt,
                url: await frame.request?.getUrl() ?? '',
                defaultText: defaultText,
              );
              final String result = await callback.call(request);
              return result;
            }

            return '';
          },
    );

    _webView.setUIDelegate(_uiDelegate);
  }

  static const String _onConsoleMessageChannelName = 'fltConsoleMessage';

  int _nextUserScriptIdentifier = 0;
  int _navigationGeneration = 0;
  final Map<String, WebViewJavaScriptWorld> _javaScriptChannelWorlds = {};
  Future<void>? _offscreenCloseFuture;
  late final VoidCallback _navigationStartCallback = withWeakReferenceTo(this, (
    WeakReference<WebKitWebViewController> weakReference,
  ) {
    return () {
      final WebKitWebViewController? controller = weakReference.target;
      if (controller != null) {
        controller._navigationGeneration += 1;
        controller.cancelJavaScriptHandlerCalls();
      }
    };
  });
  final Map<String, WebViewUserScript> _registeredUserScripts =
      <String, WebViewUserScript>{};
  // Native cleanup uses the installed world, even after a registration changes.
  final Map<String, WebViewJavaScriptWorld> _installedJavaScriptChannelWorlds =
      {};
  Future<void> _scriptUpdateTail = Future<void>.value();

  /// The WebKit WebView being controlled.
  final int? _adoptedViewId;
  late final PlatformWebView _webView = _createWebView();

  PlatformWebView _createWebView() {
    final observeValue = withWeakReferenceTo(this, (
      WeakReference<WebKitWebViewController> weakReference,
    ) {
      return (
        _,
        String? keyPath,
        NSObject? object,
        Map<KeyValueChangeKey, Object?>? change,
      ) async {
        final WebKitWebViewController? controller = weakReference.target;
        if (controller == null || change == null) {
          return;
        }

        switch (keyPath) {
          case 'estimatedProgress':
            final ProgressCallback? progressCallback =
                controller._currentNavigationDelegate?._onProgress;
            if (progressCallback != null) {
              final progress = change[KeyValueChangeKey.newValue]! as double;
              progressCallback((progress * 100).round());
            }
          case 'URL':
            final UrlChangeCallback? urlChangeCallback =
                controller._currentNavigationDelegate?._onUrlChange;
            if (urlChangeCallback != null) {
              final url = change[KeyValueChangeKey.newValue] as URL?;
              urlChangeCallback(UrlChange(url: await url?.getAbsoluteString()));
            }
          case 'title':
            if (controller._offscreenCloseFuture != null) return;
            controller._currentNavigationDelegate?._onTitleChange?.call(
              change[KeyValueChangeKey.newValue] as String? ?? '',
            );
          case 'canGoBack':
            if (controller._onCanGoBackChangeCallback != null) {
              final canGoBack = change[KeyValueChangeKey.newValue]! as bool;
              controller._onCanGoBackChangeCallback!(canGoBack);
            }
        }
      };
    });
    return _adoptedViewId == null
        ? PlatformWebView(
            initialConfiguration: _webKitParams._configuration,
            observeValue: observeValue,
          )
        : PlatformWebView.fromIdentifier(
            _adoptedViewId,
            observeValue: observeValue,
          );
  }

  late final WKUIDelegate _uiDelegate;

  late final UIScrollViewDelegate? _uiScrollViewDelegate;

  final Map<String, WebKitJavaScriptChannelParams> _javaScriptChannelParams =
      <String, WebKitJavaScriptChannelParams>{};

  bool _zoomEnabled = true;
  WebKitNavigationDelegate? _currentNavigationDelegate;

  static const Set<String> _unsupportedWebpagePreferencesErrorCodes = <String>{
    // Returned by generated ProxyApi implementations when the operation is
    // unavailable.
    'PigeonUnsupportedOperationError',
    // Returned by the native WebKit delegate on iOS < 14 and macOS < 11.
    'FWFUnsupportedVersionError',
  };

  void _logUnsupportedMacOS(
    String method, {
    String? requirement,
    String? fallback,
  }) {
    final String reason = requirement == null
        ? 'is not available through public macOS WKWebView APIs'
        : 'requires $requirement';
    final String result = fallback == null
        ? 'The call was ignored.'
        : 'Returning $fallback.';
    debugPrint('webview_all_wkwebview: $method $reason. $result');
  }

  void Function(bool)? _onCanGoBackChangeCallback;
  void Function(JavaScriptConsoleMessage)? _onConsoleMessageCallback;
  void Function(PlatformWebViewPermissionRequest)? _onPermissionRequestCallback;

  Future<void> Function(JavaScriptAlertDialogRequest request)?
  _onJavaScriptAlertDialog;
  Future<bool> Function(JavaScriptConfirmDialogRequest request)?
  _onJavaScriptConfirmDialog;
  Future<String> Function(JavaScriptTextInputDialogRequest request)?
  _onJavaScriptTextInputDialog;

  void Function(ScrollPositionChange scrollPositionChange)?
  _onScrollPositionChangeCallback;

  static WebKitWebViewControllerCreationParams _paramsForController(
    PlatformWebViewControllerCreationParams params,
  ) {
    if (params is! WebKitWebViewControllerCreationParams) {
      return WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
        params,
      );
    }
    if (params.sessionMode == WebViewSessionMode.shared) return params;
    // Reusing a creation-params object must not share its private data store.
    return WebKitWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
      params,
      mediaTypesRequiringUserAction: params.mediaTypesRequiringUserAction,
      allowsInlineMediaPlayback: params.allowsInlineMediaPlayback,
      limitsNavigationsToAppBoundDomains:
          params.limitsNavigationsToAppBoundDomains,
      javaScriptCanOpenWindowsAutomatically:
          params.javaScriptCanOpenWindowsAutomatically,
    );
  }

  WebKitWebViewControllerCreationParams get _webKitParams =>
      params as WebKitWebViewControllerCreationParams;

  /// Identifier used to retrieve the underlying native `WKWebView`.
  ///
  /// This is typically used by other plugins to retrieve the native `WKWebView`
  /// from an `FWFInstanceManager`.
  ///
  /// See Objective-C method
  /// `WebviewAllWKWebViewExternalAPI.webView(forIdentifier:withPluginRegistry:)`.
  int get webViewIdentifier =>
      PigeonInstanceManager.instance.getIdentifier(_webView.nativeWebView)!;

  /// Whether horizontal swipe gestures trigger page navigation.
  Future<void> setAllowsBackForwardNavigationGestures(bool enabled) {
    return _webView.setAllowsBackForwardNavigationGestures(enabled);
  }

  /// Whether to allow previews for link destinations and detected data such as
  /// addresses and phone numbers.
  ///
  /// This property is available on devices that support 3D Touch.
  ///
  /// Defaults to true.
  Future<void> setAllowsLinkPreview(bool allow) {
    return _webView.setAllowsLinkPreview(allow);
  }

  /// Sets the listener for canGoBack changes.
  Future<void> setOnCanGoBackChange(
    void Function(bool) onCanGoBackChangeCallback,
  ) async {
    _onCanGoBackChangeCallback = onCanGoBackChangeCallback;
  }

  /// Whether to enable tools for debugging the current WKWebView content.
  ///
  /// It needs to be activated in each WKWebView where you want to enable it.
  ///
  /// Starting from macOS version 13.3, iOS version 16.4, and tvOS version 16.4,
  /// the default value is set to false.
  ///
  /// Defaults to true in previous versions.
  Future<void> setInspectable(bool inspectable) async {
    final bool supported = await _webView.setInspectable(inspectable);
    if (supported) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS(
        'setInspectable',
        requirement: 'macOS 13.3 or later',
      );
    } else {
      debugPrint(
        'webview_all_wkwebview: setInspectable requires iOS 16.4 or later. '
        'The call was ignored.',
      );
    }
  }

  @override
  Future<void> loadFile(String absoluteFilePath) {
    return loadFileWithParams(
      WebKitLoadFileParams(absoluteFilePath: absoluteFilePath),
    );
  }

  @override
  Future<void> loadFileWithParams(LoadFileParams params) {
    switch (params) {
      case final WebKitLoadFileParams params:
        _navigationGeneration += 1;
        prepareJavaScriptForNavigation();
        return _webView.loadFileUrl(
          params.absoluteFilePath,
          params.readAccessPath,
        );

      default:
        return loadFileWithParams(
          WebKitLoadFileParams.fromLoadFileParams(params),
        );
    }
  }

  @override
  Future<void> loadFlutterAsset(String key) {
    assert(key.isNotEmpty);
    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.loadFlutterAsset(key);
  }

  @override
  Future<void> loadHtmlString(String html, {String? baseUrl}) {
    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.loadHtmlString(html, baseUrl);
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) {
    if (!params.uri.hasScheme) {
      throw ArgumentError(
        'LoadRequestParams#uri is required to have a scheme.',
      );
    }

    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.load(
      URLRequest(url: params.uri.toString())
        ..setAllHttpHeaderFields(params.headers)
        ..setHttpMethod(params.method.name)
        ..setHttpBody(params.body),
    );
  }

  @override
  Future<void> addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
  ) => _addJavaScriptChannel(
    javaScriptChannelParams,
    WebViewJavaScriptWorld.page,
  );

  Future<void> _addJavaScriptChannel(
    JavaScriptChannelParams javaScriptChannelParams,
    WebViewJavaScriptWorld world,
  ) async {
    final String channelName = javaScriptChannelParams.name;
    if (channelName.isEmpty) {
      throw ArgumentError.value(
        channelName,
        'javaScriptChannelParams.name',
        'JavaScript channel names must not be empty.',
      );
    }
    final WebKitJavaScriptChannelParams webKitParams =
        javaScriptChannelParams is WebKitJavaScriptChannelParams
        ? javaScriptChannelParams
        : WebKitJavaScriptChannelParams.fromJavaScriptChannelParams(
            javaScriptChannelParams,
          );

    await _serializeScriptUpdate(() async {
      if (_javaScriptChannelParams.containsKey(channelName)) {
        throw ArgumentError(
          'A JavaScriptChannel with name `$channelName` already exists.',
        );
      }
      _javaScriptChannelParams[webKitParams.name] = webKitParams;
      _javaScriptChannelWorlds[webKitParams.name] = world;
      try {
        await _resetUserScripts();
      } catch (_) {
        _javaScriptChannelParams.remove(webKitParams.name);
        _javaScriptChannelWorlds.remove(webKitParams.name);
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<void> removeJavaScriptChannel(String javaScriptChannelName) async {
    assert(javaScriptChannelName.isNotEmpty);
    await _serializeScriptUpdate(() async {
      final WebKitJavaScriptChannelParams? removed = _javaScriptChannelParams
          .remove(javaScriptChannelName);
      if (removed == null) {
        return;
      }
      final WebViewJavaScriptWorld? removedWorld = _javaScriptChannelWorlds
          .remove(javaScriptChannelName);
      try {
        await _resetUserScripts();
      } catch (_) {
        _javaScriptChannelParams[javaScriptChannelName] = removed;
        if (removedWorld != null) {
          _javaScriptChannelWorlds[javaScriptChannelName] = removedWorld;
        }
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<String?> currentUrl() => _webView.getUrl();

  @override
  Future<bool> canGoBack() => _webView.canGoBack();

  @override
  Future<bool> canGoForward() => _webView.canGoForward();

  @override
  Future<void> goBack() {
    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.goBack();
  }

  @override
  Future<void> goForward() {
    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.goForward();
  }

  @override
  Future<void> reload() {
    _navigationGeneration += 1;
    prepareJavaScriptForNavigation();
    return _webView.reload();
  }

  @override
  Future<void> clearCache() async {
    final WKWebsiteDataStore dataStore = await _webView.configuration
        .getWebsiteDataStore();
    await dataStore.removeDataOfTypes(<WebsiteDataType>[
      WebsiteDataType.memoryCache,
      WebsiteDataType.diskCache,
      WebsiteDataType.offlineWebApplicationCache,
    ], 0);
  }

  @override
  Future<void> clearLocalStorage() async {
    final WKWebsiteDataStore dataStore = await _webView.configuration
        .getWebsiteDataStore();
    await dataStore.removeDataOfTypes(<WebsiteDataType>[
      WebsiteDataType.localStorage,
    ], 0);
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    try {
      await _webView.evaluateJavaScript(javaScript);
    } on PlatformException catch (exception) {
      // WebKit will throw an error when the type of the evaluated value is
      // unsupported. This also goes for `null` and `undefined` on iOS 14+. For
      // example, when running a void function. For ease of use, this specific
      // error is ignored when no return value is expected.
      final Object? details = exception.details;
      if (details is! NSError ||
          details.code != WKErrorCode.javaScriptResultTypeIsUnsupported) {
        rethrow;
      }
    }
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    final Object? result = await _webView.evaluateJavaScript(javaScript);
    if (result == null) {
      throw ArgumentError(
        'Result of JavaScript execution returned a `null` value. '
        'Use `runJavascript` when expecting a null return value.',
      );
    }
    return result;
  }

  @override
  Future<Object?> callAsyncJavaScript(JavaScriptInvocationParams params) async {
    if (!params.world.isPage) return invokeAsyncJavaScriptInWorld(params);
    final int navigationGeneration = _navigationGeneration;
    final Stopwatch stopwatch = Stopwatch()..start();
    Duration remainingTime() => params.timeout - stopwatch.elapsed;
    try {
      final Duration remaining = remainingTime();
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'The JavaScript invocation did not complete before the timeout.',
          params.timeout,
        );
      }
      final String normalizedFunctionBody =
          '''
        const __webviewAllValue = await (async () => {
${params.functionBody}
        })();
        const __webviewAllEncoded = JSON.stringify(__webviewAllValue);
        return JSON.stringify({
          value: __webviewAllEncoded === undefined
              ? null
              : __webviewAllEncoded
        });
      ''';
      final Object? result = await _webView
          .callAsyncJavaScript(normalizedFunctionBody, params.arguments)
          .timeout(remaining);
      if (navigationGeneration != _navigationGeneration) {
        throw const JavaScriptExecutionException(
          name: 'NavigationError',
          message: 'The page navigated before JavaScript completed.',
        );
      }
      if (result is! String) {
        throw const JavaScriptExecutionException(
          name: 'SerializationError',
          message: 'WebKit returned an invalid asynchronous JavaScript result.',
        );
      }
      try {
        final Object? envelope = jsonDecode(result);
        if (envelope is! Map<String, Object?> ||
            !envelope.containsKey('value')) {
          throw const FormatException();
        }
        final Object? encodedValue = envelope['value'];
        return encodedValue is String ? jsonDecode(encodedValue) : null;
      } on FormatException {
        throw const JavaScriptExecutionException(
          name: 'SerializationError',
          message: 'WebKit returned an invalid asynchronous JavaScript result.',
        );
      }
    } on PlatformException catch (exception) {
      if (navigationGeneration != _navigationGeneration) {
        throw const JavaScriptExecutionException(
          name: 'NavigationError',
          message: 'The page navigated before JavaScript completed.',
        );
      }
      if (exception.code == 'FWFCallAsyncJavaScriptUnavailable') {
        return _callAsyncJavaScriptLegacy(
          params,
          navigationGeneration,
          stopwatch,
        );
      }
      final Map<Object?, Object?>? details =
          exception.details is Map<Object?, Object?>
          ? exception.details as Map<Object?, Object?>
          : null;
      throw JavaScriptExecutionException(
        name: details?['name']?.toString() ?? exception.code,
        message:
            details?['message']?.toString() ??
            exception.message ??
            'The JavaScript invocation failed.',
        javaScriptStackTrace: details?['stack']?.toString(),
      );
    }
  }

  @override
  Future<void> prepareSession() async {
    await _webView.getTitle();
  }

  @override
  PlatformWebViewCookieManager createSessionCookieManager() =>
      WebKitWebViewCookieManager.forController(_webView);

  @override
  PlatformWebViewDataManager createSessionDataManager() =>
      WebKitWebViewDataManager.forController(_webView);

  @override
  Future<bool> isOffscreenWebViewSupported() async => true;

  @override
  Future<void> closeOffscreenWebView() {
    return _offscreenCloseFuture ??= _closeOffscreenWebView();
  }

  Future<void> _closeOffscreenWebView() async {
    if (_nativeFullscreen) await exitFullscreen();
    disposeBrowserLifecycleCallbacks();
    _newWindowDelegate = null;
    _onWindowCloseRequested = null;
    _browserControllers.remove(
      PigeonInstanceManager.instance.getIdentifier(_webView.nativeWebView),
    );
    disposeJavaScriptHandlers();
    final networkDisposal = disposeNetworkBridges();
    if (networkDisposal != null) await networkDisposal;
    final resourceDisposal = disposeResourceBridge();
    if (resourceDisposal != null) await resourceDisposal;
    _navigationGeneration += 1;
    Object? firstError;
    StackTrace? firstStackTrace;
    WKWebsiteDataStore? privateStore;
    if (params.sessionMode != WebViewSessionMode.shared) {
      try {
        privateStore = await _webView.configuration.getWebsiteDataStore();
      } catch (error, stackTrace) {
        firstError = error;
        firstStackTrace = stackTrace;
      }
    }
    try {
      await _downloadUpdateTail;
    } catch (_) {
      // Failed registration has already removed its messenger handler.
    }
    try {
      await _downloadBridge?.close();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    } finally {
      _downloadBridge = null;
    }
    final WebKitNavigationDelegate? previousDelegate =
        _currentNavigationDelegate;
    if (previousDelegate != null) {
      _webKitNavigationStartCallbacks[previousDelegate]?.remove(
        _navigationStartCallback,
      );
    }
    _currentNavigationDelegate = null;

    try {
      await _scriptUpdateTail;
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    for (final String keyPath in <String>[
      'estimatedProgress',
      'URL',
      'title',
      'canGoBack',
    ]) {
      try {
        await _webView.removeObserver(_webView.nativeWebView, keyPath);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    try {
      await _webView.dispose();
      PigeonInstanceManager.instance.removeWeakReference(
        _webView.nativeWebView,
      );
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
    final owners = _webKitParams._privateOwners;
    if (owners != null) owners.owners--;
    if (privateStore != null && (owners == null || owners.owners == 0)) {
      try {
        // A retained Dart configuration/manager can outlive the native view.
        // Clear this private store after stopping its page, without touching defaults.
        await privateStore.removeDataOfTypes(WebsiteDataType.values, 0);
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<Object?> _callAsyncJavaScriptLegacy(
    JavaScriptInvocationParams params,
    int navigationGeneration,
    Stopwatch stopwatch,
  ) async {
    final String identifier = _createWebKitOpaqueIdentifier(
      'webview_all_async',
    );
    final String encodedIdentifier = jsonEncode(identifier);
    final String argumentNames = params.arguments.keys.join(',');
    final String argumentValues = params.arguments.keys
        .map((String name) => 'args[${jsonEncode(name)}]')
        .join(',');
    Duration remainingTime() => params.timeout - stopwatch.elapsed;
    Future<Object?> evaluateWithinDeadline(String javaScript) {
      final Duration remaining = remainingTime();
      if (remaining <= Duration.zero) {
        return Future<Object?>.error(
          TimeoutException(
            'The JavaScript invocation did not complete before the timeout.',
            params.timeout,
          ),
        );
      }
      return _webView.evaluateJavaScript(javaScript).timeout(remaining);
    }

    final Duration setupRemaining = remainingTime();
    if (setupRemaining <= Duration.zero) {
      throw TimeoutException(
        'The JavaScript invocation did not complete before the timeout.',
        params.timeout,
      );
    }
    final int timeoutMilliseconds = max(1, setupRemaining.inMilliseconds);
    await evaluateWithinDeadline('''
      (function() {
        const results = window.__webviewAllAsyncResults =
            window.__webviewAllAsyncResults || Object.create(null);
        const slot = {result: null};
        results[$encodedIdentifier] = slot;
        const expiresAt = Date.now() + $timeoutMilliseconds;
        const release = function() {
          if (results[$encodedIdentifier] === slot) {
            delete results[$encodedIdentifier];
          }
        };
        const settle = function(result) {
          if (results[$encodedIdentifier] !== slot || Date.now() >= expiresAt) {
            release();
            return;
          }
          slot.result = result;
        };
        setTimeout(release, $timeoutMilliseconds);
        const args = JSON.parse(${jsonEncode(jsonEncode(params.arguments))});
        Promise.resolve().then(function() {
          return (async function($argumentNames) {
${params.functionBody}
          })($argumentValues);
        }).then(function(value) {
          try {
            const encoded = JSON.stringify(value);
            settle({
              state: 'fulfilled',
              value: encoded === undefined ? null : encoded
            });
          } catch (error) {
            settle({
              state: 'rejected',
              name: error && error.name ? String(error.name) : 'Error',
              message: error && error.message ? String(error.message) : String(error),
              stack: error && error.stack ? String(error.stack) : null
            });
          }
        }, function(error) {
          settle({
            state: 'rejected',
            name: error && error.name ? String(error.name) : 'Error',
            message: error && error.message ? String(error.message) : String(error),
            stack: error && error.stack ? String(error.stack) : null
          });
        });
      })();
    ''');

    try {
      while (stopwatch.elapsed < params.timeout) {
        if (navigationGeneration != _navigationGeneration) {
          throw const JavaScriptExecutionException(
            name: 'NavigationError',
            message: 'The page navigated before JavaScript completed.',
          );
        }
        final Object? rawResult = await evaluateWithinDeadline('''
          (function() {
            const values = window.__webviewAllAsyncResults;
            const slot = values && values[$encodedIdentifier];
            const value = slot && slot.result;
            return value ? JSON.stringify(value) : null;
          })();
        ''');
        if (rawResult is String && rawResult.isNotEmpty) {
          final Object? decoded = jsonDecode(rawResult);
          if (decoded is Map<String, Object?>) {
            if (decoded['state'] == 'fulfilled') {
              final Object? encodedValue = decoded['value'];
              return encodedValue is String ? jsonDecode(encodedValue) : null;
            }
            throw JavaScriptExecutionException(
              name: decoded['name']?.toString(),
              message:
                  decoded['message']?.toString() ??
                  'The JavaScript promise was rejected.',
              javaScriptStackTrace: decoded['stack']?.toString(),
            );
          }
        }
        final Duration delayRemaining = remainingTime();
        if (delayRemaining <= Duration.zero) {
          break;
        }
        const Duration pollingInterval = Duration(milliseconds: 20);
        await Future<void>.delayed(
          delayRemaining.compareTo(pollingInterval) < 0
              ? delayRemaining
              : pollingInterval,
        );
      }
      throw TimeoutException(
        'The JavaScript invocation did not complete before the timeout.',
        params.timeout,
      );
    } finally {
      if (navigationGeneration == _navigationGeneration &&
          remainingTime() > Duration.zero) {
        try {
          await evaluateWithinDeadline('''
          if (window.__webviewAllAsyncResults) {
            delete window.__webviewAllAsyncResults[$encodedIdentifier];
          }
        ''');
        } catch (_) {
          // Navigation can replace the document before cleanup completes.
        }
      }
    }
  }

  @override
  Future<WebViewJavaScriptCapabilities> getJavaScriptCapabilities({
    WebViewJavaScriptWorld world = WebViewJavaScriptWorld.page,
  }) async => const WebViewJavaScriptCapabilities(
    supportsPromiseHandlers: true,
    supportsIsolatedWorlds: true,
    supportsTrustedOrigins: true,
    supportsTrustedFrameInformation: true,
    userScriptInjectionTimes: {
      WebViewUserScriptInjectionTime.documentStart,
      WebViewUserScriptInjectionTime.documentEnd,
    },
    limitation: 'Promise handlers currently run in the main document.',
  );

  @override
  Future<Object?> evaluateJavaScriptInWorld(
    String source,
    WebViewJavaScriptWorld world,
  ) => world.isPage
      ? _webView.evaluateJavaScript(source)
      : _webView.evaluateJavaScriptInWorld(source, 'webview_all.${world.name}');

  @override
  Future<void> addJavaScriptChannelInWorld(
    JavaScriptChannelParams params,
    WebViewJavaScriptWorld world,
  ) => _addJavaScriptChannel(params, world);

  @override
  Future<bool> isUserScriptInjectionSupported(
    WebViewUserScriptInjectionTime injectionTime,
  ) async {
    return true;
  }

  @override
  Future<String> addUserScript(WebViewUserScript userScript) async {
    final String identifier =
        'webview_all_user_script_${_nextUserScriptIdentifier++}';
    await _serializeScriptUpdate(() async {
      _registeredUserScripts[identifier] = userScript;
      try {
        await _resetUserScripts();
      } catch (_) {
        _registeredUserScripts.remove(identifier);
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
    return identifier;
  }

  @override
  Future<void> removeUserScript(String identifier) async {
    await _serializeScriptUpdate(() async {
      final WebViewUserScript? removed = _registeredUserScripts.remove(
        identifier,
      );
      if (removed == null) {
        return;
      }
      try {
        await _resetUserScripts();
      } catch (_) {
        _registeredUserScripts[identifier] = removed;
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<void> removeAllUserScripts() async {
    await _serializeScriptUpdate(() async {
      if (_registeredUserScripts.isEmpty) {
        return;
      }
      final Map<String, WebViewUserScript> removed =
          Map<String, WebViewUserScript>.of(_registeredUserScripts)
            ..removeWhere(
              (identifier, _) => isJavaScriptBridgeScript(identifier),
            );
      if (removed.isEmpty) return;
      _registeredUserScripts.removeWhere(
        (identifier, _) => !isJavaScriptBridgeScript(identifier),
      );
      try {
        await _resetUserScripts();
      } catch (_) {
        _registeredUserScripts.addAll(removed);
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<String?> getTitle() => _webView.getTitle();

  @override
  Future<void> scrollTo(int x, int y) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('scrollTo');
      return Future<void>.value();
    }
    return _webView.scrollView.setContentOffset(x.toDouble(), y.toDouble());
  }

  @override
  Future<void> scrollBy(int x, int y) async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('scrollBy');
      return;
    }
    return _webView.scrollView.scrollBy(x.toDouble(), y.toDouble());
  }

  @override
  Future<Offset> getScrollPosition() async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('getScrollPosition', fallback: 'Offset.zero');
      return Offset.zero;
    }
    final List<double> position = await _webView.scrollView.getContentOffset();
    return Offset(position[0], position[1]);
  }

  @override
  Future<void> setVerticalScrollBarEnabled(bool enabled) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('setVerticalScrollBarEnabled');
      return Future<void>.value();
    }
    return _webView.scrollView.setShowsVerticalScrollIndicator(enabled);
  }

  @override
  Future<void> setHorizontalScrollBarEnabled(bool enabled) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('setHorizontalScrollBarEnabled');
      return Future<void>.value();
    }
    return _webView.scrollView.setShowsHorizontalScrollIndicator(enabled);
  }

  @override
  bool supportsSetScrollBarsEnabled() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return true;
      case TargetPlatform.macOS:
        return false;
      case _:
        throw UnsupportedError(
          'This plugin does not support this platform: $defaultTargetPlatform',
        );
    }
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      final bool supported = await _webView.setUnderPageBackgroundColor(
        color.r,
        color.g,
        color.b,
        color.a,
      );
      if (!supported) {
        _logUnsupportedMacOS(
          'setBackgroundColor',
          requirement: 'macOS 12.0 or later',
        );
      }
      return;
    }

    const Color transparent = Colors.transparent;
    await Future.wait(<Future<void>>[
      _webView.setOpaque(false),
      _webView.setBackgroundColor(
        UIColor(
          red: transparent.r,
          green: transparent.g,
          blue: transparent.b,
          alpha: transparent.a,
        ),
      ),
      // This method must be called last.
      _webView.scrollView.setBackgroundColor(
        UIColor(red: color.r, green: color.g, blue: color.b, alpha: color.a),
      ),
    ]);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {
    final bool? javaScriptCanOpenWindowsAutomatically =
        _webKitParams.javaScriptCanOpenWindowsAutomatically;
    if (javaScriptCanOpenWindowsAutomatically != null) {
      final WKPreferences preferences = await _webView.configuration
          .getPreferences();
      await preferences.setJavaScriptCanOpenWindowsAutomatically(
        javaScriptCanOpenWindowsAutomatically,
      );
    }

    if (_adoptedViewId != null) {
      // WebKit's related configuration shares its default webpage preferences.
      // The native navigation delegate keeps this override scoped to the child.
      await _browserChannel.invokeMethod<bool>('setChildJavaScriptEnabled', {
        'webViewId': webViewIdentifier,
        'enabled': javaScriptMode == JavaScriptMode.unrestricted,
      });
      return;
    }

    // Attempt to set the value that requires iOS 14+.
    try {
      final WKWebpagePreferences webpagePreferences = await _webView
          .configuration
          .getDefaultWebpagePreferences();
      switch (javaScriptMode) {
        case JavaScriptMode.disabled:
          await webpagePreferences.setAllowsContentJavaScript(false);
        case JavaScriptMode.unrestricted:
          await webpagePreferences.setAllowsContentJavaScript(true);
      }
      return;
    } on PlatformException catch (exception) {
      if (!_unsupportedWebpagePreferencesErrorCodes.contains(exception.code)) {
        rethrow;
      }
    } catch (exception) {
      rethrow;
    }

    final WKPreferences preferences = await _webView.configuration
        .getPreferences();
    switch (javaScriptMode) {
      case JavaScriptMode.disabled:
        await preferences.setJavaScriptEnabled(false);
      case JavaScriptMode.unrestricted:
        await preferences.setJavaScriptEnabled(true);
    }
  }

  @override
  Future<void> setUserAgent(String? userAgent) {
    return _webView.setCustomUserAgent(userAgent);
  }

  @override
  Future<void> enableZoom(bool enabled) async {
    if (_zoomEnabled == enabled) {
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.macOS) {
      await _webView.setAllowsMagnification(enabled);
      _zoomEnabled = enabled;
      return;
    }

    await _serializeScriptUpdate(() async {
      final bool previous = _zoomEnabled;
      _zoomEnabled = enabled;
      try {
        if (enabled) {
          await _resetUserScripts();
        } else {
          await _disableZoom();
        }
      } catch (_) {
        _zoomEnabled = previous;
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    covariant WebKitNavigationDelegate handler,
  ) {
    final WebKitNavigationDelegate? previousDelegate =
        _currentNavigationDelegate;
    if (previousDelegate != null) {
      _webKitNavigationStartCallbacks[previousDelegate]?.remove(
        _navigationStartCallback,
      );
    }
    _currentNavigationDelegate = handler;
    (_webKitNavigationStartCallbacks[handler] ??= <VoidCallback>{}).add(
      _navigationStartCallback,
    );
    return _webView.setNavigationDelegate(handler._navigationDelegate);
  }

  /// Sets a callback that notifies the host application of any log messages
  /// written to the JavaScript console.
  ///
  /// Because the iOS WKWebView doesn't provide a built-in way to access the
  /// console, setting this callback will inject a custom [WKUserScript] which
  /// overrides the JavaScript `console.debug`, `console.error`, `console.info`,
  /// `console.log` and `console.warn` methods and forwards the console message
  /// via a `JavaScriptChannel` to the host application.
  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    final WebKitJavaScriptChannelParams channelParams =
        WebKitJavaScriptChannelParams(
          name: _onConsoleMessageChannelName,
          onMessageReceived: (JavaScriptMessage message) {
            if (_onConsoleMessageCallback == null) {
              return;
            }

            final consoleLog =
                jsonDecode(message.message) as Map<String, dynamic>;

            JavaScriptLogLevel level;
            switch (consoleLog['level']) {
              case 'error':
                level = JavaScriptLogLevel.error;
              case 'warning':
                level = JavaScriptLogLevel.warning;
              case 'debug':
                level = JavaScriptLogLevel.debug;
              case 'info':
                level = JavaScriptLogLevel.info;
              case 'log':
              default:
                level = JavaScriptLogLevel.log;
            }

            _onConsoleMessageCallback!(
              JavaScriptConsoleMessage(
                level: level,
                message: consoleLog['message']! as String,
              ),
            );
          },
        );
    await _serializeScriptUpdate(() async {
      final void Function(JavaScriptConsoleMessage)? previousCallback =
          _onConsoleMessageCallback;
      _onConsoleMessageCallback = onConsoleMessage;
      if (_javaScriptChannelParams.containsKey(_onConsoleMessageChannelName)) {
        return;
      }
      _javaScriptChannelParams[_onConsoleMessageChannelName] = channelParams;
      try {
        await _resetUserScripts();
      } catch (_) {
        _javaScriptChannelParams.remove(_onConsoleMessageChannelName);
        _onConsoleMessageCallback = previousCallback;
        await _restoreUserScriptsBestEffort();
        rethrow;
      }
    });
  }

  @override
  Future<void> setOverScrollMode(WebViewOverScrollMode mode) {
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      _logUnsupportedMacOS('setOverScrollMode');
      return Future<void>.value();
    }
    return switch (mode) {
      WebViewOverScrollMode.always => Future.wait<void>(<Future<void>>[
        _webView.scrollView.setBounces(true),
        _webView.scrollView.setAlwaysBounceHorizontal(true),
        _webView.scrollView.setAlwaysBounceVertical(true),
      ]),
      WebViewOverScrollMode.ifContentScrolls =>
        Future.wait<void>(<Future<void>>[
          _webView.scrollView.setBounces(true),
          _webView.scrollView.setAlwaysBounceHorizontal(false),
          _webView.scrollView.setAlwaysBounceVertical(false),
        ]),
      WebViewOverScrollMode.never => _webView.scrollView.setBounces(false),
      // This prevents future additions from causing a breaking change.
      // ignore: unreachable_switch_case
      _ => throw UnsupportedError('This platform does not support $mode.'),
    };
  }

  @override
  Future<void> setOnPlatformPermissionRequest(
    void Function(PlatformWebViewPermissionRequest request) onPermissionRequest,
  ) async {
    _onPermissionRequestCallback = onPermissionRequest;
  }

  @override
  Future<void> setOnScrollPositionChange(
    void Function(ScrollPositionChange scrollPositionChange)?
    onScrollPositionChange,
  ) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _onScrollPositionChangeCallback = onScrollPositionChange;

      if (onScrollPositionChange != null) {
        final weakThis = WeakReference<WebKitWebViewController>(this);
        _uiScrollViewDelegate = UIScrollViewDelegate(
          scrollViewDidScroll: (_, __, double x, double y) {
            weakThis.target?._onScrollPositionChangeCallback?.call(
              ScrollPositionChange(x, y),
            );
          },
        );
        return _webView.scrollView.setDelegate(_uiScrollViewDelegate);
      } else {
        _uiScrollViewDelegate = null;
        return _webView.scrollView.setDelegate(null);
      }
    } else {
      _logUnsupportedMacOS('setOnScrollPositionChange');
      return Future<void>.value();
    }
  }

  @override
  Future<String?> getUserAgent() async {
    final String? customUserAgent = await _webView.getCustomUserAgent();
    // Despite the official documentation of `WKWebView.customUserAgent`, the
    // default value seems to be an empty String and not null. It's possible it
    // could depend on the iOS version, so this checks for both.
    if (customUserAgent != null && customUserAgent.isNotEmpty) {
      return customUserAgent;
    }

    return (await _webView.evaluateJavaScript('navigator.userAgent;')
        as String?)!;
  }

  @override
  Future<void> setOnJavaScriptAlertDialog(
    Future<void> Function(JavaScriptAlertDialogRequest request)
    onJavaScriptAlertDialog,
  ) async {
    _onJavaScriptAlertDialog = onJavaScriptAlertDialog;
  }

  @override
  Future<void> setOnJavaScriptConfirmDialog(
    Future<bool> Function(JavaScriptConfirmDialogRequest request)
    onJavaScriptConfirmDialog,
  ) async {
    _onJavaScriptConfirmDialog = onJavaScriptConfirmDialog;
  }

  @override
  Future<void> setOnJavaScriptTextInputDialog(
    Future<String> Function(JavaScriptTextInputDialogRequest request)
    onJavaScriptTextInputDialog,
  ) async {
    _onJavaScriptTextInputDialog = onJavaScriptTextInputDialog;
  }

  Future<T> _serializeScriptUpdate<T>(Future<T> Function() operation) {
    final Completer<T> completer = Completer<T>();
    _scriptUpdateTail = _scriptUpdateTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _restoreUserScriptsBestEffort() async {
    try {
      await _resetUserScripts();
    } catch (error) {
      debugPrint(
        'webview_all_wkwebview: failed to restore WebKit user scripts: '
        '${error.toString().replaceAll(RegExp(r'[\r\n]+'), ' ')}',
      );
    }
  }

  Future<void> _installJavaScriptChannel(
    WKUserContentController controller,
    WebKitJavaScriptChannelParams params,
  ) async {
    final String encodedName = jsonEncode(params.name);
    final world =
        _javaScriptChannelWorlds[params.name] ?? WebViewJavaScriptWorld.page;
    final nativeWorld = 'webview_all.${world.name}';
    if (world.isPage) {
      await controller.addScriptMessageHandler(
        params._messageHandler,
        params.name,
      );
    } else {
      await controller.addScriptMessageHandlerInWorld(
        params._messageHandler,
        params.name,
        nativeWorld,
      );
    }
    _installedJavaScriptChannelWorlds[params.name] = world;
    try {
      final source =
          'window[$encodedName] = window.webkit.messageHandlers[$encodedName];';
      if (world.isPage) {
        await controller.addUserScript(
          WKUserScript(
            source: source,
            injectionTime: UserScriptInjectionTime.atDocumentStart,
            isForMainFrameOnly: false,
          ),
        );
      } else {
        await controller.addUserScriptInWorld(
          source,
          UserScriptInjectionTime.atDocumentStart,
          true,
          nativeWorld,
        );
      }
    } catch (_) {
      if (world.isPage) {
        await controller.removeScriptMessageHandler(params.name);
      } else {
        await controller.removeScriptMessageHandlerInWorld(
          params.name,
          nativeWorld,
        );
      }
      _installedJavaScriptChannelWorlds.remove(params.name);
      rethrow;
    }
  }

  // WKWebView does not support removing a single script on every supported OS
  // version, so the internal and application registries are rebuilt together.
  Future<void> _resetUserScripts() async {
    final WKUserContentController controller = await _webView.configuration
        .getUserContentController();
    await controller.removeAllUserScripts();
    // TODO(bparrishMines): This can be replaced with
    // `removeAllScriptMessageHandlers` once Dart supports runtime version
    // checking. (e.g. The equivalent to @availability in Objective-C.)
    await Future.wait(<Future<void>>[
      for (final channel in _installedJavaScriptChannelWorlds.entries)
        if (!channel.value.isPage)
          controller.removeScriptMessageHandlerInWorld(
            channel.key,
            'webview_all.${channel.value.name}',
          )
        else
          controller.removeScriptMessageHandler(channel.key),
    ]);
    _installedJavaScriptChannelWorlds.clear();

    for (final WebKitJavaScriptChannelParams params
        in _javaScriptChannelParams.values) {
      await _installJavaScriptChannel(controller, params);
    }
    if (!_zoomEnabled) {
      await _disableZoom();
    }
    if (_onConsoleMessageCallback != null) {
      await _injectConsoleOverride();
    }
    for (final userScript in _registeredUserScripts.values) {
      final source = buildUserScriptSource(
        userScript,
        platformHandlesMainFrameOnly: true,
      );
      final time =
          userScript.injectionTime == WebViewUserScriptInjectionTime.documentEnd
          ? UserScriptInjectionTime.atDocumentEnd
          : UserScriptInjectionTime.atDocumentStart;
      if (userScript.world.isPage) {
        await controller.addUserScript(
          WKUserScript(
            source: source,
            injectionTime: time,
            isForMainFrameOnly: userScript.forMainFrameOnly,
          ),
        );
      } else {
        await controller.addUserScriptInWorld(
          source,
          time,
          userScript.forMainFrameOnly,
          'webview_all.${userScript.world.name}',
        );
      }
    }
  }

  Future<void> _disableZoom() async {
    final userScript = WKUserScript(
      source:
          "var meta = document.createElement('meta');\n"
          "meta.name = 'viewport';\n"
          "meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, "
          "user-scalable=no';\n"
          "var head = document.getElementsByTagName('head')[0];head.appendChild(meta);",
      injectionTime: UserScriptInjectionTime.atDocumentEnd,
      isForMainFrameOnly: true,
    );
    final WKUserContentController controller = await _webView.configuration
        .getUserContentController();
    await controller.addUserScript(userScript);
  }

  Future<void> _injectConsoleOverride() async {
    // Within overrideScript, a series of console output methods such as
    // console.log will be rewritten to pass the output content to the Flutter
    // end.
    //
    // These output contents will first be serialized through JSON.stringify(),
    // but if the output content contains cyclic objects, it will encounter the
    // following error.
    // TypeError: JSON.stringify cannot serialize cyclic structures.
    // See https://github.com/flutter/flutter/issues/144535.
    //
    // Considering this is just looking at the logs printed via console.log,
    // the cyclic object is not important, so remove it.
    // Therefore, the replacer parameter of JSON.stringify() is used and the
    // removeCyclicObject method is passed in to solve the error.
    final overrideScript = WKUserScript(
      source:
          '''
(function() {
  if (window._flutter_webview_plugin_overrides) {
    if (typeof window._flutter_webview_plugin_overrides.onError === 'function') {
      window.addEventListener("error", window._flutter_webview_plugin_overrides.onError);
    }
    return;
  }
  const overrides = window._flutter_webview_plugin_overrides = {
    removeCyclicObject: function() {
      const traversalStack = [];
      return function (k, v) {
        if (typeof v !== "object" || v === null) { return v; }
        const currentParentObj = this;
        while (
          traversalStack.length > 0 &&
          traversalStack[traversalStack.length - 1] !== currentParentObj
        ) {
          traversalStack.pop();
        }
        if (traversalStack.includes(v)) { return; }
        traversalStack.push(v);
        return v;
      };
    },
    log: function (type, args) {
      var message = Object.values(args)
          .map(v => typeof(v) === "undefined" ? "undefined" : typeof(v) === "object" ? JSON.stringify(v, overrides.removeCyclicObject()) : v.toString())
          .map(v => v.substring(0, 3000)) // Limit msg to 3000 chars
          .join(", ");

      window.webkit.messageHandlers.$_onConsoleMessageChannelName.postMessage(JSON.stringify({
        level: type,
        message: message
      }));
    }
  };

  ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
    const original = console[level];
    console[level] = function() {
      overrides.log(level === 'warn' ? 'warning' : level, arguments);
      original.apply(console, arguments);
    };
  });

  overrides.onError = function(e) {
    overrides.log("error", [e.message + " at " + e.filename + ":" + e.lineno + ":" + e.colno]);
  };
  function restoreErrorListener() {
    window.addEventListener("error", overrides.onError);
  }
  restoreErrorListener();
  // document.open() clears window listeners, but retains the Document and
  // its observers. Reusing onError prevents duplicate error reports.
  new MutationObserver(restoreErrorListener).observe(document, { childList: true });
})();
      ''',
      injectionTime: UserScriptInjectionTime.atDocumentStart,
      isForMainFrameOnly: true,
    );

    final WKUserContentController controller = await _webView.configuration
        .getUserContentController();
    await controller.addUserScript(overrideScript);
  }
}

/// An implementation of [JavaScriptChannelParams] with the WebKit api.
///
/// See [WebKitWebViewController.addJavaScriptChannel].
@immutable
class WebKitJavaScriptChannelParams extends JavaScriptChannelParams {
  /// Constructs a [WebKitJavaScriptChannelParams].
  WebKitJavaScriptChannelParams({
    required super.name,
    required super.onMessageReceived,
  }) : assert(name.isNotEmpty),
       _messageHandler = WKScriptMessageHandler(
         didReceiveScriptMessage: withWeakReferenceTo(onMessageReceived, (
           WeakReference<void Function(JavaScriptMessage)> weakReference,
         ) {
           return (_, __, WKScriptMessage message) {
             if (weakReference.target != null) {
               // When message.body is null, return '(null)' for consistency
               // with previous implementations.
               weakReference.target!(
                 JavaScriptMessage(
                   message: message.body == null
                       ? '(null)'
                       : message.body.toString(),
                   sourceUrl: message.frameInfo.requestUrl,
                   sourceOrigin: _serializeSourceOrigin(message.frameInfo),
                   isMainFrame: message.frameInfo.isMainFrame,
                 ),
               );
             }
           };
         }),
       );

  /// Constructs a [WebKitJavaScriptChannelParams] using a
  /// [JavaScriptChannelParams].
  WebKitJavaScriptChannelParams.fromJavaScriptChannelParams(
    JavaScriptChannelParams params,
  ) : this(name: params.name, onMessageReceived: params.onMessageReceived);

  final WKScriptMessageHandler _messageHandler;

  static String? _serializeSourceOrigin(WKFrameInfo frame) {
    final WKSecurityOrigin origin = frame.securityOrigin;
    final String scheme = origin.securityProtocol.toLowerCase();
    final String nativeHost = origin.host.toLowerCase();
    final String host = nativeHost.startsWith('[') && nativeHost.endsWith(']')
        ? nativeHost.substring(1, nativeHost.length - 1)
        : nativeHost;
    if (scheme.isEmpty && host.isEmpty && origin.port == 0) {
      return 'null';
    }
    // WebKit's public origin tuple does not describe every scheme reliably.
    if ((scheme != 'http' && scheme != 'https') ||
        host.isEmpty ||
        origin.port < 0 ||
        origin.port > 65535) {
      return null;
    }

    int? port = origin.port;
    if (port == 0) {
      // WKSecurityOrigin uses 0 for both an absent port and explicit :0.
      // Only use the native URL to disambiguate an already matching tuple.
      final Uri? request = Uri.tryParse(frame.requestUrl ?? '');
      if (request == null ||
          request.scheme.toLowerCase() != scheme ||
          request.host.toLowerCase() != host) {
        return null;
      }
      if (request.hasPort && request.port != 0) {
        return null;
      }
      port = request.hasPort ? 0 : null;
    }
    try {
      return Uri(scheme: scheme, host: host, port: port).origin;
    } on FormatException {
      return null;
    }
  }
}

/// Object specifying creation parameters for a [WebKitWebViewWidget].
@immutable
class WebKitWebViewWidgetCreationParams
    extends PlatformWebViewWidgetCreationParams {
  /// Constructs a [WebKitWebViewWidgetCreationParams].
  const WebKitWebViewWidgetCreationParams({
    super.key,
    required super.controller,
    super.layoutDirection,
    super.gestureRecognizers,
    this.uiKitGestureBlockingPolicy =
        WebKitGestureBlockingPolicy.fallbackToPluginDefault,
  });

  /// Constructs a [WebKitWebViewWidgetCreationParams] using a
  /// [PlatformWebViewWidgetCreationParams].
  WebKitWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
    PlatformWebViewWidgetCreationParams params, {
    Enum? uiKitGestureBlockingPolicy,
  }) : this(
         key: params.key,
         controller: params.controller,
         layoutDirection: params.layoutDirection,
         gestureRecognizers: params.gestureRecognizers,
         uiKitGestureBlockingPolicy:
             uiKitGestureBlockingPolicy ??
             (params is WebKitWebViewWidgetCreationParams
                 ? params.uiKitGestureBlockingPolicy
                 : WebKitGestureBlockingPolicy.fallbackToPluginDefault),
       );

  /// How Flutter blocks gesture recognizers on the native iOS WebView.
  ///
  /// Accepts [WebKitGestureBlockingPolicy], or Flutter's
  /// `UiKitViewGestureBlockingPolicy` on SDKs that provide it.
  ///
  /// Defaults to [WebKitGestureBlockingPolicy.fallbackToPluginDefault].
  /// `doNotBlockGesture` requires Flutter 3.47 or later. Unsupported policies
  /// print a diagnostic and retain the default behavior. macOS also retains its
  /// default behavior. Changing this setting recreates the platform view.
  final Enum uiKitGestureBlockingPolicy;

  @override
  int get hashCode =>
      Object.hash(controller, layoutDirection, uiKitGestureBlockingPolicy.name);

  @override
  bool operator ==(Object other) {
    return other is WebKitWebViewWidgetCreationParams &&
        controller == other.controller &&
        layoutDirection == other.layoutDirection &&
        uiKitGestureBlockingPolicy.name ==
            other.uiKitGestureBlockingPolicy.name;
  }
}

/// An implementation of [PlatformWebViewWidget] with the WebKit api.
class WebKitWebViewWidget extends PlatformWebViewWidget {
  /// Constructs a [WebKitWebViewWidget].
  WebKitWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(
        params is WebKitWebViewWidgetCreationParams
            ? params
            : WebKitWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                params,
              ),
      );

  WebKitWebViewWidgetCreationParams get _webKitParams =>
      params as WebKitWebViewWidgetCreationParams;

  String _platformViewType() {
    final String policy = _webKitParams.uiKitGestureBlockingPolicy.name;
    if (policy == 'fallbackToPluginDefault') {
      return _webKitWebViewPlatformViewType;
    }
    final bool known = WebKitGestureBlockingPolicy.values.any(
      (value) => value.name == policy,
    );
    String? restriction;
    if (!known) {
      restriction = 'Unknown gesture blocking policy "$policy".';
    } else if (defaultTargetPlatform != TargetPlatform.iOS) {
      restriction = 'Gesture blocking policies are only supported on iOS.';
    } else if (policy == 'doNotBlockGesture' &&
        !_supportsUiKitGestureBlockingPolicy) {
      restriction = 'doNotBlockGesture requires Flutter 3.47 or later.';
    }
    if (restriction != null) {
      debugPrint(
        'webview_all: $restriction Using the default WebView gesture policy.',
      );
      return _webKitWebViewPlatformViewType;
    }
    return '$_webKitWebViewPlatformViewType/gesture/$policy';
  }

  @override
  Widget build(BuildContext context) {
    final String viewType = _platformViewType();
    // Setting a default key using `params` ensures the `UIKitView` recreates
    // the PlatformView when changes are made.
    final Key key =
        _webKitParams.key ??
        ValueKey<WebKitWebViewWidgetCreationParams>(
          params as WebKitWebViewWidgetCreationParams,
        );
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return AppKitView(
        key: key,
        viewType: viewType,
        onPlatformViewCreated: (_) {},
        layoutDirection: params.layoutDirection,
        gestureRecognizers: params.gestureRecognizers,
        creationParams: PigeonInstanceManager.instance.getIdentifier(
          (params.controller as WebKitWebViewController)._webView.nativeWebView,
        ),
        creationParamsCodec: const StandardMessageCodec(),
      );
    } else {
      return UiKitView(
        key: key,
        viewType: viewType,
        onPlatformViewCreated: (_) {},
        layoutDirection: params.layoutDirection,
        gestureRecognizers: params.gestureRecognizers,
        creationParams: PigeonInstanceManager.instance.getIdentifier(
          (params.controller as WebKitWebViewController)._webView.nativeWebView,
        ),
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
  }
}

/// An implementation of [WebResourceError] with the WebKit API.
class WebKitWebResourceError extends WebResourceError {
  WebKitWebResourceError._(
    this._nsError, {
    required bool isForMainFrame,
    required super.url,
  }) : super(
         errorCode: _nsError.code,
         description:
             _nsError.userInfo[NSErrorUserInfoKey.NSLocalizedDescription]
                 as String? ??
             '',
         errorType: _toWebResourceErrorType(_nsError.code),
         isForMainFrame: isForMainFrame,
       );

  static WebResourceErrorType? _toWebResourceErrorType(int code) {
    switch (code) {
      case WKErrorCode.unknown:
        return WebResourceErrorType.unknown;
      case WKErrorCode.webContentProcessTerminated:
        return WebResourceErrorType.webContentProcessTerminated;
      case WKErrorCode.webViewInvalidated:
        return WebResourceErrorType.webViewInvalidated;
      case WKErrorCode.javaScriptExceptionOccurred:
        return WebResourceErrorType.javaScriptExceptionOccurred;
      case WKErrorCode.javaScriptResultTypeIsUnsupported:
        return WebResourceErrorType.javaScriptResultTypeIsUnsupported;
    }

    return null;
  }

  /// A string representing the domain of the error.
  String? get domain => _nsError.domain;

  final NSError _nsError;
}

/// Object specifying creation parameters for a [WebKitNavigationDelegate].
@immutable
class WebKitNavigationDelegateCreationParams
    extends PlatformNavigationDelegateCreationParams {
  /// Constructs a [WebKitNavigationDelegateCreationParams].
  const WebKitNavigationDelegateCreationParams();

  /// Constructs a [WebKitNavigationDelegateCreationParams] using a
  /// [PlatformNavigationDelegateCreationParams].
  const WebKitNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
    // Recommended placeholder to prevent being broken by platform interface.
    // ignore: avoid_unused_constructor_parameters
    PlatformNavigationDelegateCreationParams params,
  );
}

/// An implementation of [PlatformNavigationDelegate] with the WebKit API.
class WebKitNavigationDelegate extends PlatformNavigationDelegate {
  /// Constructs a [WebKitNavigationDelegate].
  WebKitNavigationDelegate(PlatformNavigationDelegateCreationParams params)
    : super.implementation(
        params is WebKitNavigationDelegateCreationParams
            ? params
            : WebKitNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
                params,
              ),
      ) {
    final weakThis = WeakReference<WebKitNavigationDelegate>(this);
    _navigationDelegate = WKNavigationDelegate(
      didFinishNavigation: (_, __, String? url) {
        if (weakThis.target?._onPageFinished != null) {
          weakThis.target!._onPageFinished!(url ?? '');
        }
      },
      didStartProvisionalNavigation: (_, __, String? url) {
        final WebKitNavigationDelegate? delegate = weakThis.target;
        if (delegate != null) {
          for (final VoidCallback callback in List<VoidCallback>.of(
            _webKitNavigationStartCallbacks[delegate] ?? const <VoidCallback>{},
          )) {
            callback();
          }
        }
        if (weakThis.target?._onPageStarted != null) {
          weakThis.target!._onPageStarted!(url ?? '');
        }
      },
      decidePolicyForNavigationResponse:
          (_, __, WKNavigationResponse response) async {
            final URLResponse urlResponse = response.response;
            if (weakThis.target?._onHttpError != null &&
                urlResponse is HTTPURLResponse &&
                urlResponse.statusCode >= 400) {
              weakThis.target!._onHttpError!(
                HttpResponseError(
                  response: WebResourceResponse(
                    uri: null,
                    statusCode: urlResponse.statusCode,
                  ),
                ),
              );
            }

            return NavigationResponsePolicy.allow;
          },
      decidePolicyForNavigationAction:
          (_, __, WKNavigationAction action) async {
            if (weakThis.target?._onNavigationRequest != null) {
              final NavigationDecision decision =
                  await weakThis.target!._onNavigationRequest!(
                    NavigationRequest(
                      url: await action.request.getUrl() ?? '',
                      isMainFrame: action.targetFrame?.isMainFrame ?? false,
                    ),
                  );
              switch (decision) {
                case NavigationDecision.prevent:
                  return NavigationActionPolicy.cancel;
                case NavigationDecision.navigate:
                  return NavigationActionPolicy.allow;
              }
            }
            return NavigationActionPolicy.allow;
          },
      didFailNavigation: (_, __, NSError error) {
        if (weakThis.target?._onWebResourceError != null) {
          weakThis.target!._onWebResourceError!(
            WebKitWebResourceError._(
              error,
              isForMainFrame: true,
              url:
                  error.userInfo[NSErrorUserInfoKey
                          .NSURLErrorFailingURLStringError]
                      as String?,
            ),
          );
        }
      },
      didFailProvisionalNavigation: (_, __, NSError error) async {
        var url =
            error.userInfo[NSErrorUserInfoKey.NSURLErrorFailingURLStringError]
                as String?;

        // On iOS 26+, the error is stored with `NSURLErrorFailingURLErrorKey`.
        if (url == null) {
          final nativeURL =
              error.userInfo[NSErrorUserInfoKey.NSURLErrorFailingURLErrorKey]
                  as URL?;
          url = await nativeURL?.getAbsoluteString();
        }

        if (weakThis.target?._onWebResourceError != null) {
          weakThis.target!._onWebResourceError!(
            WebKitWebResourceError._(error, isForMainFrame: true, url: url),
          );
        }
      },
      webViewWebContentProcessDidTerminate: (_, __) {
        if (weakThis.target?._onWebResourceError != null) {
          weakThis.target!._onWebResourceError!(
            WebKitWebResourceError._(
              NSError.pigeon_detached(
                code: WKErrorCode.webContentProcessTerminated,
                // Value from https://developer.apple.com/documentation/webkit/wkerrordomain?language=objc.
                domain: 'WKErrorDomain',
                userInfo: const <String, Object?>{},
              ),
              isForMainFrame: true,
              url: null,
            ),
          );
        }
      },
      didReceiveAuthenticationChallenge:
          (_, __, URLAuthenticationChallenge challenge) async {
            final WebKitNavigationDelegate? delegate = weakThis.target;

            if (delegate != null) {
              final URLProtectionSpace protectionSpace = await challenge
                  .getProtectionSpace();

              switch (protectionSpace.authenticationMethod) {
                case NSUrlAuthenticationMethod.httpBasic:
                case NSUrlAuthenticationMethod.httpNtlm:
                  final void Function(HttpAuthRequest)? callback =
                      delegate._onHttpAuthRequest;
                  if (callback != null) {
                    return _handleHttpAuthRequest(
                      onHttpAuthRequest: callback,
                      protectionSpace: protectionSpace,
                    );
                  }
                case NSUrlAuthenticationMethod.serverTrust:
                  final void Function(PlatformSslAuthError)? callback =
                      delegate._onSslAuthError;
                  if (callback != null) {
                    final SecTrust? serverTrust = await protectionSpace
                        .getServerTrust();

                    if (serverTrust != null) {
                      try {
                        final bool trusted = await SecTrust.evaluateWithError(
                          serverTrust,
                        );
                        if (!trusted) {
                          throw StateError(
                            'Expected to throw an exception when evaluation fails.',
                          );
                        }
                      } on PlatformException catch (exception) {
                        final DartSecTrustResultType result =
                            (await SecTrust.getTrustResult(serverTrust)).result;

                        if (result ==
                            DartSecTrustResultType.recoverableTrustFailure) {
                          return _handleSslAuthError(
                            onSslAuthError: callback,
                            serverTrust: serverTrust,
                            protectionSpace: protectionSpace,
                            secTrustException: exception,
                          );
                        }
                      }
                    }
                  }
              }
            }

            return AuthenticationChallengeResponse.createAsync(
              UrlSessionAuthChallengeDisposition.performDefaultHandling,
              null,
            );
          },
    );
  }

  // Used to set `WKWebView.setNavigationDelegate` in `WebKitWebViewController`.
  late final WKNavigationDelegate _navigationDelegate;

  PageEventCallback? _onPageFinished;
  PageEventCallback? _onPageStarted;
  HttpResponseErrorCallback? _onHttpError;
  ProgressCallback? _onProgress;
  WebResourceErrorCallback? _onWebResourceError;
  NavigationRequestCallback? _onNavigationRequest;
  UrlChangeCallback? _onUrlChange;
  TitleChangeCallback? _onTitleChange;
  HttpAuthRequestCallback? _onHttpAuthRequest;
  SslAuthErrorCallback? _onSslAuthError;

  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {
    _onPageFinished = onPageFinished;
  }

  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {
    _onPageStarted = onPageStarted;
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
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback onNavigationRequest,
  ) async {
    _onNavigationRequest = onNavigationRequest;
  }

  @override
  Future<void> setOnTitleChange(TitleChangeCallback onTitleChange) async {
    _onTitleChange = onTitleChange;
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

  static Future<AuthenticationChallengeResponse> _handleHttpAuthRequest({
    required void Function(HttpAuthRequest) onHttpAuthRequest,
    required URLProtectionSpace protectionSpace,
  }) {
    final responseCompleter = Completer<AuthenticationChallengeResponse>();

    onHttpAuthRequest(
      HttpAuthRequest(
        host: protectionSpace.host,
        realm: protectionSpace.realm,
        onProceed: (WebViewCredential credential) async {
          responseCompleter.complete(
            await AuthenticationChallengeResponse.createAsync(
              UrlSessionAuthChallengeDisposition.useCredential,
              await URLCredential.withUserAsync(
                credential.user,
                credential.password,
                UrlCredentialPersistence.forSession,
              ),
            ),
          );
        },
        onCancel: () async {
          responseCompleter.complete(
            await AuthenticationChallengeResponse.createAsync(
              UrlSessionAuthChallengeDisposition.cancelAuthenticationChallenge,
              null,
            ),
          );
        },
      ),
    );

    return responseCompleter.future;
  }

  static Future<AuthenticationChallengeResponse> _handleSslAuthError({
    required void Function(PlatformSslAuthError) onSslAuthError,
    required SecTrust serverTrust,
    required URLProtectionSpace protectionSpace,
    required PlatformException secTrustException,
  }) async {
    final responseCompleter = Completer<AuthenticationChallengeResponse>();

    final List<SecCertificate> certificates =
        (await SecTrust.copyCertificateChain(serverTrust)) ??
        <SecCertificate>[];

    final SecCertificate? leafCertificate = certificates.firstOrNull;
    onSslAuthError(
      WebKitSslAuthError(
        certificate: leafCertificate != null
            ? X509Certificate(
                data: await SecCertificate.copyData(leafCertificate),
              )
            : null,
        description: '${secTrustException.code}: ${secTrustException.message}',
        trust: serverTrust,
        host: protectionSpace.host,
        port: protectionSpace.port,
        onResponse:
            (
              UrlSessionAuthChallengeDisposition disposition,
              URLCredential? credential,
            ) async {
              responseCompleter.complete(
                await AuthenticationChallengeResponse.createAsync(
                  disposition,
                  credential,
                ),
              );
            },
      ),
    );

    return responseCompleter.future;
  }
}

/// WebKit implementation of [PlatformWebViewPermissionRequest].
class WebKitWebViewPermissionRequest extends PlatformWebViewPermissionRequest {
  const WebKitWebViewPermissionRequest._({
    required super.types,
    required void Function(PermissionDecision decision) onDecision,
  }) : _onDecision = onDecision;

  final void Function(PermissionDecision) _onDecision;

  @override
  Future<void> grant() async {
    _onDecision(PermissionDecision.grant);
  }

  @override
  Future<void> deny() async {
    _onDecision(PermissionDecision.deny);
  }

  /// Prompt the user for permission for the requested resource.
  Future<void> prompt() async {
    _onDecision(PermissionDecision.prompt);
  }
}

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'platform_webview_controller.dart';
import 'types/types.dart';
import 'webview_resource_bridge.dart';

/// Common validation and bounded transport for native network adapters.
mixin WebViewNetworkControllerMixin on PlatformWebViewController {
  Future<bool> configureContentRules(List<Map<String, Object?>> rules) async =>
      false;
  Future<bool> configureNetworkBridge(
    Map<String, Object?> configuration,
  ) async => false;
  bool get nativeNetworkBodies => false;
  final Set<WebViewResourceBridge> _networkBridges = {};
  @protected
  WebViewResourceBridge? networkBridgeForChannel(String name) {
    for (final bridge in _networkBridges) {
      if (bridge.channelName == name) return bridge;
    }
    return null;
  }

  WebViewResourceBridge? _requestsBridge, _schemesBridge;
  bool _networkClosed = false;
  Future<bool> _networkUpdates = Future.value(true);
  late final Set<String> declaredCustomSchemes = Set.unmodifiable(
    params.customSchemes,
  );

  Future<bool> _updateNetwork(Future<bool> Function() update) {
    final next = _networkUpdates.then((_) async {
      if (_networkClosed) return false;
      try {
        return await update();
      } catch (error) {
        debugPrint(
          'webview_all: configuring native network control failed: $error',
        );
        return false;
      }
    });
    _networkUpdates = next;
    return next;
  }

  @override
  Future<bool> setContentRules(List<WebViewContentRule> rules) {
    final copy = List<WebViewContentRule>.unmodifiable(rules);
    return _updateNetwork(() async {
      final caps = await getNetworkCapabilities();
      if (!caps.contentRules ||
          copy.length > 256 ||
          copy.any(
            (r) =>
                !r.isValid ||
                !caps.resourceTypes.containsAll(r.resourceTypes) ||
                !caps.ruleActions.contains(r.action) ||
                !caps.ruleConditions.containsAll(r.conditions),
          )) {
        debugPrint(
          'webview_all: the content-rule set is unsupported or invalid. Use up to 256 ASCII URL patterns (1–2048 characters); conditions, actions and resource-type filtering require native support. Existing rules were retained.',
        );
        return false;
      }
      final accepted = await configureContentRules(
        copy.map((r) => r.toMap()).toList(),
      );
      if (!accepted) {
        debugPrint(
          'webview_all: the native rule compiler rejected this content-rule set. Existing rules were retained.',
        );
      }
      return accepted;
    });
  }

  @override
  Future<bool> setRequestDelegate(
    WebViewRequestDelegate? delegate,
  ) => _updateNetwork(() async {
    final caps = await getNetworkCapabilities();
    if (!caps.httpInterception) return super.setRequestDelegate(delegate);
    if (delegate != null &&
        (delegate.urlPatterns.isEmpty ||
            delegate.urlPatterns.length > 256 ||
            delegate.urlPatterns.any((v) => !isValidWebViewUrlPattern(v)))) {
      debugPrint(
        'webview_all: request interception needs 1–256 valid ASCII URL patterns. Existing interception was retained.',
      );
      return false;
    }
    final patterns = delegate?.urlPatterns ?? const <String>[];
    return _replaceBridge(
      'http',
      delegate == null
          ? null
          : WebViewResourceDelegate(
              onRequest: (request) async {
                final decision = await delegate.onRequest(request);
                switch (decision.kind) {
                  case WebViewRequestDecisionKind.allow:
                    return WebViewPassThroughResponse();
                  case WebViewRequestDecisionKind.block:
                    return WebViewResourceResponse.bytes(
                      Uint8List(0),
                      mimeType: 'text/plain',
                      statusCode: 403,
                    );
                  case WebViewRequestDecisionKind.respond:
                    return decision.response;
                }
              },
            ),
      (uri) =>
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          patterns.any(
            (v) => webViewUrlPatternMatches(
              v,
              uri.toString(),
              caseSensitive: delegate?.caseSensitive ?? false,
            ),
          ),
      {
        'urlPatterns': patterns,
        'caseSensitive': delegate?.caseSensitive ?? false,
      },
      caps,
    );
  });

  @override
  Future<bool> setCustomSchemeDelegate(
    WebViewResourceDelegate? delegate,
  ) => _updateNetwork(() async {
    final caps = await getNetworkCapabilities();
    if (!caps.customSchemes) return super.setCustomSchemeDelegate(delegate);
    if (declaredCustomSchemes.isEmpty ||
        declaredCustomSchemes.length > 16 ||
        declaredCustomSchemes.any((v) => !isValidCustomWebViewScheme(v))) {
      debugPrint(
        'webview_all: declare 1–16 non-engine schemes in creation parameters before setting a scheme delegate. Existing handlers were retained.',
      );
      return false;
    }
    return _replaceBridge(
      'schemes',
      delegate,
      (uri) => declaredCustomSchemes.contains(uri.scheme),
      {'schemes': declaredCustomSchemes.toList()},
      caps,
    );
  });

  Future<bool> _replaceBridge(
    String kind,
    WebViewResourceDelegate? delegate,
    bool Function(Uri) filter,
    Map<String, Object?> selectors,
    WebViewNetworkCapabilities caps,
  ) async {
    final previous = kind == 'http' ? _requestsBridge : _schemesBridge;
    final weak = WeakReference<WebViewNetworkControllerMixin>(this);
    late WebViewResourceBridge bridge;
    bridge = WebViewResourceBridge(
      scheme: 'webview-all-request',
      supportsStreaming: caps.streamingResponses,
      nativeBodies: nativeNetworkBodies,
      uriFilter: filter,
      allowAnyMethod: true,
      allowPassThrough: kind == 'http',
      configure: (channel, host, enabled) async {
        final owner = weak.target;
        if (owner == null) return;
        final accepted = await owner.configureNetworkBridge({
          'kind': kind,
          'channel': channel,
          'enabled': enabled,
          ...selectors,
        });
        if (!accepted && enabled) {
          throw UnsupportedError('The engine rejected the request handler.');
        }
      },
    );
    _networkBridges.add(bridge);
    try {
      await bridge.update(delegate);
      if (_networkClosed) {
        await bridge.close();
        return false;
      }
      if (kind == 'http') {
        _requestsBridge = bridge;
      } else {
        _schemesBridge = bridge;
      }
      await previous?.close();
      if (previous != null) _networkBridges.remove(previous);
      return true;
    } catch (_) {
      await bridge.close();
      _networkBridges.remove(bridge);
      rethrow;
    }
  }

  Future<void>? disposeNetworkBridges() {
    if (_networkClosed) return null;
    _networkClosed = true;
    if (_networkBridges.isEmpty) return null;
    final bridges = _networkBridges.toList();
    _networkBridges.clear();
    return Future.wait(bridges.map((v) => v.close())).then<void>((_) {});
  }
}

bool isValidCustomWebViewScheme(String name) =>
    RegExp(r'^[a-z][a-z0-9+.-]{0,31}$').hasMatch(name) &&
    !const {
      'http',
      'https',
      'file',
      'data',
      'about',
      'javascript',
      'blob',
      'ws',
      'wss',
      'ftp',
      'mailto',
      'tel',
      'intent',
      'content',
      'android',
      'resource',
      'chrome',
      'edge',
      'webview-all-resource',
    }.contains(name);

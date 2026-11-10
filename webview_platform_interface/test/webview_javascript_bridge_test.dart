import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'helpers/garbage_collection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('origin policies reject unknown, opaque, wildcard and path origins', () {
    final policy = WebViewJavaScriptAccessPolicy.origins({
      'https://example.com',
    });
    expect(
      policy.allows(origin: 'https://example.com', isMainFrame: true),
      isTrue,
    );
    for (final origin in [
      null,
      'null',
      'https://other.com',
      'https://example.com:8443',
    ]) {
      expect(policy.allows(origin: origin, isMainFrame: true), isFalse);
    }
    expect(
      policy.allows(origin: 'https://example.com', isMainFrame: null),
      isFalse,
    );
    expect(
      policy.allows(origin: 'https://example.com', isMainFrame: false),
      isFalse,
    );
    for (final origin in [
      '*',
      'https://*.example.com',
      'https://example.com/path',
      'file:///',
      'https://example.com?',
    ]) {
      expect(
        () => WebViewJavaScriptAccessPolicy.origins({origin}),
        throwsArgumentError,
      );
    }
  });

  test(
    'unsupported policies warn and skip without installing a channel',
    () async {
      final view = _Controller(trustedOrigins: false);
      expect(
        await view.addJavaScriptHandler(
          _params(
            (_) => 1,
            policy: WebViewJavaScriptAccessPolicy.origins({
              'https://example.com',
            }),
          ),
        ),
        isFalse,
      );
      expect(view.channels, isEmpty);
      expect(await view.addJavaScriptHandler(_params((_) => 1)), isTrue);
      view.close();
    },
  );

  test(
    'structured arguments and asynchronous results use the original document',
    () async {
      final view = _Controller();
      await view.addJavaScriptHandler(
        _params((call) async {
          expect(call.sourceOrigin, 'https://example.com');
          expect(call.sourceUrl, 'https://example.com/current');
          expect(call.arguments, [
            {
              'nested': [1, true, null],
            },
          ]);
          expect(
            () => (call.arguments.single as Map)['new'] = 1,
            throwsUnsupportedError,
          );
          return {'ok': true, 'values': call.arguments};
        }),
      );
      await view.hello();
      view.call(
        '1',
        arguments: [
          {
            'nested': [1, true, null],
          },
        ],
      );
      final response = await view.response('1');
      expect(response['type'], 'result');
      expect(response['value'], {
        'ok': true,
        'values': [
          {
            'nested': [1, true, null],
          },
        ],
      });
      view.close();
    },
  );

  test(
    'native caller metadata enforces origin and main-frame restrictions',
    () async {
      final view = _Controller();
      var called = false;
      await view.addJavaScriptHandler(
        _params(
          (_) {
            called = true;
            return null;
          },
          policy: WebViewJavaScriptAccessPolicy.origins({
            'https://example.com',
          }),
        ),
      );
      await view.hello();
      view.call('1', origin: null);
      expect((await view.response('1'))['code'], 'forbidden');
      view.call('2', origin: 'null');
      expect((await view.response('2'))['code'], 'forbidden');
      expect(called, isFalse);
      view.close();
    },
  );

  test(
    'handler errors, timeout and non-JSON results reject predictably',
    () async {
      final view = _Controller();
      await view.addJavaScriptHandler(
        _params((_) => throw StateError('private details')),
      );
      await view.hello();
      view.call('1');
      final error = await view.response('1');
      expect(error['code'], 'handler_error');
      expect(jsonEncode(error), isNot(contains('private details')));
      await view.addJavaScriptHandler(_params((_) => double.nan));
      view.call('2');
      expect((await view.response('2'))['code'], 'serialization_error');
      await view.addJavaScriptHandler(
        _params(
          (_) => Completer<Object?>().future,
          timeout: const Duration(milliseconds: 10),
        ),
      );
      view.call('3');
      expect((await view.response('3'))['code'], 'timeout');
      view.close();
    },
  );

  test(
    'navigation cancels pending callbacks and discards late results',
    () async {
      final view = _Controller();
      final result = Completer<Object?>();
      final started = Completer<WebViewJavaScriptCall>();
      await view.addJavaScriptHandler(
        _params((call) {
          started.complete(call);
          return result.future;
        }),
      );
      await view.hello();
      view.call('1');
      final call = await started.future;
      view.navigate();
      await call.cancelled;
      await view.hello(document: 'new-document');
      result.complete('old secret');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        view.replies.where(
          (reply) => reply['id'] == '1' && reply['type'] == 'result',
        ),
        isEmpty,
      );
      view.close();
    },
  );

  test(
    'a failed navigation leaves the current document able to call again',
    () async {
      final view = _Controller();
      await view.addJavaScriptHandler(_params((call) => call.arguments.single));
      await view.hello();
      view.navigate();
      // A provisional load can fail without replacing the original Document.
      view.call('still-current', arguments: ['kept']);
      expect((await view.response('still-current'))['value'], 'kept');
      view.close();
    },
  );

  test('closing during capability lookup does not install a bridge', () async {
    final capabilitiesReady = Completer<void>();
    final view = _Controller(capabilitiesReady: capabilitiesReady.future);
    final registration = view.addJavaScriptHandler(_params((_) => null));
    await Future<void>.delayed(Duration.zero);
    view.close();
    capabilitiesReady.complete();
    expect(await registration, isFalse);
    expect(view.channels, isEmpty);
    expect(view.scripts, isEmpty);
  });

  test('a closed controller rejects its first handler registration', () async {
    final view = _Controller()..close();
    expect(await view.addJavaScriptHandler(_params((_) => null)), isFalse);
    expect(view.channels, isEmpty);
  });

  for (final stage in ['channel', 'script']) {
    test(
      'closing during $stage installation cleans up partial registration',
      () async {
        final installed = Completer<void>();
        final view = _Controller(
          channelReady: stage == 'channel' ? installed.future : null,
          scriptReady: stage == 'script' ? installed.future : null,
        );
        final registration = view.addJavaScriptHandler(_params((_) => null));
        await Future<void>.delayed(Duration.zero);
        view.close();
        installed.complete();
        expect(await registration, isFalse);
        expect(view.channels, isEmpty);
        expect(view.scripts, isEmpty);
      },
    );
  }

  test(
    'removal rejects pending calls and preserves the internal script',
    () async {
      final view = _Controller();
      final started = Completer<void>();
      await view.addJavaScriptHandler(
        _params((_) {
          started.complete();
          return Completer<Object?>().future;
        }),
      );
      await view.hello();
      view.call('1');
      await started.future;
      await view.removeJavaScriptHandler('echo');
      expect((await view.response('1'))['code'], 'aborted');
      await view.addUserScript(
        const WebViewUserScript(source: 'userScript();'),
      );
      await view.removeAllUserScripts();
      expect(view.scripts.length, 1);
      expect(view.scripts.single.source, contains('callHandler'));
      view.call('2');
      expect((await view.response('2'))['code'], 'handler_not_found');
      view.close();
    },
  );

  test('same handler names in different worlds remain independent', () async {
    final view = _Controller();
    await view.addJavaScriptHandler(_params((_) => 'page'));
    await view.addJavaScriptHandler(
      WebViewJavaScriptHandlerParams(
        name: 'echo',
        onCall: (_) => 'isolated',
        accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
        world: const WebViewJavaScriptWorld.isolated('app'),
      ),
    );
    expect(view.channels.length, 2);
    expect(view.scripts.map((script) => script.world).toSet().length, 2);
    view.close();
  });

  test('native callbacks do not retain a released handler owner', () async {
    final nativeChannels = <JavaScriptChannelParams>[];
    final weak = await _registerHandlerOwner(nativeChannels);
    if (!await forceGarbageCollection()) {
      markTestSkipped('Run with --enable-vmservice to verify collection.');
      return;
    }
    expect(nativeChannels, isNotEmpty);
    expect(weak.target, isNull);
  });
}

class _HandlerOwner {
  final view = _Controller();
  int calls = 0;
  Object? onCall(WebViewJavaScriptCall call) => ++calls;
}

@pragma('vm:never-inline')
Future<WeakReference<_HandlerOwner>> _registerHandlerOwner(
  List<JavaScriptChannelParams> nativeChannels,
) async {
  final owner = _HandlerOwner();
  await owner.view.addJavaScriptHandler(_params(owner.onCall));
  nativeChannels.addAll(owner.view.channels.values);
  return WeakReference(owner);
}

WebViewJavaScriptHandlerParams _params(
  WebViewJavaScriptHandler callback, {
  WebViewJavaScriptAccessPolicy policy =
      const WebViewJavaScriptAccessPolicy.unrestricted(),
  Duration timeout = const Duration(seconds: 1),
}) => WebViewJavaScriptHandlerParams(
  name: 'echo',
  onCall: callback,
  accessPolicy: policy,
  timeout: timeout,
);

class _Controller extends PlatformWebViewController {
  _Controller({
    this.trustedOrigins = true,
    this.capabilitiesReady,
    this.channelReady,
    this.scriptReady,
  }) : super.implementation(const PlatformWebViewControllerCreationParams());
  final bool trustedOrigins;
  final Future<void>? capabilitiesReady;
  final Future<void>? channelReady;
  final Future<void>? scriptReady;
  final Map<String, JavaScriptChannelParams> channels = {};
  final Map<String, WebViewUserScript> _scripts = {};
  final List<Map<String, dynamic>> replies = [];
  List<WebViewUserScript> get scripts => _scripts.values.toList();

  @override
  Future<WebViewJavaScriptCapabilities> getJavaScriptCapabilities({
    WebViewJavaScriptWorld world = WebViewJavaScriptWorld.page,
  }) async {
    await capabilitiesReady;
    return WebViewJavaScriptCapabilities(
      supportsPromiseHandlers: true,
      supportsIsolatedWorlds: true,
      supportsTrustedOrigins: trustedOrigins,
      supportsTrustedFrameInformation: true,
    );
  }

  @override
  Future<void> addJavaScriptChannelInWorld(
    JavaScriptChannelParams params,
    WebViewJavaScriptWorld world,
  ) async {
    channels[params.name] = params;
    await channelReady;
  }

  @override
  Future<void> removeJavaScriptChannel(String name) async {
    channels.remove(name);
  }

  @override
  Future<String> addUserScript(WebViewUserScript script) async {
    final id = '${_scripts.length}';
    _scripts[id] = script;
    await scriptReady;
    return id;
  }

  @override
  Future<void> removeUserScript(String identifier) async {
    _scripts.remove(identifier);
  }

  @override
  Future<void> removeAllUserScripts() async {
    _scripts.removeWhere((id, _) => !isJavaScriptBridgeScript(id));
  }

  @override
  Future<void> runJavaScriptInWorld(
    String source,
    WebViewJavaScriptWorld world,
  ) async {
    const marker = ', JSON.parse(';
    final start = source.indexOf(marker);
    final encoded =
        jsonDecode(source.substring(start + marker.length, source.length - 3))
            as String;
    replies.add(jsonDecode(encoded) as Map<String, dynamic>);
  }

  Future<void> hello({String document = 'document'}) async {
    _document = document;
    _emit({'v': 1, 'type': 'hello', 'document': document});
    await Future<void>.delayed(Duration.zero);
  }

  String _document = 'document';
  void call(
    String id, {
    List<Object?> arguments = const [],
    String? origin = 'https://example.com',
  }) => _emit({
    'v': 1,
    'type': 'call',
    'document': _document,
    'name': 'echo',
    'id': id,
    'arguments': arguments,
  }, origin: origin);

  void _emit(
    Map<String, Object?> message, {
    String? origin = 'https://example.com',
  }) => channels.values.first.onMessageReceived(
    JavaScriptMessage(
      message: jsonEncode(message),
      sourceOrigin: origin,
      sourceUrl: 'https://example.com/current',
      isMainFrame: true,
    ),
  );

  Future<Map<String, dynamic>> response(String id) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 2)) {
      for (final reply in replies) {
        if (reply['id'] == id) return reply;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw StateError('No response for $id.');
  }

  void navigate() => cancelJavaScriptHandlerCalls();
  void close() => disposeJavaScriptHandlers();
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scripts and Promise handlers preserve worlds and document lifetimes', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          request.uri.path == '/child'
              ? '<!doctype html><body>child</body>'
              : '''
<!doctype html><html><head><script>
globalThis.firstCall = (async () => {
  if (!globalThis.webviewAll) throw new Error('The first document script cannot see the bridge.');
  await webviewAll.ready;
  return await webviewAll.callHandler('echo', {nested: [1, true, null]});
})();
globalThis.firstCall.catch(() => {});
globalThis.allowedCall = (async () => {
  await webviewAll.ready;
  try { return await webviewAll.callHandler('allowed', 'trusted'); }
  catch (error) { return error.code; }
})();
window.addEventListener('load', () => { globalThis.endBeforeLoad = globalThis.endRan === true; });
</script></head><body><div id="target">ready</div><iframe src="/child"></iframe></body></html>
''',
        );
        await request.response.close();
      }),
    );
    final uri = Uri.parse('http://127.0.0.1:${server.port}/');
    final controller = WebViewController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.platform.closeWebViewSession();
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: controller)),
      ),
    );
    await tester.pump();
    var loaded = Completer<void>();
    final prevented = Completer<void>();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (Uri.parse(request.url).path == '/blocked') {
            if (!prevented.isCompleted) prevented.complete();
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    Future<void> load() async {
      loaded = Completer<void>();
      await controller.loadRequest(uri);
      await loaded.future.timeout(const Duration(seconds: 20));
    }

    final caps = await controller.getJavaScriptCapabilities();
    debugPrint(
      'JavaScript capabilities: isolated=${caps.supportsIsolatedWorlds}, '
      'promise=${caps.supportsPromiseHandlers}, '
      'origins=${caps.supportsTrustedOrigins}, '
      'frames=${caps.supportsTrustedFrameInformation}, '
      'emulatedEnd=${caps.documentEndIsEmulated}',
    );
    if (const bool.fromEnvironment('WEBVIEW_ALL_REQUIRE_ISOLATED_WORLDS')) {
      expect(
        caps.supportsIsolatedWorlds,
        isTrue,
        reason: 'This run must exercise native isolated worlds.',
      );
      expect(caps.supportsPromiseHandlers, isTrue);
    }
    if (!caps.supportsPromiseHandlers) {
      expect(
        await controller.addJavaScriptHandler(
          'echo',
          onCall: (_) => null,
          accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
        ),
        isFalse,
      );
      return;
    }
    expect(
      await controller.addJavaScriptHandler(
        'echo',
        onCall: (call) async => call.arguments.single,
        accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
      ),
      isTrue,
    );
    expect(
      await controller.tryAddUserScript(
        const WebViewUserScript(source: 'globalThis.startRan = true;'),
      ),
      isNotNull,
    );
    expect(
      await controller.tryAddUserScript(
        const WebViewUserScript(
          source:
              'globalThis.endRan = document.getElementById("target") !== null;',
          injectionTime: WebViewUserScriptInjectionTime.documentEnd,
        ),
      ),
      isNotNull,
    );

    final allowed = await controller.addJavaScriptHandler(
      'allowed',
      onCall: (call) => call.arguments.single,
      accessPolicy: WebViewJavaScriptAccessPolicy.origins({uri.origin}),
    );
    expect(
      allowed,
      caps.supportsTrustedOrigins && caps.supportsTrustedFrameInformation,
    );

    const isolated = WebViewJavaScriptWorld.isolated('integration');
    WebViewJavaScriptCall? isolatedCall;
    if (caps.supportsIsolatedWorlds) {
      expect(
        await controller.addJavaScriptHandler(
          'echo',
          onCall: (call) {
            isolatedCall = call;
            return {'isolated': call.arguments};
          },
          accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
          world: isolated,
        ),
        isTrue,
      );
      expect(
        await controller.tryAddUserScript(
          const WebViewUserScript(
            source: 'globalThis.isolatedValue = 42;',
            world: isolated,
          ),
        ),
        isNotNull,
      );
      expect(
        await controller.tryAddUserScript(
          const WebViewUserScript(
            source:
                'globalThis.isolatedEndRan = document.getElementById("target") !== null;',
            injectionTime: WebViewUserScriptInjectionTime.documentEnd,
            world: isolated,
          ),
        ),
        isNotNull,
      );
    } else {
      expect(
        await controller.tryAddUserScript(
          const WebViewUserScript(
            source: 'throw new Error("must not execute");',
            world: isolated,
          ),
        ),
        isNull,
      );
      expect(
        await controller.callAsyncJavaScript('return 42;', world: isolated),
        isNull,
      );
    }
    await load();
    expect(
      await controller.callAsyncJavaScript(
        'return await globalThis.allowedCall;',
      ),
      allowed ? 'trusted' : 'handler_not_found',
    );
    expect(
      await controller.callAsyncJavaScript(
        'return await globalThis.firstCall;',
      ),
      {
        'nested': [1, true, null],
      },
    );
    expect(
      await controller.callAsyncJavaScript(
        'return {start: globalThis.startRan, end: globalThis.endRan, beforeLoad: globalThis.endBeforeLoad};',
      ),
      {'start': true, 'end': true, 'beforeLoad': true},
    );
    expect(
      await controller.callAsyncJavaScript(
        'return typeof document.querySelector("iframe").contentWindow.webviewAll;',
      ),
      'undefined',
    );
    if (caps.supportsIsolatedWorlds) {
      expect(
        await controller.callAsyncJavaScript(
          'return typeof globalThis.isolatedValue;',
        ),
        'undefined',
      );
      expect(
        await controller.callAsyncJavaScript(
          'return {value: globalThis.isolatedValue, end: globalThis.isolatedEndRan, body: !!document.getElementById("target")};',
          world: isolated,
        ),
        {'value': 42, 'end': true, 'body': true},
      );
      expect(
        await controller.callAsyncJavaScript(
          'await webviewAll.ready; return await webviewAll.callHandler("echo", "world");',
          world: isolated,
        ),
        {
          'isolated': ['world'],
        },
      );
      expect(isolatedCall?.world, isolated);
      final worldCaps = await controller.getJavaScriptCapabilities(
        world: isolated,
      );
      if (worldCaps.supportsTrustedOrigins) {
        expect(isolatedCall?.sourceOrigin, uri.origin);
      }
      if (worldCaps.supportsTrustedFrameInformation) {
        expect(isolatedCall?.isMainFrame, isTrue);
      }
    }

    final strict = await controller.addJavaScriptHandler(
      'restricted',
      onCall: (_) => 'must not run',
      accessPolicy: WebViewJavaScriptAccessPolicy.origins({
        'https://different.invalid',
      }),
    );
    expect(
      strict,
      caps.supportsTrustedOrigins && caps.supportsTrustedFrameInformation,
    );
    if (strict) {
      expect(
        await controller.callAsyncJavaScript(
          'try { await webviewAll.callHandler("restricted"); } catch (e) { return e.code; }',
        ),
        'forbidden',
      );
    }
    expect(
      await controller.addJavaScriptHandler(
        'failure',
        onCall: (_) => throw StateError('private details'),
        accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
      ),
      isTrue,
    );
    expect(
      await controller.callAsyncJavaScript(
        'try { await webviewAll.callHandler("failure"); } catch (e) { return {code: e.code, private: e.message.includes("private details")}; }',
      ),
      {'code': 'handler_error', 'private': false},
    );

    var started = Completer<WebViewJavaScriptCall>();
    var pending = Completer<Object?>();
    await controller.addJavaScriptHandler(
      'wait',
      onCall: (call) {
        started.complete(call);
        return pending.future;
      },
      accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
    );
    await controller.runJavaScript(
      'globalThis.waitResult = webviewAll.callHandler("wait"); globalThis.waitResult.catch(() => {});',
    );
    await started.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript(
      'location.href = "${uri.resolve('/blocked')}";',
    );
    await prevented.future.timeout(const Duration(seconds: 10));
    await controller.runJavaScript('history.pushState({}, "", "/spa");');
    pending.complete({'afterSpa': true});
    expect(
      await controller.callAsyncJavaScript(
        'return await globalThis.waitResult;',
      ),
      {'afterSpa': true},
    );

    started = Completer<WebViewJavaScriptCall>();
    pending = Completer<Object?>();
    await controller.runJavaScript(
      'globalThis.waitResult = webviewAll.callHandler("wait"); globalThis.waitResult.catch(() => {});',
    );
    final oldCall = await started.future.timeout(const Duration(seconds: 10));
    await load();
    await oldCall.cancelled.timeout(const Duration(seconds: 5));
    pending.complete('old document result');
    if (caps.supportsIsolatedWorlds) {
      expect(
        await controller.callAsyncJavaScript(
          'await webviewAll.ready; return {value: globalThis.isolatedValue, end: globalThis.isolatedEndRan, reply: await webviewAll.callHandler("echo", "after reload")};',
          world: isolated,
        ),
        {
          'value': 42,
          'end': true,
          'reply': {
            'isolated': ['after reload'],
          },
        },
      );
    }
    expect(
      await controller.callAsyncJavaScript(
        'return await globalThis.firstCall;',
      ),
      {
        'nested': [1, true, null],
      },
    );

    await controller.removeAllUserScripts();
    await load();
    if (caps.supportsIsolatedWorlds) {
      expect(
        await controller.callAsyncJavaScript(
          'return {value: typeof globalThis.isolatedValue, end: typeof globalThis.isolatedEndRan};',
          world: isolated,
        ),
        {'value': 'undefined', 'end': 'undefined'},
      );
    }
    expect(
      await controller.callAsyncJavaScript(
        'return typeof globalThis.startRan;',
      ),
      'undefined',
    );
    expect(
      await controller.callAsyncJavaScript(
        'return await globalThis.firstCall;',
      ),
      {
        'nested': [1, true, null],
      },
    );
    await controller.removeAllJavaScriptHandlers();
    if (caps.supportsIsolatedWorlds) {
      expect(
        await controller.callAsyncJavaScript(
          'try { await webviewAll.callHandler("echo", 1); } catch (e) { return e.code; }',
          world: isolated,
        ),
        'handler_not_found',
      );
    }
    expect(
      await controller.callAsyncJavaScript(
        'try { await webviewAll.callHandler("echo", 1); } catch (e) { return e.code; }',
      ),
      'handler_not_found',
    );
  });
}

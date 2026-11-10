@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:web/web.dart' as web;
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'web_webview_controller_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stopping a pending navigation policy keeps the current document',
    () async {
      final params = WebWebViewControllerCreationParams();
      final controller = WebWebViewController(params);
      addTearDown(controller.closeWebViewSession);
      await controller.loadHtmlString('<p>original document</p>');
      final before = params.iFrame.srcdoc;
      final started = Completer<void>();
      final decision = Completer<NavigationDecision>();
      final delegate = WebNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      await delegate.setOnNavigationRequest((request) {
        started.complete();
        return decision.future;
      });
      await controller.setPlatformNavigationDelegate(delegate);
      final loading = controller.loadRequest(
        LoadRequestParams(uri: Uri.parse('https://example.test/held')),
      );
      await started.future;
      await controller.stopLoading();
      await loading.timeout(const Duration(seconds: 1));
      decision.complete(NavigationDecision.navigate);
      await Future<void>.delayed(Duration.zero);
      expect(params.iFrame.srcdoc, before);
      expect((await controller.getNavigationHistory()).items, hasLength(1));
    },
  );

  test(
    'stopping fetch cancels transport and ignores a late response',
    () async {
      final factory = MockHttpRequestFactory();
      final response = Completer<web.Response>();
      final requested = Completer<web.AbortSignal>();
      when(
        factory.request(
          any,
          method: anyNamed('method'),
          requestHeaders: anyNamed('requestHeaders'),
          sendData: anyNamed('sendData'),
          abortSignal: anyNamed('abortSignal'),
        ),
      ).thenAnswer((invocation) {
        requested.complete(
          invocation.namedArguments[#abortSignal] as web.AbortSignal,
        );
        return response.future;
      });
      final params = WebWebViewControllerCreationParams(
        httpRequestFactory: factory,
      );
      final controller = WebWebViewController(params);
      addTearDown(controller.closeWebViewSession);
      await controller.loadHtmlString('<p>original document</p>');
      final before = params.iFrame.srcdoc;
      final loading = controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/pending'),
          method: LoadRequestMethod.post,
        ),
      );
      final signal = await requested.future.timeout(const Duration(seconds: 2));
      await controller.stopLoading();
      expect(signal.aborted, isTrue);
      response.complete(web.Response('<p>late document</p>'.toJS));
      await loading;
      expect(params.iFrame.srcdoc, before);
      expect((await controller.getNavigationHistory()).items, hasLength(1));
    },
  );

  test(
    'controlled HTML exposes native text search and logical history',
    () async {
      final params = WebWebViewControllerCreationParams();
      final controller = WebWebViewController(params);
      web.document.body!.append(params.iFrame);
      addTearDown(() async {
        await controller.closeWebViewSession();
        params.iFrame.remove();
      });
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      final loaded = Completer<void>();
      final delegate = WebNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      await delegate.setOnPageFinished((_) {
        if (!loaded.isCompleted) loaded.complete();
      });
      await controller.setPlatformNavigationDelegate(delegate);
      await controller.loadHtmlString(
        '<p>search needle</p><p>search needle</p>',
      );
      await loaded.future.timeout(const Duration(seconds: 10));
      final caps = await controller.getBrowserCapabilities();
      expect(caps.historyIsEmulated, isTrue);
      expect(caps.findText, isTrue);
      expect((await controller.findText('search needle'))?.matchFound, isTrue);
      expect((await controller.findText('absent 81379'))?.matchFound, isFalse);
      expect(
        (await controller.findText(
          'SEARCH NEEDLE',
          caseSensitive: true,
        ))?.matchFound,
        isFalse,
      );
      await controller.clearFindMatches();
      expect((await controller.getNavigationHistory()).currentIndex, 0);
    },
  );

  test('same-origin text search works without eval permission', () async {
    final params = WebWebViewControllerCreationParams(
      iFrameSandbox: 'allow-scripts allow-same-origin',
    );
    final controller = WebWebViewController(params);
    web.document.body!.append(params.iFrame);
    addTearDown(() async {
      await controller.closeWebViewSession();
      params.iFrame.remove();
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final loaded = Completer<void>();
    final delegate = WebNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    await delegate.setOnPageFinished((_) {
      if (!loaded.isCompleted) loaded.complete();
    });
    await controller.setPlatformNavigationDelegate(delegate);
    await controller.loadHtmlString(
      '''<meta http-equiv="Content-Security-Policy" content="script-src 'none'"><p>search needle</p>''',
    );
    await loaded.future.timeout(const Duration(seconds: 10));
    expect((await controller.getBrowserCapabilities()).findText, isTrue);
    expect((await controller.findText('search needle'))?.matchFound, isTrue);
    await controller.clearFindMatches();
  });

  test(
    'controlled HTML supports document-end scripts and Promise replies after reload',
    () async {
      final factory = MockHttpRequestFactory();
      final params = WebWebViewControllerCreationParams(
        httpRequestFactory: factory,
      );
      final controller = WebWebViewController(params);
      web.document.body!.append(params.iFrame);
      addTearDown(() async {
        await controller.closeWebViewSession();
        params.iFrame.remove();
      });
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      var loaded = Completer<void>();
      final delegate = WebNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      await delegate.setOnPageFinished((_) {
        if (!loaded.isCompleted) loaded.complete();
      });
      await controller.setPlatformNavigationDelegate(delegate);
      expect(
        await controller.addJavaScriptHandler(
          WebViewJavaScriptHandlerParams(
            name: 'echo',
            onCall: (call) async => call.arguments.single,
            accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
          ),
        ),
        isTrue,
      );
      await controller.addJavaScriptHandler(
        WebViewJavaScriptHandlerParams(
          name: 'strict',
          onCall: (_) => throw StateError('must not run'),
          accessPolicy: WebViewJavaScriptAccessPolicy.origins({
            'https://example.com',
          }),
        ),
      );
      await controller.addUserScript(
        const WebViewUserScript(
          source: '''
          globalThis.endRan = !!document.getElementById("target");
          globalThis.literalClosingTag = '</ScRiPt>';
          globalThis.comparison = 0</script/.test('script');
        ''',
          injectionTime: WebViewUserScriptInjectionTime.documentEnd,
        ),
      );
      await controller.loadHtmlString('''<!doctype html><html><head><script>
globalThis.firstReply = (async () => { await webviewAll.ready; return await webviewAll.callHandler('echo', {ok: [1, true, null]}); })();
firstReply.catch(() => {});
window.addEventListener('load', () => { globalThis.endBeforeLoad = globalThis.endRan === true; });
</script></head><body><div id="target">ready</div></body></html>''');

      await loaded.future.timeout(const Duration(seconds: 10));

      Future<Object?> evaluate(String source) => controller.callAsyncJavaScript(
        JavaScriptInvocationParams(functionBody: source),
      );
      expect(await evaluate('return await globalThis.firstReply;'), {
        'ok': [1, true, null],
      });
      expect(
        await evaluate(
          'return {end: globalThis.endRan, beforeLoad: globalThis.endBeforeLoad};',
        ),
        {'end': true, 'beforeLoad': true},
      );
      expect(
        await evaluate(
          'try { await webviewAll.callHandler("strict"); } catch (e) { return e.code; }',
        ),
        'forbidden',
      );
      expect(
        await evaluate(
          'return {tag: globalThis.literalClosingTag, comparison: globalThis.comparison};',
        ),
        {'tag': '</ScRiPt>', 'comparison': true},
      );
      expect(
        await evaluate(
          'try { await webviewAll.callHandler("echo", "中".repeat(400000)); } catch (error) { return error.code; }',
        ).timeout(const Duration(seconds: 5)),
        'serialization_error',
      );
      await controller.removeAllUserScripts();
      loaded = Completer<void>();
      await controller.reload();
      await loaded.future.timeout(const Duration(seconds: 10));
      expect(await evaluate('return await globalThis.firstReply;'), {
        'ok': [1, true, null],
      });
      expect(await evaluate('return typeof globalThis.endRan;'), 'undefined');
      expect(
        await controller.callAsyncJavaScript(
          JavaScriptInvocationParams(
            functionBody: 'return 42;',
            world: const WebViewJavaScriptWorld.isolated('unsupported'),
          ),
        ),
        isNull,
      );
      await controller.runJavaScript(
        'document.open(); document.write("<!doctype html><body>rewritten</body>"); document.close();',
      );
      expect(
        await evaluate(
          'return await webviewAll.callHandler("echo", {rewritten: true});',
        ),
        {'rewritten': true},
      );
      expect(
        await controller.callAsyncJavaScript(
          JavaScriptInvocationParams(
            functionBody:
                'return Object.prototype.hasOwnProperty.call(value, "__proto__");',
            arguments: {
              'value': {
                '__proto__': {'own': true},
              },
            },
          ),
        ),
        isTrue,
      );
      expect(
        await evaluate(
          """const value = JSON.parse('{"__proto__":{"own":true}}');
      const result = await webviewAll.callHandler('echo', value);
      return {own: Object.prototype.hasOwnProperty.call(result, '__proto__'), value: result['__proto__'].own};""",
        ),
        {'own': true, 'value': true},
      );

      final started = Completer<WebViewJavaScriptCall>();
      final result = Completer<Object?>();
      await controller.addJavaScriptHandler(
        WebViewJavaScriptHandlerParams(
          name: 'wait',
          onCall: (call) {
            started.complete(call);
            return result.future;
          },
          accessPolicy: const WebViewJavaScriptAccessPolicy.unrestricted(),
        ),
      );
      await controller.runJavaScript(
        'globalThis.pendingReply = webviewAll.callHandler("wait"); globalThis.pendingReply.catch(() => {});',
      );
      final pendingCall = await started.future.timeout(
        const Duration(seconds: 5),
      );
      var cancelled = false;
      unawaited(pendingCall.cancelled.then((_) => cancelled = true));
      await delegate.setOnNavigationRequest((_) => NavigationDecision.prevent);
      await controller.loadRequest(
        LoadRequestParams(uri: Uri.parse('https://blocked.example/')),
      );
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isFalse);
      result.complete('original document');
      expect(
        await evaluate('return await globalThis.pendingReply;'),
        'original document',
      );

      await delegate.setOnNavigationRequest((_) => NavigationDecision.navigate);
      when(
        factory.request(
          any,
          method: anyNamed('method'),
          requestHeaders: anyNamed('requestHeaders'),
          sendData: anyNamed('sendData'),
          abortSignal: anyNamed('abortSignal'),
        ),
      ).thenThrow(StateError('Network unavailable'));
      await expectLater(
        controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://unavailable.example/'),
            headers: {'X-Test': '1'},
          ),
        ),
        throwsStateError,
      );
      expect(
        await evaluate(
          'return await webviewAll.callHandler("echo", "still usable");',
        ),
        'still usable',
      );
      await expectLater(
        controller.installJavaScriptBridgeScript(
          const WebViewUserScript(
            source:
                'globalThis.failedRegistration = true; throw new Error("failed registration");',
          ),
        ),
        throwsA(anything),
      );
      loaded = Completer<void>();
      await controller.reload();
      await loaded.future.timeout(const Duration(seconds: 10));
      expect(
        await evaluate('return typeof globalThis.failedRegistration;'),
        'undefined',
      );
      expect(await evaluate('return await globalThis.firstReply;'), {
        'ok': [1, true, null],
      });
    },
  );
}

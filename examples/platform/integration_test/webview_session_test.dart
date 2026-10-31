import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
import 'package:webview_all_wkwebview/src/common/web_kit.g.dart' as wk;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native sessions isolate cookies/storage and report dynamic titles', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '<!doctype html><title>Initial</title><body>Session test</body>',
        );
        await request.response.close();
      }),
    );
    final url = Uri.parse('http://127.0.0.1:${server.port}/');
    final capabilities = await WebViewSession.getCapabilities();
    final sessions = <WebViewSession>[];
    // ArkWeb needs mounted widgets; stable keys preserve the surviving views.
    final mountedSessions = <WebViewSession>[];

    Future<void> updateWidgets() async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (final session in mountedSessions)
                Expanded(
                  key: ObjectKey(session),
                  child: WebViewWidget(controller: session.controller),
                ),
            ],
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> close(WebViewSession session) async {
      if (mountedSessions.remove(session)) await updateWidgets();
      await session.close();
    }

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final session in sessions) {
        await session.close();
      }
    });

    Future<WebViewSession> create(WebViewSessionMode mode) async {
      final session = await WebViewSession.create(mode: mode);
      expect(
        session,
        isNotNull,
        reason: 'Advertised $mode must create a native session',
      );
      sessions.add(session!);
      mountedSessions.add(session);
      await updateWidgets();
      await session.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      return session;
    }

    Future<void> load(WebViewSession session) async {
      final ready = Completer<void>();
      await session.controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!ready.isCompleted) ready.complete();
          },
        ),
      );
      await session.controller.loadRequest(url);
      await ready.future.timeout(const Duration(seconds: 25));
    }

    Future<Object?> read(WebViewSession session, String expression) =>
        session.controller.callAsyncJavaScript('return $expression;');

    final shared = await create(WebViewSessionMode.shared);
    await load(shared);
    await shared.controller.runJavaScript(
      "document.cookie='session_test=shared;path=/';localStorage.setItem('session_test','shared');",
    );

    final titles = <String>[];
    await shared.controller.setNavigationDelegate(
      NavigationDelegate(onTitleChange: titles.add),
    );
    await shared.controller.runJavaScript("document.title='Dynamic title';");
    Future<void> waitTitle(String title) async {
      for (var i = 0; i < 100 && !titles.contains(title); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(titles, contains(title));
    }

    await waitTitle('Dynamic title');
    final beforeEmpty = titles.length;
    await shared.controller.runJavaScript("document.title='';");
    for (var i = 0; i < 100 && titles.length == beforeEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(titles.length, greaterThan(beforeEmpty));
    expect(titles.last, await shared.controller.getTitle());
    await shared.controller.runJavaScript(
      "document.open();document.write('<title>Rewritten</title>');document.close();",
    );
    await waitTitle('Rewritten');

    final isolated = capabilities.supports(
      WebViewSessionMode.isolatedIncognito,
    );
    if (!isolated) {
      expect(
        await WebViewSession.create(mode: WebViewSessionMode.isolatedIncognito),
        isNull,
      );
    }
    if (!capabilities.supports(WebViewSessionMode.incognito) && !isolated) {
      await close(shared);
      return;
    }
    if (capabilities.incognitoSupport == WebViewIncognitoSupport.limited) {
      final limited = await create(WebViewSessionMode.incognito);
      await load(limited);
      expect(await read(limited, 'document.cookie'), contains('shared'));
      await close(limited);
      expect(await read(shared, 'document.cookie'), contains('shared'));
      expect(
        await read(shared, "localStorage.getItem('session_test')"),
        'shared',
      );
      await close(shared);
      return;
    }
    expect(capabilities.incognitoSupport, WebViewIncognitoSupport.nativeStore);
    final privateMode = isolated
        ? WebViewSessionMode.isolatedIncognito
        : WebViewSessionMode.incognito;
    final a = await create(privateMode);
    final b = await create(privateMode);
    await load(a);
    await load(b);
    expect(await read(a, 'document.cookie'), '');
    expect(await read(b, "localStorage.getItem('session_test')"), isNull);
    await a.cookieManager.setCookie(
      const WebViewCookie(
        name: 'session_test',
        value: 'private_a',
        domain: '127.0.0.1',
      ),
    );
    await a.controller.runJavaScript(
      "localStorage.setItem('session_test','private_a');",
    );
    expect(await read(a, 'document.cookie'), contains('private_a'));
    expect(await a.cookieManager.getCookies(domain: url), isNotEmpty);
    if (isolated) {
      expect(await b.cookieManager.getCookies(domain: url), isEmpty);
      expect(await read(b, 'document.cookie'), '');
    } else {
      // ArkWeb private views share one store, separate from ordinary views.
      expect(await read(b, 'document.cookie'), contains('private_a'));
      expect(
        await read(b, "localStorage.getItem('session_test')"),
        'private_a',
      );
    }
    expect(await read(shared, 'document.cookie'), contains('shared'));
    expect(
      await read(shared, "localStorage.getItem('session_test')"),
      'shared',
    );

    await b.cookieManager.setCookie(
      const WebViewCookie(
        name: 'session_test',
        value: 'private_b',
        domain: '127.0.0.1',
      ),
    );
    await a.cookieManager.clearCookies();
    expect(await a.cookieManager.getCookies(domain: url), isEmpty);
    if (isolated) {
      expect(
        (await b.cookieManager.getCookies(domain: url)).single.value,
        'private_b',
      );
    } else {
      expect(await b.cookieManager.getCookies(domain: url), isEmpty);
      expect(await read(shared, 'document.cookie'), contains('shared'));
    }
    final result = await a.dataManager.clearAllWebsiteData();
    expect(result.failures, isEmpty);
    await load(a);
    expect(await read(a, "localStorage.getItem('session_test')"), isNull);
    if (!isolated) {
      await load(b);
      expect(await read(b, "localStorage.getItem('session_test')"), isNull);
      await b.controller.runJavaScript(
        "document.cookie='session_test=private_b;path=/';localStorage.setItem('session_test','private_b');",
      );
    }
    expect(
      await read(shared, "localStorage.getItem('session_test')"),
      'shared',
    );
    await close(a);
    await close(a);
    expect(await read(shared, 'document.cookie'), contains('shared'));
    if (!isolated) {
      expect(await read(b, 'document.cookie'), contains('private_b'));
    }
    final fresh = await create(privateMode);
    await load(fresh);
    if (isolated) {
      expect(await fresh.cookieManager.getCookies(domain: url), isEmpty);
      expect(await read(fresh, "localStorage.getItem('session_test')"), isNull);
    } else {
      expect(await read(fresh, 'document.cookie'), contains('private_b'));
      expect(
        await read(fresh, "localStorage.getItem('session_test')"),
        'private_b',
      );
    }
    if (Platform.isIOS || Platform.isMacOS) {
      final params = WebKitWebViewControllerCreationParams(
        sessionMode: WebViewSessionMode.isolatedIncognito,
      );
      final first = WebViewController.fromPlatformCreationParams(params);
      final second = WebViewController.fromPlatformCreationParams(params);
      final ownedFirst = await OffscreenWebViewSession.fromController(first);
      final ownedSecond = await OffscreenWebViewSession.fromController(second);
      addTearDown(ownedFirst.close);
      addTearDown(ownedSecond.close);
      await first.platform.prepareSession();
      await second.platform.prepareSession();
      final cookiesA = WebViewCookieManager.fromPlatform(
        first.platform.createSessionCookieManager(),
      );
      final cookiesB = WebViewCookieManager.fromPlatform(
        second.platform.createSessionCookieManager(),
      );
      await cookiesA.setCookie(
        const WebViewCookie(
          name: 'reused_params',
          value: 'a',
          domain: '127.0.0.1',
        ),
      );
      expect(await cookiesB.getCookies(domain: url), isEmpty);
      await cookiesB.setCookie(
        const WebViewCookie(
          name: 'reused_params',
          value: 'b',
          domain: '127.0.0.1',
        ),
      );
      // Retain the native store to verify actual erasure, independently of Dart lifecycle guards.
      // ignore: invalid_use_of_visible_for_testing_member
      final identifier =
          (first.platform as WebKitWebViewController).webViewIdentifier;
      final view = wk.PigeonInstanceManager.instance
          .getInstanceWithWeakReference(identifier);
      final config = Platform.isMacOS
          ? (view as wk.NSViewWKWebView).configuration
          : (view as wk.UIViewWKWebView).configuration;
      final retainedStore = await config.getWebsiteDataStore();
      expect(await retainedStore.httpCookieStore.getAllCookies(), isNotEmpty);
      await ownedFirst.close();
      expect(await retainedStore.httpCookieStore.getAllCookies(), isEmpty);
      expect((await cookiesB.getCookies(domain: url)).single.value, 'b');
      expect(await read(shared, 'document.cookie'), contains('shared'));
      await ownedSecond.close();
    }
    // Keep the test output useful when diagnosing a runtime-specific failure.
    debugPrint(
      jsonEncode({
        'modes': capabilities.supportedModes.map((m) => m.name).toList(),
        'titles': titles,
      }),
    );
  });
}

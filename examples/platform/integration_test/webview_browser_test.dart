import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('browser operations use native history, find and cookie stores', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final slowStarted = Completer<void>();
    final releaseSlow = Completer<void>();
    final postStarted = Completer<void>();
    final releasePost = Completer<void>();
    final policyStarted = Completer<void>();
    final policyDecision = Completer<NavigationDecision>();
    addTearDown(() async {
      if (!releaseSlow.isCompleted) releaseSlow.complete();
      if (!releasePost.isCompleted) releasePost.complete();
      if (!policyDecision.isCompleted) {
        policyDecision.complete(NavigationDecision.prevent);
      }
      await server.close(force: true);
    });
    unawaited(
      server.forEach((request) async {
        try {
          if (request.uri.path == '/slow-post') {
            if (!postStarted.isCompleted) postStarted.complete();
            await releasePost.future;
          }
          if (request.uri.path == '/slow') {
            if (!slowStarted.isCompleted) slowStarted.complete();
            await releaseSlow.future;
          }
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '''<!doctype html><html><head><title>${request.uri.path}</title></head>
<body><p id="page">${request.uri.path}</p><p>search needle</p><p>search needle</p></body></html>''',
          );
          await request.response.close();
        } on IOException {
          // A stopped navigation can close its socket before the fixture responds.
        }
      }),
    );
    final origin = Uri.parse('http://127.0.0.1:${server.port}/');
    final controller = WebViewController(
      mediaPlaybackPolicy: WebViewMediaPlaybackPolicy.requireUserGesture,
    );
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
    Completer<void>? stopped;
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (request) {
          if (Uri.parse(request.url).path == '/held-policy') {
            if (!policyStarted.isCompleted) policyStarted.complete();
            return policyDecision.future;
          }
          return NavigationDecision.navigate;
        },
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
          final pendingStop = stopped;
          if (pendingStop != null && !pendingStop.isCompleted) {
            pendingStop.complete();
          }
        },
      ),
    );
    Future<void> load(String path) async {
      loaded = Completer<void>();
      await controller.loadRequest(origin.resolve(path));
      await loaded.future.timeout(const Duration(seconds: 25));
    }

    Future<void> stopNavigation(Future<void> request) async {
      final finished = Completer<void>();
      stopped = finished;
      try {
        await controller.stopLoading();
        await request.timeout(const Duration(seconds: 5));
        if (Platform.isWindows) {
          // Stop() queues cancellation. Keep the server response withheld until
          // NavigationCompleted acknowledges it, instead of racing the response.
          await finished.future.timeout(const Duration(seconds: 20));
        }
      } finally {
        stopped = null;
      }
    }

    final caps = await controller.getBrowserCapabilities();
    debugPrint(
      'Browser capabilities: find=${caps.findText}, count=${caps.findMatchCount}, picker=${caps.fileSelector}, creationMedia=${caps.mediaPlaybackPolicyAtCreation}',
    );
    expect(caps.stopLoading, isTrue);
    expect(caps.navigationHistory, isTrue);
    await load('/one');
    await load('/two');
    await load('/three');
    final history = (await controller.getNavigationHistory())!;
    final first = history.items.indexWhere(
      (item) => item.url == origin.resolve('/one').toString(),
    );
    final third = history.items.indexWhere(
      (item) => item.url == origin.resolve('/three').toString(),
    );
    expect(first, greaterThanOrEqualTo(0));
    expect(history.currentIndex, third);
    expect(await controller.goToHistoryIndex(-1), isFalse);
    expect(await controller.goToHistoryIndex(history.items.length), isFalse);
    loaded = Completer<void>();
    expect(await controller.goToHistoryIndex(first), isTrue);
    await loaded.future.timeout(const Duration(seconds: 25));
    expect((await controller.getNavigationHistory())!.currentIndex, first);
    expect(
      await controller.runJavaScriptReturningResult(
        'document.getElementById("page").textContent',
      ),
      contains('/one'),
    );

    if (caps.findText) {
      final found = await controller.findText('search needle');
      expect(found?.matchFound, isTrue);
      if (caps.findMatchCount) expect(found!.matchCount, 2);
      final next = await controller.findText('search needle');
      expect(next?.matchFound, isTrue);
      if (found?.activeMatchIndex != null && next?.activeMatchIndex != null) {
        expect(next!.activeMatchIndex, isNot(found!.activeMatchIndex));
      }
      expect(
        (await controller.findText('absent text 983417'))?.matchFound,
        isFalse,
      );
      if (caps.findCaseSensitive) {
        expect(
          (await controller.findText(
            'SEARCH NEEDLE',
            caseSensitive: true,
          ))?.matchFound,
          isFalse,
        );
      }
      final reverse = await controller.findText(
        'search needle',
        forward: false,
      );
      expect(reverse?.matchFound, isTrue);
      final rapid = await Future.wait([
        controller.findText('absent query 103781'),
        controller.findText('search needle'),
      ]);
      expect(rapid[0]?.matchFound, isFalse);
      expect(rapid[1]?.matchFound, isTrue);
      await controller.clearFindMatches();
    }
    if (caps.popupWindowPolicies.contains(WebViewPopupWindowPolicy.deny)) {
      await controller.setPopupPolicy(WebViewPopupWindowPolicy.deny);
      await controller.runJavaScript(
        'window.open("${origin.resolve('/blocked-popup')}");',
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(await controller.currentUrl(), origin.resolve('/one').toString());
      await controller.setPopupPolicy(WebViewPopupWindowPolicy.platformDefault);
    }

    final cookies = WebViewCookieManager();
    final cookieCaps = await cookies.getCapabilities();
    final name = 'webview_all_test_${DateTime.now().microsecondsSinceEpoch}';
    final expiry = DateTime.now().toUtc().add(const Duration(days: 1));
    final cookie = WebViewCookie(
      name: name,
      value: 'native=value',
      domain: origin.host,
      path: '/cookies',
      expires: expiry,
      isSecure: false,
      isHttpOnly: cookieCaps.setHttpOnly,
      sameSite: WebViewCookieSameSite.lax,
    );
    addTearDown(
      () => cookies.deleteCookie(
        name: name,
        domain: origin.host,
        path: '/cookies',
      ),
    );
    await cookies.setCookie(cookie);
    final visible = await cookies.getCookies(
      domain: origin.resolve('/cookies/check'),
    );
    final stored = visible.singleWhere((value) => value.name == name);
    expect(stored.value, cookie.value);
    if (cookieCaps.readableAttributes.contains(WebViewCookieAttribute.secure)) {
      expect(stored.isSecure, isFalse);
    }
    if (cookieCaps.readableAttributes.contains(
      WebViewCookieAttribute.httpOnly,
    )) {
      expect(stored.isHttpOnly, cookieCaps.setHttpOnly);
    }
    if (cookieCaps.readableAttributes.contains(
      WebViewCookieAttribute.sameSite,
    )) {
      expect(stored.sameSite, WebViewCookieSameSite.lax);
    }
    if (cookieCaps.readableAttributes.contains(
      WebViewCookieAttribute.expires,
    )) {
      expect(
        stored.expires!.difference(expiry).inMilliseconds.abs(),
        lessThan(1000),
      );
    }
    expect(
      (await cookies.getCookies(
        domain: origin.resolve('/other'),
      )).where((value) => value.name == name),
      isEmpty,
    );
    expect(
      await cookies.deleteCookie(
        name: name,
        domain: origin.host,
        path: '/cookies',
      ),
      isTrue,
    );
    expect(
      (await cookies.getCookies(
        domain: origin.resolve('/cookies/check'),
      )).where((value) => value.name == name),
      isEmpty,
    );

    final pending = controller.loadRequest(origin.resolve('/slow'));
    await slowStarted.future.timeout(const Duration(seconds: 20));
    await stopNavigation(pending);
    releaseSlow.complete();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(
      await controller.runJavaScriptReturningResult(
        'String(document.getElementById("page")?.textContent ?? "")',
      ),
      isNot(contains('/slow')),
    );
    await load('/one');
    final post = controller.loadRequest(
      origin.resolve('/slow-post'),
      method: LoadRequestMethod.post,
      body: Uint8List.fromList([1, 2, 3]),
    );
    await postStarted.future.timeout(const Duration(seconds: 20));
    await stopNavigation(post);
    releasePost.complete();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      await controller.runJavaScriptReturningResult(
        'String(document.getElementById("page")?.textContent ?? "")',
      ),
      isNot(contains('/slow-post')),
    );
    await load('/one');

    await controller.runJavaScript(
      'window.location.href = "${origin.resolve('/held-policy')}";',
    );
    await policyStarted.future.timeout(const Duration(seconds: 20));
    final historyBeforeStop = await controller.getNavigationHistory();
    await controller.stopLoading();
    policyDecision.complete(NavigationDecision.navigate);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // Stopping cannot recall requests already sent by an engine. Check that the
    // late decision neither commits a new history entry nor replaces the page.
    expect(
      (await controller.getNavigationHistory())!.currentIndex,
      historyBeforeStop!.currentIndex,
      reason: 'A late policy result must not commit the cancelled navigation.',
    );
    expect(
      await controller.runJavaScriptReturningResult(
        'document.getElementById("page")?.textContent',
      ),
      contains('/one'),
    );
  });
}

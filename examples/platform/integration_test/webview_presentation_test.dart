import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_android/webview_all_android.dart';

Future<String> _text(WebViewController view, String expression) async {
  final raw = (await view.runJavaScriptReturningResult(
    'String($expression)',
  )).toString();
  return raw.startsWith('"') ? jsonDecode(raw) as String : raw;
}

Future<void> _until(Future<bool> Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('The native page did not reach the expected state.');
}

Future<List<double>> _geometry(WebViewController view) async =>
    (jsonDecode(
              await _text(
                view,
                'JSON.stringify([innerWidth, devicePixelRatio, '
                'document.getElementById("box").getBoundingClientRect().width])',
              ),
            )
            as List)
        .map((v) => (v as num).toDouble())
        .toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native page zoom is absolute and can be reset', (tester) async {
    final session = (await WebViewSession.create(
      mode: WebViewSessionMode.shared,
    ))!;
    final view = session.controller;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
    });
    await view.setJavaScriptMode(JavaScriptMode.unrestricted);
    final caps = await view.getBrowserCapabilities();
    await view.enableZoom(false);
    if (caps.pageZoom) expect(await view.setPageZoom(3), isTrue);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WebViewWidget(controller: view),
      ),
    );
    await tester.pumpAndSettle();
    await view.loadHtmlString('''
<!doctype html><meta name="viewport" content="width=device-width">
<body><div id="box" style="width:100px;height:100px">中文缩放</div></body>
''');
    await _until(
      () async =>
          await _text(view, '!!document.getElementById("box")') == 'true',
    );
    if (!caps.pageZoom) {
      final previous = await _geometry(view);
      expect(await view.setPageZoom(2), isFalse);
      expect(await _geometry(view), previous);
      return;
    }
    final createdZoom = await _geometry(view);
    expect(await view.setPageZoom(3), isTrue);
    final sameZoom = await _geometry(view);
    for (var i = 0; i < sameZoom.length; i++) {
      expect(sameZoom[i], closeTo(createdZoom[i], 1));
    }
    expect(await view.setPageZoom(1), isTrue);
    await _until(() async {
      final current = await _geometry(view);
      return List.generate(
        3,
        (i) => (current[i] - createdZoom[i]).abs(),
      ).any((difference) => difference > 0.5);
    });
    final initial = await _geometry(view);
    expect(await view.setPageZoom(2), isTrue);
    await _until(() async {
      final current = await _geometry(view);
      return List.generate(
        3,
        (i) => (current[i] - initial[i]).abs(),
      ).any((difference) => difference > 0.5);
    });
    final doubled = await _geometry(view);
    expect(await view.setPageZoom(2), isTrue);
    expect(await view.setPageZoom(-1), isFalse);
    expect(await view.setPageZoom(double.nan), isFalse);
    final repeated = await _geometry(view);
    for (var i = 0; i < repeated.length; i++) {
      expect(repeated[i], closeTo(doubled[i], 1));
    }
    expect(await view.setPageZoom(1), isTrue);
    await _until(() async {
      final restored = await _geometry(view);
      return List.generate(
        3,
        (i) => (restored[i] - initial[i]).abs(),
      ).every((difference) => difference <= 1);
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await session.close();
    expect(await view.setPageZoom(2), isFalse);
  });

  testWidgets(
    'Android storage and cache policies preserve stored data and private policy',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final hits = <String, int>{};
      server.listen((request) async {
        hits.update(request.uri.path, (count) => count + 1, ifAbsent: () => 1);
        request.response.headers.contentType = ContentType.html;
        request.response.headers.set(
          HttpHeaders.cacheControlHeader,
          'no-store',
        );
        request.response.write(
          '<!doctype html><body data-page="${request.uri}">settings</body>',
        );
        await request.response.close();
      });
      final session = (await WebViewSession.create(
        mode: WebViewSessionMode.shared,
      ))!;
      final view = session.controller;
      final android = view.platform as AndroidWebViewController;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        await server.close(force: true);
      });
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: WebViewWidget(controller: view),
        ),
      );
      await tester.pumpAndSettle();
      final origin = Uri.parse('http://127.0.0.1:${server.port}');
      Future<void> load(String page) async {
        await view.loadRequest(origin.resolve(page));
        await _until(
          () async => await _text(view, 'document.body?.dataset.page') == page,
        );
      }

      expect(await android.setDomStorageEnabled(true), isTrue);
      await load('/settings?first');
      await view.runJavaScript(
        'localStorage.setItem("presentation-test", "保留 & +")',
      );
      expect(await android.setDomStorageEnabled(false), isTrue);
      await load('/settings?disabled');
      expect(
        await _text(view, '''(() => {
        try { return localStorage.getItem('presentation-test') || 'disabled'; }
        catch (_) { return 'disabled'; }
      })()'''),
        'disabled',
      );
      expect(await android.setDomStorageEnabled(true), isTrue);
      await load('/settings?restored');
      expect(
        await _text(view, 'localStorage.getItem("presentation-test")'),
        '保留 & +',
      );
      await view.runJavaScript('localStorage.removeItem("presentation-test")');

      final cacheMiss = Completer<WebResourceError>();
      await view.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (error) {
            if (error.isForMainFrame != false && !cacheMiss.isCompleted) {
              cacheMiss.complete(error);
            }
          },
        ),
      );
      expect(
        await android.setCacheMode(AndroidWebViewCacheMode.cacheOnly),
        isTrue,
      );
      await view.loadRequest(origin.resolve('/network-only'));
      final error = await cacheMiss.future.timeout(const Duration(seconds: 20));
      expect(error.description, contains('CACHE_MISS'));
      expect(hits['/network-only'] ?? 0, 0);
      expect(
        await android.setCacheMode(AndroidWebViewCacheMode.noCache),
        isTrue,
      );
      await load('/settings?network');
      expect(hits['/settings'], greaterThanOrEqualTo(4));
      expect(
        await android.setCacheMode(AndroidWebViewCacheMode.defaultMode),
        isTrue,
      );
      expect(await android.setAlgorithmicDarkeningAllowed(true), isTrue);
      expect(await android.setAlgorithmicDarkeningAllowed(false), isTrue);

      final privateSession = (await WebViewSession.create())!;
      try {
        final private =
            privateSession.controller.platform as AndroidWebViewController;
        expect(
          await private.setCacheMode(AndroidWebViewCacheMode.defaultMode),
          isFalse,
        );
        expect(
          await private.setCacheMode(AndroidWebViewCacheMode.noCache),
          isTrue,
        );
      } finally {
        await privateSession.close();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      expect(await android.setDomStorageEnabled(false), isFalse);
      expect(await android.setAlgorithmicDarkeningAllowed(true), isFalse);
      expect(
        await android.setCacheMode(AndroidWebViewCacheMode.noCache),
        isFalse,
      );
    },
    skip: !Platform.isAndroid,
  );
}

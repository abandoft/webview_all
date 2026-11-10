import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

Future<void> _until(WidgetTester tester, Future<bool> Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  Object? lastError;
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await check()) return;
    } catch (error) {
      lastError = error;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('The native page did not reach its expected state: $lastError');
}

Future<String> _value(WebViewController view, String expression) async {
  final result = (await view.runJavaScriptReturningResult(
    'String($expression)',
  )).toString();
  return result.startsWith('"') ? jsonDecode(result) as String : result;
}

Future<void> _load(WidgetTester tester, WebViewController view, Uri uri) async {
  await view.loadRequest(uri);
  await _until(
    tester,
    () async =>
        await _value(view, 'document.body?.dataset.page') ==
        uri.path.substring(1),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native profiles, export layouts, scoped data and navigation state', (
    tester,
  ) async {
    final caps = await WebViewSession.getCapabilities();
    if (!caps.relatedControllers) {
      debugPrint('Related native stores are unavailable.');
      return;
    }
    final independent = caps.supports(WebViewSessionMode.isolatedIncognito);
    if (!independent && !caps.namedProfiles) {
      debugPrint('Independent test stores are unavailable.');
      return;
    }
    final a = (await WebViewProfile.create(
      name: independent ? null : 'integration_advanced_a',
      mode: independent
          ? WebViewSessionMode.isolatedIncognito
          : WebViewSessionMode.shared,
    ))!;
    final b = (await WebViewProfile.create(
      name: independent ? null : 'integration_advanced_b',
      mode: independent
          ? WebViewSessionMode.isolatedIncognito
          : WebViewSessionMode.shared,
    ))!;
    final one = (await a.createSession())!,
        two = (await a.createSession())!,
        other = (await b.createSession())!;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!a.isClosed) {
        try {
          await a.dataManager.clearAllWebsiteData();
        } catch (_) {}
      }
      if (!b.isClosed) {
        try {
          await b.dataManager.clearAllWebsiteData();
        } catch (_) {}
      }
      await one.close();
      await two.close();
      await other.close();
      await a.close();
      await b.close();
      await server.close(force: true);
    });
    unawaited(
      server.forEach((request) async {
        request.response.headers.contentType = ContentType.html;
        final page = request.uri.path.substring(1);
        request.response.write(
          '''<!doctype html><html><head><title>Advanced $page</title>
<style>html,body{margin:0;background:rgb(20,180,60);height:100%}</style></head>
<body data-page="$page">Advanced native fixture $page</body></html>''',
        );
        await request.response.close();
      }),
    );
    Uri url(String page) => Uri.parse('http://127.0.0.1:${server.port}/$page');
    final view = one.controller;
    await view.setJavaScriptMode(JavaScriptMode.unrestricted);
    await two.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await other.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: view)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await _load(tester, view, url('a'));
    await view.runJavaScript('localStorage.setItem("account", "one")');
    await _load(tester, two.controller, url('a'));
    expect(
      await _value(two.controller, 'localStorage.getItem("account")'),
      'one',
    );
    await _load(tester, other.controller, url('a'));
    expect(
      await _value(other.controller, 'localStorage.getItem("account")'),
      'null',
    );
    await other.controller.runJavaScript(
      'localStorage.setItem("account", "other")',
    );
    const cookie = WebViewCookie(
      name: 'advanced_account',
      value: 'one',
      domain: '127.0.0.1',
    );
    await one.cookieManager.setCookie(cookie);
    expect(
      (await two.cookieManager.getCookies(
        domain: url('a'),
      )).any((v) => v.name == cookie.name),
      isTrue,
    );
    expect(
      (await other.cookieManager.getCookies(
        domain: url('a'),
      )).any((v) => v.name == cookie.name),
      isFalse,
    );

    final browser = await view.getBrowserCapabilities();
    debugPrint(
      'Advanced capabilities: layout=${browser.pdfPageLayout}, snapshot=${browser.navigationState}, clearHistory=${browser.clearHistory}',
    );
    if (browser.contextMenuControl) {
      expect(await view.setContextMenuEnabled(false), isTrue);
      expect(await view.setContextMenuEnabled(true), isTrue);
    }
    if (browser.audioMuting) {
      expect(await view.setAudioMuted(true), isTrue);
      expect(await view.setAudioMuted(false), isTrue);
    }
    if (browser.pauseMedia) expect(await view.pauseMedia(), isTrue);
    if (browser.suspendMedia) {
      expect(await view.setMediaPlaybackSuspended(true), isTrue);
      expect(await view.setMediaPlaybackSuspended(false), isTrue);
    }
    if (browser.screenshotRegion && browser.screenshotScale) {
      await tester.pump(const Duration(milliseconds: 300));
      final png = (await view.takeScreenshot(
        options: const WebViewScreenshotOptions(
          region: ui.Rect.fromLTWH(0, 0, 20, 20),
          scale: 2,
        ),
      ))!;
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect(image.width, 40);
      expect(image.height, 40);
      image.dispose();
      codec.dispose();
    }
    if (browser.printCancellation &&
        defaultTargetPlatform == TargetPlatform.iOS) {
      final job = await view.printPage(
        jobName: 'Integration print cancellation',
      );
      expect(job, isNotNull);
      expect(job!.canQueryState, isTrue);
      expect(job.canCancel, isTrue);
      expect(await job.cancel(), isTrue);
      await _until(
        tester,
        () async => await job.getState() == WebViewPrintState.cancelled,
      );
      await job.dispose();
      await job.dispose();
    }
    if (browser.pdfPageLayout) {
      final pdf = (await view.createPdf(
        options: const WebViewPdfOptions(
          paperSize: ui.Size(288, 432),
          margins: EdgeInsets.all(18),
        ),
      ))!;
      final text = latin1.decode(pdf);
      expect(text.startsWith('%PDF-'), isTrue);
      expect(
        RegExp(
          r'/MediaBox\s*\[\s*0\s+0\s+288(?:\.0+)?\s+432(?:\.0+)?\s*\]',
        ).hasMatch(text),
        isTrue,
        reason:
            'The exported PDF must retain the requested 4 × 6 inch paper size.',
      );
    }
    for (final format in browser.archiveFormats) {
      final bytes = (await view.createArchive(format: format))!;
      expect(bytes.length, greaterThan(100));
      if (format == WebViewArchiveFormat.mhtml) {
        expect(latin1.decode(bytes).toLowerCase(), contains('content-type:'));
      } else {
        expect(
          ascii.decode(bytes.take(8).toList(), allowInvalid: true),
          anyOf(startsWith('bplist'), startsWith('<?xml')),
        );
      }
    }
    await _load(tester, view, url('b'));
    if (browser.navigationState) {
      final history = (await view.getNavigationHistory())!;
      final snapshot = (await view.saveNavigationState())!;
      WebViewSession? restoreSession;
      try {
        expect(
          await other.controller.restoreNavigationState(snapshot),
          isFalse,
        );
        await _load(tester, view, url('c'));
        var targetView = view;
        if (browser.navigationStateRequiresNewView) {
          expect(await view.restoreNavigationState(snapshot), isFalse);
          expect(await _value(view, 'document.body.dataset.page'), 'c');
          restoreSession = (await a.createSession())!;
          targetView = restoreSession.controller;
          await targetView.setJavaScriptMode(JavaScriptMode.unrestricted);
        }
        expect(await targetView.restoreNavigationState(snapshot), isTrue);
        await _until(
          tester,
          () async =>
              await _value(targetView, 'document.body?.dataset.page') == 'b',
        );
        final restored = (await targetView.getNavigationHistory())!;
        expect(restored.currentIndex, history.currentIndex);
        expect(
          restored.items.map((v) => v.url),
          history.items.map((v) => v.url),
        );
      } finally {
        await restoreSession?.close();
        await snapshot.dispose();
      }
      expect(await view.restoreNavigationState(snapshot), isFalse);
    }
    if (browser.clearHistory) {
      expect(await view.clearNavigationHistory(), isTrue);
      expect(
        (await view.getNavigationHistory())!.items.length,
        lessThanOrEqualTo(1),
      );
    }

    final dataCaps = await a.dataManager.getCapabilities();
    final local = {WebViewDataType.localStorage};
    WebViewDataTarget? target;
    Set<WebViewDataType> types = local;
    if (dataCaps.scopedClearingGroups.containsKey(WebViewDataScope.origin)) {
      target = WebViewDataTarget.origin(url('a'));
    } else if (dataCaps.scopedClearingGroups.containsKey(
      WebViewDataScope.domain,
    )) {
      target = const WebViewDataTarget(
        scope: WebViewDataScope.domain,
        value: '127.0.0.1',
      );
      final refused = await a.dataManager.clearWebsiteDataFor(
        WebViewDataTarget.origin(url('a')),
        dataTypes: local,
      );
      expect(refused.isComplete, isFalse);
      expect(await _value(view, 'localStorage.getItem("account")'), 'one');
    } else if (dataCaps.scopedClearingGroups.containsKey(
      WebViewDataScope.site,
    )) {
      target = const WebViewDataTarget(
        scope: WebViewDataScope.site,
        value: '127.0.0.1',
      );
      final refused = await a.dataManager.clearWebsiteDataFor(
        target,
        dataTypes: local,
      );
      expect(refused.isComplete, isFalse);
      expect(await _value(view, 'localStorage.getItem("account")'), 'one');
      types = WebViewDataType.values.toSet();
    }
    if (target != null) {
      if (dataCaps.records) {
        final records = await a.dataManager.getWebsiteDataRecords(
          target: target,
          dataTypes: local,
        );
        expect(records, isNotNull);
        debugPrint('Scoped website-data records: ${records!.length}');
      }
      expect(
        (await a.dataManager.clearWebsiteDataFor(
          target,
          dataTypes: types,
        )).isComplete,
        isTrue,
      );
      await _load(tester, view, url('after-clear'));
      expect(await _value(view, 'localStorage.getItem("account")'), 'null');
      expect(
        await _value(other.controller, 'localStorage.getItem("account")'),
        'other',
      );
    }
    // Closing the profile prevents new sessions while existing children stay usable.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: two.controller)),
      ),
    );
    await tester.pump();
    await a.close();
    await one.close();
    expect(await a.createSession(), isNull);
    await _load(tester, two.controller, url('survivor'));
    expect(
      await _value(two.controller, 'document.body.dataset.page'),
      'survivor',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await two.dataManager.clearAllWebsiteData();
    await two.close();
    await a.whenReleased;
  });
  testWidgets(
    'named profiles preserve persistent cookies and storage when reopened',
    (tester) async {
      if (!(await WebViewSession.getCapabilities()).namedProfiles) return;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      unawaited(
        server.forEach((request) async {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><body data-page="named">Named profile</body></html>',
          );
          await request.response.close();
        }),
      );
      final uri = Uri.parse('http://127.0.0.1:${server.port}/named');
      WebViewProfile? profile;
      WebViewSession? session;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        if (profile != null && !profile.isClosed) {
          try {
            await profile.dataManager.clearAllWebsiteData();
          } catch (_) {}
        }
        await session?.close();
        await profile?.close();
        await server.close(force: true);
      });
      profile = (await WebViewProfile.create(name: 'integration_persistent'))!;
      await profile.dataManager.clearAllWebsiteData();
      session = (await profile.createSession())!;
      await session.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: session.controller)),
        ),
      );
      await tester.pump();
      await _load(tester, session.controller, uri);
      await profile.cookieManager.setCookie(
        WebViewCookie(
          name: 'persistent_fixture',
          value: 'retained',
          domain: '127.0.0.1',
          expires: DateTime.now().toUtc().add(const Duration(days: 1)),
        ),
      );
      await session.controller.runJavaScript(
        'localStorage.setItem("persistent_fixture", "retained")',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await profile.close();
      await profile.whenReleased;
      profile = (await WebViewProfile.create(name: 'integration_persistent'))!;
      expect(
        (await profile.cookieManager.getCookies(
          domain: uri,
        )).any((c) => c.name == 'persistent_fixture' && c.value == 'retained'),
        isTrue,
      );
      session = (await profile.createSession())!;
      await session.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: session.controller)),
        ),
      );
      await tester.pump();
      await _load(tester, session.controller, uri);
      expect(
        await _value(
          session.controller,
          'localStorage.getItem("persistent_fixture")',
        ),
        'retained',
      );
    },
  );
}

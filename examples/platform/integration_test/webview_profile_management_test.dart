import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'named profile lifecycle, native cookie metadata, rules and full document capture',
    (tester) async {
      final manager = WebViewProfileManager();
      final management = await manager.getCapabilities();
      final sessionCaps = await WebViewSession.getCapabilities();
      if (!sessionCaps.namedProfiles || !management.listing) {
        debugPrint('The installed runtime cannot manage named profiles.');
        return;
      }
      final name =
          'integration_management_${DateTime.now().microsecondsSinceEpoch}'
              .padRight(64, 'x');
      for (final old
          in (await manager.listProfiles()) ?? <WebViewProfileInfo>[]) {
        if (old.name.startsWith('integration_management_')) {
          final cleanup = await manager.requestDeletion(old.name);
          expect(cleanup.status, isNot(WebViewProfileDeletionStatus.failed));
        }
      }
      final before = await manager.requestDeletion(name);
      expect(before.status, isNot(WebViewProfileDeletionStatus.failed));
      if (before.status == WebViewProfileDeletionStatus.pending ||
          before.status == WebViewProfileDeletionStatus.requiresRestart) {
        debugPrint(
          'The prior fixture is awaiting native cleanup; use a fresh browser process.',
        );
        return;
      }
      final ordinaryCookies = WebViewCookieManager();
      final marker = 'ordinary_${DateTime.now().microsecondsSinceEpoch}';
      await ordinaryCookies.setCookie(
        WebViewCookie(name: marker, value: 'retained', domain: '127.0.0.1'),
      );
      addTearDown(
        () => ordinaryCookies.deleteCookie(name: marker, domain: '127.0.0.1'),
      );
      final coldCookie = await ordinaryCookies.getCookies(
        domain: Uri.parse('http://127.0.0.1/'),
      );
      expect(
        coldCookie.any((cookie) => cookie.name == marker),
        isTrue,
        reason:
            'Global session cookies must survive temporary helper disposal before the first page loads.',
      );
      final profile = (await WebViewProfile.create(name: name))!;
      final session = (await profile.createSession())!;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        await profile.close();
      });
      final view = session.controller;
      await view.setJavaScriptMode(JavaScriptMode.unrestricted);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WebViewWidget(controller: view)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<!doctype html><html><head><style>body{margin:0;background:#ffeedd;height:1800px}</style></head><body><div class="fixture-hidden">hidden</div><p>Profile fixture</p></body></html>',
          );
          await request.response.close();
        }),
      );
      final uri = Uri.parse('http://127.0.0.1:${server.port}/fixture');
      final loaded = Completer<void>();
      await view.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
      final network = await view.getNetworkCapabilities();
      if (network.ruleActions.contains(WebViewContentRuleAction.hideElements)) {
        expect(
          await view.setContentRules([
            WebViewContentRule(
              urlPattern: '*',
              action: WebViewContentRuleAction.hideElements,
              selector: '.fixture-hidden',
              ifTopUrls: ['http://127.0.0.1:*/fixture'],
            ),
          ]),
          isTrue,
        );
      }
      await view.loadRequest(uri);
      await loaded.future.timeout(const Duration(seconds: 30));
      await tester.pump(const Duration(milliseconds: 700));
      if (network.ruleActions.contains(WebViewContentRuleAction.hideElements)) {
        final display = (await view.runJavaScriptReturningResult(
          'getComputedStyle(document.querySelector(".fixture-hidden")).display',
        )).toString();
        expect(display, contains('none'));
        expect(await view.setContentRules([]), isTrue);
      }
      expect(
        (await manager.listProfiles())!.any((v) => v.name == name),
        isTrue,
      );
      expect(
        (await manager.requestDeletion(name)).status,
        WebViewProfileDeletionStatus.busy,
      );
      final cookies = session.cookieManager;
      await cookies.setCookie(
        const WebViewCookie(
          name: 'metadata',
          value: 'a=b',
          domain: '127.0.0.1',
          path: '/fixture',
          isHttpOnly: true,
        ),
      );
      final cookieCaps = await cookies.getCapabilities();
      if (cookieCaps.readableAttributes.contains(
        WebViewCookieAttribute.httpOnly,
      )) {
        final found = (await cookies.getCookies(
          domain: uri,
        )).singleWhere((v) => v.name == 'metadata');
        expect(found.isHttpOnly, isTrue);
        expect(found.path, '/fixture');
        expect(found.value, 'a=b');
      }
      if (Platform.isAndroid) {
        final identityUri = Uri.parse('https://identity.example.test/');
        const identity = 'host_domain_identity';
        await cookies.setCookie(
          const WebViewCookie(
            name: identity,
            value: 'host',
            domain: 'https://identity.example.test',
          ),
        );
        await cookies.setCookie(
          const WebViewCookie(
            name: identity,
            value: 'domain',
            domain: '.identity.example.test',
          ),
        );
        expect(
          (await cookies.getCookies(
            domain: identityUri,
          )).where((v) => v.name == identity),
          hasLength(2),
        );
        await cookies.deleteCookie(name: identity, domain: identityUri.host);
        final remaining = (await cookies.getCookies(
          domain: identityUri,
        )).where((v) => v.name == identity).toList();
        expect(remaining, hasLength(1));
        expect(remaining.single.value, 'domain');
        await cookies.deleteCookie(
          name: identity,
          domain: '.identity.example.test',
        );
        expect(
          (await cookies.getCookies(
            domain: identityUri,
          )).where((v) => v.name == identity),
          isEmpty,
        );
        await cookies.setCookie(
          const WebViewCookie(
            name: '__Host-identity',
            value: 'secure',
            domain: 'identity.example.test',
            isSecure: true,
          ),
        );
        expect(
          (await cookies.getCookies(
            domain: identityUri,
          )).any((v) => v.name == '__Host-identity'),
          isTrue,
        );
        await cookies.deleteCookie(
          name: '__Host-identity',
          domain: identityUri.host,
        );
        expect(
          (await cookies.getCookies(
            domain: identityUri,
          )).any((v) => v.name == '__Host-identity'),
          isFalse,
        );
      }
      final tools = await view.getBrowserCapabilities();
      if (tools.fullDocumentScreenshot) {
        final beforeScroll = await view.runJavaScriptReturningResult('scrollY');
        final png = await view.takeScreenshot(
          options: const WebViewScreenshotOptions(fullDocument: true),
        );
        expect(png, isNotNull);
        final codec = await ui.instantiateImageCodec(png!);
        final image = (await codec.getNextFrame()).image;
        expect(image.height, greaterThanOrEqualTo(1800));
        image.dispose();
        codec.dispose();
        expect(
          await view.runJavaScriptReturningResult('scrollY'),
          beforeScroll,
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await profile.close();
      // Platform-view disposal and WebKit's final native release can complete
      // after the Dart close future. Busy must remain retryable and truthful.
      var after = await manager.requestDeletion(name);
      final releaseDeadline = DateTime.now().add(const Duration(seconds: 8));
      while (after.status == WebViewProfileDeletionStatus.busy &&
          DateTime.now().isBefore(releaseDeadline)) {
        await tester.pump(const Duration(milliseconds: 200));
        after = await manager.requestDeletion(name);
      }
      if (Platform.isAndroid) {
        expect(after.status, WebViewProfileDeletionStatus.requiresRestart);
      } else if (Platform.isWindows) {
        expect(after.status, WebViewProfileDeletionStatus.pending);
      } else {
        expect(after.status, WebViewProfileDeletionStatus.deleted);
        expect(
          (await manager.listProfiles())!.any((v) => v.name == name),
          isFalse,
        );
      }
      if (Platform.isWindows) {
        expect(
          await WebViewProfile.create(name: name),
          isNull,
          reason:
              'A pending native deletion must not reopen or fall back to the ordinary profile.',
        );
      } else {
        final reopened = (await WebViewProfile.create(name: name))!;
        try {
          final values = await reopened.cookieManager.getCookies(domain: uri);
          expect(
            values.any((cookie) => cookie.name == 'metadata'),
            Platform.isAndroid,
            reason:
                'Only a completed deletion removes the named profile cookie; a restart-required request must preserve it.',
          );
        } finally {
          await reopened.close();
        }
        if (!Platform.isAndroid) {
          var cleanup = await manager.requestDeletion(name);
          final deadline = DateTime.now().add(const Duration(seconds: 8));
          while (cleanup.status == WebViewProfileDeletionStatus.busy &&
              DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 200));
            cleanup = await manager.requestDeletion(name);
          }
          expect(
            cleanup.status,
            anyOf(
              WebViewProfileDeletionStatus.deleted,
              WebViewProfileDeletionStatus.notFound,
            ),
          );
        }
      }
      expect(
        (await ordinaryCookies.getCookies(
          domain: uri,
        )).any((cookie) => cookie.name == marker && cookie.value == 'retained'),
        isTrue,
        reason: 'Deleting a named profile must never clear ordinary cookies.',
      );
    },
  );
}

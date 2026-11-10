import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
import 'package:webview_all_linux/webview_all_linux.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in [
    WebViewSessionMode.shared,
    WebViewSessionMode.incognito,
  ]) {
    testWidgets('native child attachment preserves POST and opener (${mode.name})', (
      tester,
    ) async {
      final parent = Platform.isIOS || Platform.isMacOS
          ? WebViewController.fromPlatformCreationParams(
              WebKitWebViewControllerCreationParams(
                sessionMode: mode,
                javaScriptCanOpenWindowsAutomatically: true,
              ),
            )
          : Platform.isLinux
          ? WebViewController.fromPlatformCreationParams(
              LinuxWebViewControllerCreationParams(
                sessionMode: mode,
                javascriptCanOpenWindowsAutomatically: true,
              ),
            )
          : WebViewController.fromPlatformCreationParams(
              PlatformWebViewControllerCreationParams(sessionMode: mode),
            );
      final children = <WebViewController>[];
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final child in children) {
          await child.platform.closeWebViewSession();
        }
        await parent.platform.closeWebViewSession();
      });
      final caps = await parent.getBrowserCapabilities();
      if (!caps.newWindowDelegate) {
        await parent.setNewWindowDelegate((_) {});
        await parent.setOnWindowCloseRequested(() {});
        return;
      }
      expect(
        Platform.isAndroid ||
            Platform.isWindows ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isLinux,
        isTrue,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final childRequests = <String>[];
      unawaited(
        server.forEach((request) async {
          final body = await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.html;
          if (request.uri.path == '/child') {
            childRequests.add('${request.method}:$body');
            request.response.write(
              '<html><head><title>Native child</title></head><body>native child</body></html>',
            );
          } else {
            request.response.write(
              '''<html><body><form id="popup" method="POST" action="/child" target="native_child"><input name="value" value="kept"></form></body></html>''',
            );
          }
          await request.response.close();
        }),
      );
      final uri = Uri.parse('http://127.0.0.1:${server.port}/parent');
      final parentLoaded = Completer<void>();
      WebViewResourceDelegate resource(String title) => WebViewResourceDelegate(
        onRequest: (_) => WebViewResourceResponse.bytes(
          utf8.encode(
            '<html><head><title>$title</title></head><body>$title<script>document.title += ": JavaScript";</script></body></html>',
          ),
          mimeType: 'text/html',
        ),
      );
      await parent.setResourceDelegate(resource('Parent resources'));
      await parent.setJavaScriptMode(JavaScriptMode.unrestricted);
      await parent.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!parentLoaded.isCompleted) parentLoaded.complete();
          },
        ),
      );
      Widget layout([WebViewController? child]) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: WebViewWidget(controller: parent)),
              if (child != null)
                Expanded(child: WebViewWidget(controller: child)),
            ],
          ),
        ),
      );
      await tester.pumpWidget(layout());
      await tester.pump();
      await parent.loadRequest(uri);
      await parentLoaded.future.timeout(const Duration(seconds: 25));
      final attached = Completer<WebViewController>();
      final loaded = Completer<void>();
      final closed = Completer<void>();
      var requests = 0;
      await parent.setNewWindowDelegate((request) async {
        requests++;
        final child = (await request.createController())!;
        expect(identical(await request.createController(), child), isTrue);
        children.add(child);
        await child.setJavaScriptMode(JavaScriptMode.unrestricted);
        await child.setResourceDelegate(resource('Child resources'));
        await child.setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!loaded.isCompleted) loaded.complete();
            },
          ),
        );
        await child.setOnWindowCloseRequested(() {
          if (!closed.isCompleted) closed.complete();
        });
        expect(await request.attach(child), isTrue);
        expect(await request.attach(child), isFalse);
        attached.complete(child);
      });
      await parent.setPopupPolicy(WebViewPopupWindowPolicy.deny);
      await parent.runJavaScript('window.open("${uri.resolve('/blocked')}");');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(requests, 0);
      await parent.setPopupPolicy(WebViewPopupWindowPolicy.platformDefault);
      await parent.runJavaScript('document.getElementById("popup").submit();');
      final child = await attached.future.timeout(const Duration(seconds: 25));
      await tester.pumpWidget(layout(child));
      await tester.pump();
      await loaded.future.timeout(const Duration(seconds: 25));
      expect(requests, 1);
      expect(childRequests, ['POST:value=kept']);
      expect(
        await child.runJavaScriptReturningResult(
          'String(window.opener != null)',
        ),
        contains('true'),
      );
      expect(await parent.currentUrl(), uri.toString());
      final rejected = Completer<bool>();
      await parent.setNewWindowDelegate((request) async {
        rejected.complete(await request.attach(child));
      });
      await parent.runJavaScript('window.open("${uri.resolve('/reused')}");');
      expect(
        await rejected.future.timeout(const Duration(seconds: 25)),
        isFalse,
      );
      expect(await child.currentUrl(), uri.resolve('/child').toString());
      final pending = Completer<WebViewNewWindowRequest<WebViewController>>();
      final release = Completer<void>();
      await parent.setNewWindowDelegate((request) async {
        pending.complete(request);
        await release.future;
      });
      // WebView2 may hold ExecuteScript until the window deferral completes.
      final opening = parent.runJavaScript(
        'window.open("${uri.resolve('/cancelled')}");',
      );
      final request = await pending.future.timeout(const Duration(seconds: 25));
      await parent.setPopupPolicy(WebViewPopupWindowPolicy.deny);
      final unused = WebViewController();
      children.add(unused);
      expect(await request.attach(unused), isFalse);
      release.complete();
      await opening;
      await parent.setPopupPolicy(WebViewPopupWindowPolicy.platformDefault);
      await parent.setNewWindowDelegate(
        (_) => throw StateError('Reject fixture request'),
      );
      await parent.runJavaScript('window.open("${uri.resolve('/rejected')}");');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      Future<void> waitTitle(WebViewController target, String title) async {
        final until = DateTime.now().add(const Duration(seconds: 20));
        String? actual;
        while (DateTime.now().isBefore(until)) {
          actual = await target.getTitle();
          if (actual == title) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail(
          'Expected related controller title "$title", received "$actual" '
          'at ${await target.currentUrl()}.',
        );
      }

      await child.setJavaScriptMode(JavaScriptMode.disabled);
      await child.loadRequest(child.getResourceUri('page.html')!);
      await waitTitle(child, 'Child resources');
      await parent.loadRequest(parent.getResourceUri('page.html')!);
      await waitTitle(parent, 'Parent resources: JavaScript');
      expect(await child.getTitle(), 'Child resources');
      await child.setJavaScriptMode(JavaScriptMode.unrestricted);
      await child.loadRequest(child.getResourceUri('page.html')!);
      await waitTitle(child, 'Child resources: JavaScript');
      expect(await parent.getTitle(), 'Parent resources: JavaScript');
      if (Platform.isIOS || Platform.isMacOS || Platform.isLinux) {
        final abandoned = Completer<void>();
        final scriptFinished = Completer<void>();
        await parent.setNewWindowDelegate((request) {
          final finishing = () async {
            await scriptFinished.future;
            final earlyChild = await request.createController();
            if (earlyChild == null) return;
            children.add(earlyChild);
            final earlyClosed = Completer<void>();
            await earlyChild.setOnWindowCloseRequested(() {
              if (!earlyClosed.isCompleted) earlyClosed.complete();
            });
            if (await request.attach(earlyChild)) {
              // Engines may defer the close message until attachment finishes.
              await earlyClosed.future.timeout(const Duration(seconds: 10));
            }
            await earlyChild.platform.closeWebViewSession();
          }();
          abandoned.complete(finishing);
          return finishing;
        });
        await parent.runJavaScript(
          '(() => { const early = window.open("about:blank"); if (early) early.close(); })();',
        );
        scriptFinished.complete();
        await abandoned.future.timeout(const Duration(seconds: 10));
      }
      await child.runJavaScript('window.close();');
      await closed.future.timeout(const Duration(seconds: 10));
      await parent.setNewWindowDelegate(null);
    });
  }
}

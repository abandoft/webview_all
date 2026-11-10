import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native fullscreen can be presented and exited by the app', (
    tester,
  ) async {
    // These backends forward Flutter pointer events to their native WebViews.
    if (!Platform.isAndroid && !Platform.isWindows) return;
    final controller = WebViewController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.platform.closeWebViewSession();
    });
    final caps = await controller.getBrowserCapabilities();
    expect(caps.fullscreenEvents, isTrue);
    final loaded = Completer<void>();
    final entered = Completer<WebViewFullscreenRequest>();
    final exited = Completer<void>();
    var exits = 0;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await controller.setFullscreenDelegate(
      WebViewFullscreenDelegate(
        onEnter: (request) {
          if (!entered.isCompleted) entered.complete(request);
        },
        onExit: () {
          exits++;
          if (!exited.isCompleted) exited.complete();
        },
      ),
    );
    Widget page([Widget? content]) => MaterialApp(
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: controller),
            ?content,
          ],
        ),
      ),
    );
    await tester.pumpWidget(page());
    await controller.loadHtmlString(
      '''<html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0"><button style="width:100vw;height:100vh" onclick="document.documentElement.requestFullscreen()">Enter fullscreen</button></body></html>''',
    );
    await loaded.future.timeout(const Duration(seconds: 20));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.tap(find.byType(WebViewWidget));
    await tester.pump();
    final request = await entered.future.timeout(const Duration(seconds: 10));
    expect(request.content != null, caps.fullscreenCustomContent);
    await tester.pumpWidget(page(request.content));
    await tester.pump();
    expect(await request.exit(), isTrue);
    await exited.future.timeout(const Duration(seconds: 10));
    expect(exits, 1);
    await tester.pumpWidget(page());
    await controller.setFullscreenDelegate(null);
  });
}

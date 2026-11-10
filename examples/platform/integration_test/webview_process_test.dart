import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

Future<void> waitForTitle(WebViewController controller, String title) async {
  final until = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(until)) {
    if (await controller.getTitle() == title) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('The recovered page did not load.');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renderer loss keeps the host alive and reports recovery', (
    tester,
  ) async {
    if (!Platform.isAndroid && !Platform.isWindows) return;
    var controller = WebViewController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.platform.closeWebViewSession();
    });
    final caps = await controller.getBrowserCapabilities();
    if (!caps.processFailureEvents) return;
    final failure = Completer<WebViewProcessFailure>();
    // Deliberately omit NavigationDelegate: renderer handling must work even
    // when the application has not installed navigation callbacks.
    await controller.setOnProcessFailed((event) {
      if (!failure.isCompleted &&
          event.kind == WebViewProcessFailureKind.rendererExited) {
        failure.complete(event);
      }
    });
    Widget page() => MaterialApp(
      home: Scaffold(body: WebViewWidget(controller: controller)),
    );
    await tester.pumpWidget(page());
    await controller.loadHtmlString(
      '<html><head><title>Alive</title></head><body>before crash</body></html>',
    );
    await waitForTitle(controller, 'Alive');
    // Chromium's documented renderer-crash test URLs affect only this runtime.
    await controller.loadRequest(
      Uri.parse(Platform.isAndroid ? 'chrome://crash' : 'edge://crash'),
    );
    final event = await failure.future.timeout(const Duration(seconds: 20));
    expect(event.kind, WebViewProcessFailureKind.rendererExited);
    expect(
      event.recovery,
      Platform.isAndroid
          ? WebViewProcessRecovery.recreate
          : WebViewProcessRecovery.reload,
    );
    if (Platform.isAndroid) {
      expect(event.didCrash, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.platform.closeWebViewSession();
      controller = WebViewController();
      await tester.pumpWidget(page());
    }
    await controller.loadHtmlString(
      '<html><head><title>Recovered</title></head><body>after crash</body></html>',
    );
    await waitForTitle(controller, 'Recovered');
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

Future<T> _step<T>(String name, Future<T> Function() operation) async {
  debugPrintSynchronously('Fullscreen: $name');
  final result = await operation().timeout(
    const Duration(seconds: 30),
    onTimeout: () => throw TimeoutException('Fullscreen: $name'),
  );
  debugPrintSynchronously('Fullscreen: $name completed');
  return result;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native fullscreen can be presented and exited by the app', (
    tester,
  ) async {
    // These backends forward Flutter pointer events to their native WebViews.
    if (!Platform.isAndroid && !Platform.isWindows) return;
    debugPrintSynchronously('Fullscreen: creating controller');
    final controller = WebViewController();
    addTearDown(() async {
      try {
        await _step(
          'unmount view',
          () => tester.pumpWidget(const SizedBox.shrink()),
        );
      } finally {
        await _step(
          'close controller',
          controller.platform.closeWebViewSession,
        );
      }
    });
    final caps = await _step(
      'query capabilities',
      controller.getBrowserCapabilities,
    );
    expect(caps.fullscreenEvents, isTrue);
    final loaded = Completer<void>();
    final entered = Completer<WebViewFullscreenRequest>();
    final exited = Completer<void>();
    var exits = 0;
    await _step(
      'enable JavaScript',
      () => controller.setJavaScriptMode(JavaScriptMode.unrestricted),
    );
    await _step(
      'install navigation delegate',
      () => controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      ),
    );
    await _step(
      'install fullscreen delegate',
      () => controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(
          onEnter: (request) {
            if (!entered.isCompleted) entered.complete(request);
          },
          onExit: () {
            exits++;
            if (!exited.isCompleted) exited.complete();
          },
        ),
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
    await _step('mount view', () => tester.pumpWidget(page()));
    await _step(
      'load fixture',
      () => controller.loadHtmlString(
        '''<html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0"><button style="width:100vw;height:100vh" onclick="document.documentElement.requestFullscreen()">Enter fullscreen</button></body></html>''',
      ),
    );
    await _step('wait for fixture', () => loaded.future);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _step(
      'tap fullscreen button',
      () => tester.tap(find.byType(WebViewWidget)),
    );
    await tester.pump();
    final request = await _step(
      'wait for native fullscreen entry',
      () => entered.future,
    );
    expect(request.content != null, caps.fullscreenCustomContent);
    await _step(
      'present fullscreen content',
      () => tester.pumpWidget(page(request.content)),
    );
    await tester.pump();
    expect(await _step('request fullscreen exit', request.exit), isTrue);
    await _step('wait for native fullscreen exit', () => exited.future);
    expect(exits, 1);
    await _step('restore view', () => tester.pumpWidget(page()));
    await _step(
      'remove fullscreen delegate',
      () => controller.setFullscreenDelegate(null),
    );
  }, timeout: const Timeout(Duration(minutes: 3)));
}

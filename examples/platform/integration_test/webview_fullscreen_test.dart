import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
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
    final clicked = Completer<void>();
    final granted = Completer<void>();
    final rejected = Completer<String>();
    final exited = Completer<void>();
    var exits = 0;
    await _step(
      'enable JavaScript',
      () => controller.setJavaScriptMode(JavaScriptMode.unrestricted),
    );
    await _step(
      'install page probe',
      () => controller.addJavaScriptChannel(
        'FullscreenProbe',
        onMessageReceived: (message) {
          debugPrintSynchronously('Fullscreen page: ${message.message}');
          if (message.message.startsWith('clicked:') && !clicked.isCompleted) {
            clicked.complete();
          } else if (message.message == 'granted' && !granted.isCompleted) {
            granted.complete();
          } else if (message.message.startsWith('rejected:') &&
              !rejected.isCompleted) {
            rejected.complete(message.message);
          }
        },
      ),
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
    // Navigator transition snapshots can absorb input even after the native
    // page has loaded. Fullscreen needs a stable view, without a route change.
    Widget page([Widget? content]) => Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: controller),
          ?content,
        ],
      ),
    );
    await _step('mount view', () => tester.pumpWidget(page()));
    await _step(
      'load fixture',
      () => controller.loadHtmlString(
        '''<!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0"><button id="fullscreen-target" style="width:100vw;height:100vh" onclick="
FullscreenProbe.postMessage('clicked:' + document.visibilityState + ':' + document.hasFocus());
document.documentElement.requestFullscreen().then(function() {
  FullscreenProbe.postMessage('granted');
}).catch(function(error) {
  FullscreenProbe.postMessage('rejected:' + error.name + ':' + error.message);
});">Enter fullscreen</button></body></html>''',
      ),
    );
    await _step('wait for fixture', () => loaded.future);
    await _step(
      'settle view layout',
      () => tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      ),
    );
    await _step('wait for visible native page', () async {
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      while (DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
        final visible = await controller.runJavaScriptReturningResult(
          '!!document.getElementById("fullscreen-target") && '
          'typeof FullscreenProbe !== "undefined" && '
          'document.visibilityState === "visible" && innerWidth > 1 && innerHeight > 1',
        );
        if (visible == true || visible == 'true') return;
      }
      fail('The native page did not become visible before input.');
    });
    expect(find.byType(WebViewWidget).hitTestable(), findsOneWidget);
    await _step(
      'tap fullscreen button',
      () => tester.tap(
        find.byType(WebViewWidget),
        kind: Platform.isWindows
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      ),
    );
    await _step('wait for page click', () => clicked.future);
    final outcome = await _step(
      'wait for native fullscreen entry',
      () => Future.any<Object>([entered.future, rejected.future]),
    );
    if (outcome is String) fail('The page refused fullscreen: $outcome');
    final request = outcome as WebViewFullscreenRequest;
    expect(request.content != null, caps.fullscreenCustomContent);
    await _step(
      'present fullscreen content',
      () => tester.pumpWidget(page(request.content)),
    );
    await tester.pump();
    final grant = await _step(
      'wait for page fullscreen entry',
      () => Future.any<Object?>([granted.future, rejected.future]),
    );
    if (grant is String) fail('The page refused fullscreen: $grant');
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

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native captures and selective clearing preserve other data', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        debugPrint('Page export fixture: ${request.uri.path}');
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><html><head><title>Page export</title>
<style>html,body{margin:0;background:rgb(20,180,60);min-height:100%;}p{margin:0}</style>
</head><body><p>Native page capture and PDF export</p></body></html>''',
        );
        await request.response.close();
      }),
    );
    final uri = Uri.parse('http://127.0.0.1:${server.port}/export');
    final controller = WebViewController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.platform.closeWebViewSession();
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(child: WebViewWidget(controller: controller)),
              const Positioned(
                top: 0,
                right: 0,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    var loaded = Completer<void>();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) => debugPrint('Page export loading: $url'),
        onWebResourceError: (error) =>
            debugPrint('Page export error: ${error.description}'),
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await controller.loadRequest(uri);
    await loaded.future.timeout(const Duration(seconds: 25));
    await tester.pumpAndSettle();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final caps = await controller.getBrowserCapabilities();
    debugPrint(
      'Page export capabilities: PNG=${caps.viewportScreenshot}, PDF=${caps.pdfExport}',
    );
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isWindows) {
      expect(caps.viewportScreenshot, isTrue);
      expect(caps.pdfExport, !Platform.isAndroid);
      // Queue distinct native operations without letting overlapping print jobs race.
      final captures = await Future.wait([
        controller.takeScreenshot(),
        controller.createPdf(),
        controller.takeScreenshot(),
      ]);
      for (final index in [0, 2]) {
        final png = captures[index]!;
        expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(png);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(20));
        expect(frame.image.height, greaterThan(20));
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset =
            ((frame.image.height ~/ 2) * frame.image.width +
                frame.image.width ~/ 2) *
            4;
        expect(pixels.getUint8(offset), closeTo(20, 8));
        expect(pixels.getUint8(offset + 1), closeTo(180, 8));
        expect(pixels.getUint8(offset + 2), closeTo(60, 8));
        // Flutter's red overlay occupies this corner; it must be absent in native exports.
        final corner = (5 * frame.image.width + frame.image.width - 5) * 4;
        expect(pixels.getUint8(corner), closeTo(20, 8));
        expect(pixels.getUint8(corner + 1), closeTo(180, 8));
        frame.image.dispose();
        codec.dispose();
      }
      if (caps.pdfExport) {
        final pdf = captures[1]!;
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        expect(pdf.length, greaterThan(500));
      } else {
        expect(captures[1], isNull);
      }
    }

    final data = WebViewDataManager.fromPlatform(
      controller.platform.createSessionDataManager(),
    );
    final dataCaps = await data.getCapabilities();
    final empty = await data.clearWebsiteData(dataTypes: {});
    expect(empty.isComplete, isTrue);
    const cookieName = 'webview_all_selective_cookie';
    const key = 'webview_all_selective_storage';
    await controller.runJavaScript(
      'document.cookie="$cookieName=keep; path=/"; localStorage.setItem("$key", "preserved");',
    );
    final cookies = await data.clearWebsiteData(
      dataTypes: {WebViewDataType.cookies},
    );
    expect(cookies.requestedDataTypes, {WebViewDataType.cookies});
    expect(cookies.isComplete, dataCaps.canClear({WebViewDataType.cookies}));
    if (cookies.isComplete) {
      expect(
        await controller.runJavaScriptReturningResult('document.cookie'),
        isNot(contains(cookieName)),
      );
    }
    expect(
      await controller.runJavaScriptReturningResult(
        'localStorage.getItem("$key")',
      ),
      contains('preserved'),
    );
    await controller.runJavaScript(
      'document.cookie="$cookieName=keep; path=/";',
    );
    final storage = await data.clearWebsiteData(
      dataTypes: {WebViewDataType.localStorage},
    );
    expect(storage.requestedDataTypes, {WebViewDataType.localStorage});
    expect(
      storage.isComplete,
      dataCaps.canClear({WebViewDataType.localStorage}),
    );
    loaded = Completer<void>();
    await controller.reload();
    await loaded.future.timeout(const Duration(seconds: 25));
    expect(
      await controller.runJavaScriptReturningResult('document.cookie'),
      contains(cookieName),
    );
    expect(
      await controller.runJavaScriptReturningResult(
        'String(localStorage.getItem("$key"))',
      ),
      contains(storage.isComplete ? 'null' : 'preserved'),
    );
    // Test data cleanup stays local to this fixture's keys.
    await controller.runJavaScript(
      'document.cookie="$cookieName=; Max-Age=0; path=/"; localStorage.removeItem("$key");',
    );
    final pending = controller.createPdf();
    await tester.pumpWidget(const SizedBox.shrink());
    await controller.platform.closeWebViewSession();
    await pending.timeout(const Duration(seconds: 5));
    expect(await controller.takeScreenshot(), isNull);
  });
}

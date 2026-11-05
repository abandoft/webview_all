import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var androidApiLevel = 0;
  if (Platform.isAndroid) {
    final result = Process.runSync('/system/bin/getprop', [
      'ro.build.version.sdk',
    ]);
    if (result.exitCode != 0) {
      throw StateError('Unable to read the Android API level.');
    }
    androidApiLevel = int.parse(result.stdout.toString().trim());
  }

  testWidgets(
    'renderer crashes do not terminate the app and views can be replaced',
    (tester) async {
      final retained = <WebViewController>[];
      for (var cycle = 0; cycle < 3; cycle++) {
        final controller = WebViewController();
        final observerless = WebViewController();
        retained.addAll([controller, observerless]);
        final loaded = Completer<void>();
        final terminated = Completer<WebResourceError>();
        final opened = Completer<void>();
        final cancelled = Completer<void>();
        final stream = StreamController<List<int>>(
          onCancel: () => cancelled.complete(),
        );
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await observerless.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setResourceDelegate(
          WebViewResourceDelegate(
            onRequest: (request) {
              if (request.path == '/index.html') {
                return WebViewResourceResponse.bytes(
                  Uint8List.fromList(
                    '<!doctype html><title>renderer recovery</title><p>ready</p>'
                        .codeUnits,
                  ),
                  mimeType: 'text/html',
                );
              }
              if (request.path == '/bytes.bin') {
                return WebViewResourceResponse.bytes(
                  Uint8List.fromList([1, 2, 3]),
                  mimeType: 'application/octet-stream',
                );
              }
              if (request.path == '/pending.bin') {
                opened.complete();
                return WebViewResourceResponse.stream(
                  stream.stream,
                  mimeType: 'application/octet-stream',
                );
              }
              return null;
            },
          ),
        );
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              if (!loaded.isCompleted) loaded.complete();
            },
            onWebResourceError: (error) {
              if (error.errorType ==
                      WebResourceErrorType.webContentProcessTerminated &&
                  !terminated.isCompleted) {
                terminated.complete(error);
              }
            },
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Column(
              children: [
                Expanded(child: WebViewWidget(controller: controller)),
                Expanded(child: WebViewWidget(controller: observerless)),
              ],
            ),
          ),
        );
        await controller.loadRequest(controller.getResourceUri('index.html')!);
        await observerless.loadHtmlString(
          '<!doctype html><p>no navigation delegate</p>',
        );
        await loaded.future.timeout(const Duration(seconds: 15));
        expect(await controller.callAsyncJavaScript('return 6 * 7;'), 42);
        final bytes = controller.getResourceUri('bytes.bin')!;
        expect(
          await controller.callAsyncJavaScript(
            'return Array.from(new Uint8Array(await (await fetch(url)).arrayBuffer()));',
            arguments: {'url': bytes.toString()},
          ),
          [1, 2, 3],
        );
        final pending = controller.getResourceUri('pending.bin')!;
        await controller.callAsyncJavaScript(
          'void fetch(url).then(response => response.arrayBuffer()).catch(() => {});',
          arguments: {'url': pending.toString()},
        );
        await opened.future.timeout(const Duration(seconds: 5));
        // Android documents this URL as an intentional renderer crash trigger.
        await controller.loadRequest(Uri.parse('chrome://crash'));
        final error = await terminated.future.timeout(
          const Duration(seconds: 15),
        );
        expect(error.isForMainFrame, isTrue);
        await cancelled.future.timeout(const Duration(seconds: 5));
        await expectLater(
          controller.callAsyncJavaScript('return 1;'),
          throwsA(isA<JavaScriptExecutionException>()),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.platform.closeWebViewSession();
        await observerless.platform.closeWebViewSession();
        await stream.close();
      }
      expect(retained, hasLength(6));
    },
    skip: androidApiLevel < 26,
  );
}

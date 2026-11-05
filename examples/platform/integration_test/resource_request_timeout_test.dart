import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import 'support/resource_test_binding.dart';

WebViewResourceResponse bytes(String value, {String mimeType = 'text/plain'}) =>
    WebViewResourceResponse.bytes(
      Uint8List.fromList(value.codeUnits),
      mimeType: mimeType,
    );

void main() {
  initializeResourceTestBinding();

  testWidgets(
    'resource deadlines cover slow callbacks and stream reads',
    (tester) async {
      final controller = WebViewController();
      final loaded = Completer<void>();
      final cancelled = Completer<void>();
      final source = StreamController<List<int>>(onCancel: cancelled.complete);
      source.add(List<int>.filled(65536, 1));
      var cancelSourceUsed = false;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.platform.closeWebViewSession();
        if (!cancelSourceUsed) await source.stream.listen((_) {}).cancel();
        await source.close();
      });
      var delayedCalls = 0;
      Stream<List<int>> slowStream() async* {
        yield 'first'.codeUnits;
        await Future<void>.delayed(const Duration(seconds: 32));
        yield 'last'.codeUnits;
      }

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
      await controller.setResourceDelegate(
        WebViewResourceDelegate(
          requestTimeout: const Duration(seconds: 45),
          onRequest: (request) async {
            switch (request.path) {
              case '/index.html':
                return bytes(
                  '<!doctype html><p>resources</p>',
                  mimeType: 'text/html',
                );
              case '/delayed':
                delayedCalls++;
                await Future<void>.delayed(const Duration(seconds: 32));
                return bytes('ready');
              case '/stream':
                return WebViewResourceResponse.stream(
                  slowStream(),
                  mimeType: 'text/plain',
                );
              case '/cancel':
                cancelSourceUsed = true;
                return WebViewResourceResponse.stream(
                  source.stream,
                  mimeType: 'application/octet-stream',
                );
              default:
                return null;
            }
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: WebViewWidget(controller: controller)),
      );
      await controller.loadRequest(controller.getResourceUri('index.html')!);
      await loaded.future.timeout(const Duration(seconds: 10));
      final supportsStreaming =
          controller.resourceCapabilities.supportsStreaming;
      final result = await controller.callAsyncJavaScript(
        '''
      const requests = [fetch(delayed).then(response => response.text())];
      if (streaming) requests.push(fetch(stream).then(response => response.text()));
      return await Promise.all(requests);
    ''',
        arguments: {
          'delayed': controller.getResourceUri('delayed')!.toString(),
          'stream': controller.getResourceUri('stream')!.toString(),
          'streaming': supportsStreaming,
        },
        timeout: const Duration(seconds: 60),
      );
      expect(result, supportsStreaming ? ['ready', 'firstlast'] : ['ready']);
      expect(delayedCalls, 1);
      if (supportsStreaming) {
        expect(
          await controller.callAsyncJavaScript(
            '''
        const abort = new AbortController();
        const response = await fetch(url, {signal: abort.signal});
        const reader = response.body.getReader();
        await reader.read();
        abort.abort();
        try { await reader.read(); return false; }
        catch (error) { return error.name === 'AbortError'; }
      ''',
            arguments: {'url': controller.getResourceUri('cancel')!.toString()},
            timeout: const Duration(seconds: 5),
          ),
          isTrue,
        );
        await cancelled.future.timeout(const Duration(seconds: 5));
      }
      await controller.setResourceDelegate(
        WebViewResourceDelegate(
          requestTimeout: const Duration(milliseconds: 200),
          onRequest: (_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return bytes('late');
          },
        ),
      );
      expect(
        await controller.callAsyncJavaScript(
          '''
      try { return !(await fetch(url)).ok; } catch (_) { return true; }
    ''',
          arguments: {'url': controller.getResourceUri('short')!.toString()},
          timeout: const Duration(seconds: 5),
        ),
        isTrue,
      );
      await controller.setResourceDelegate(
        WebViewResourceDelegate(onRequest: (_) => bytes('next')),
      );
      expect(
        await controller.callAsyncJavaScript(
          'return await (await fetch(url)).text();',
          arguments: {'url': controller.getResourceUri('next')!.toString()},
        ),
        'next',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip:
        !(Platform.isAndroid ||
            Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isLinux ||
            Platform.isWindows),
  );
}

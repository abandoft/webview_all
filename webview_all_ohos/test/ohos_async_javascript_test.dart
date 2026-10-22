import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

const MethodChannel _host = MethodChannel(
  'com.abandoft.webview_all_ohos/host_api',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Future<String?> Function(String) evaluate;
  late int cleanupCalls;

  setUp(() {
    cleanupCalls = 0;
    evaluate = (_) async => null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_host, (MethodCall call) async {
          if (call.method == 'WebView.evaluateJavascript') {
            final String source =
                (call.arguments as Map<Object?, Object?>)['javascriptString']!
                    as String;
            if (source.contains('delete window.__webviewAllAsyncResults')) {
              cleanupCalls += 1;
            }
            return evaluate(source);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_host, null);
  });

  OhosWebViewController createController() =>
      OhosWebViewController(OhosWebViewControllerCreationParams());
  Future<void> navigate(OhosWebViewController controller) =>
      controller.loadRequest(
        LoadRequestParams(uri: Uri.parse('https://example.test/next')),
      );
  Matcher navigationError() => isA<JavaScriptExecutionException>().having(
    (JavaScriptExecutionException error) => error.name,
    'name',
    'NavigationError',
  );
  final JavaScriptInvocationParams invocation = JavaScriptInvocationParams(
    functionBody: 'return await Promise.resolve(7);',
    timeout: Duration(seconds: 5),
  );
  final String fulfilled = jsonEncode(<String, Object?>{
    'state': 'fulfilled',
    'value': '7',
  });

  test(
    'navigation cancels an outstanding setup before its native callback',
    () async {
      final OhosWebViewController controller = createController();
      final Completer<void> started = Completer<void>();
      final Completer<String?> setup = Completer<String?>();
      evaluate = (_) {
        started.complete();
        return setup.future;
      };
      final Future<Object?> result = controller.callAsyncJavaScript(invocation);
      final Future<void> rejected = expectLater(
        result,
        throwsA(navigationError()),
      );
      await started.future;
      await navigate(controller);
      await rejected.timeout(const Duration(seconds: 1));
      setup.complete(null);
      await Future<void>.delayed(Duration.zero);
      expect(cleanupCalls, 0);
    },
  );

  test(
    'navigation cancels an outstanding poll and ignores its late value',
    () async {
      final OhosWebViewController controller = createController();
      final Completer<void> started = Completer<void>();
      final Completer<String?> poll = Completer<String?>();
      evaluate = (String source) async {
        if (source.contains('const value = slot && slot.result')) {
          started.complete();
          return poll.future;
        }
        return null;
      };
      final Future<Object?> result = controller.callAsyncJavaScript(invocation);
      final Future<void> rejected = expectLater(
        result,
        throwsA(navigationError()),
      );
      await started.future;
      await navigate(controller);
      await rejected.timeout(const Duration(seconds: 1));
      poll.complete(fulfilled);
      await Future<void>.delayed(Duration.zero);
      expect(cleanupCalls, 0);
    },
  );

  test(
    'rechecks navigation when a native poll and navigation finish together',
    () async {
      final OhosWebViewController controller = createController();
      final Completer<void> started = Completer<void>();
      final Completer<String?> poll = Completer<String?>();
      evaluate = (String source) async {
        if (source.contains('const value = slot && slot.result')) {
          started.complete();
          return poll.future;
        }
        return null;
      };
      final Future<Object?> result = controller.callAsyncJavaScript(invocation);
      final Future<void> rejected = expectLater(
        result,
        throwsA(navigationError()),
      );
      await started.future;
      poll.complete(fulfilled);
      await navigate(controller);
      await rejected;
    },
  );

  test(
    'unresponsive cleanup does not delay a fulfilled JavaScript result',
    () async {
      final OhosWebViewController controller = createController();
      final Completer<String?> cleanup = Completer<String?>();
      evaluate = (String source) async {
        if (source.contains('const value = slot && slot.result')) {
          return fulfilled;
        }
        if (source.contains('delete window.__webviewAllAsyncResults')) {
          return cleanup.future;
        }
        return null;
      };
      try {
        expect(
          await controller
              .callAsyncJavaScript(invocation)
              .timeout(const Duration(milliseconds: 250)),
          7,
        );
        expect(cleanupCalls, 1);
      } finally {
        cleanup.complete(null);
      }
    },
  );

  test('preserves JavaScript rejection details', () async {
    final OhosWebViewController controller = createController();
    evaluate = (String source) async =>
        source.contains('const value = slot && slot.result')
        ? jsonEncode(<String, Object?>{
            'state': 'rejected',
            'name': 'TypeError',
            'message': 'broken',
            'stack': 'test-stack',
          })
        : null;
    await expectLater(
      controller.callAsyncJavaScript(invocation),
      throwsA(
        isA<JavaScriptExecutionException>()
            .having(
              (JavaScriptExecutionException error) => error.name,
              'name',
              'TypeError',
            )
            .having(
              (JavaScriptExecutionException error) => error.message,
              'message',
              'broken',
            )
            .having(
              (JavaScriptExecutionException error) =>
                  error.javaScriptStackTrace,
              'stack',
              'test-stack',
            ),
      ),
    );
  });
}

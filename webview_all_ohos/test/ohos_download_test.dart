import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

const host = MethodChannel('com.abandoft.webview_all_ohos/host_api');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final controllers = <OhosWebViewController>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, null);
    for (final controller in controllers) {
      MethodChannel(
        'com.abandoft.webview_all_ohos/download/${controller.webViewIdentifier}',
      ).setMethodCallHandler(null);
    }
    controllers.clear();
  });
  OhosWebViewController controller() {
    final value = OhosWebViewController(OhosWebViewControllerCreationParams());
    controllers.add(value);
    return value;
  }

  Future<Object?> send(
    OhosWebViewController controller,
    String method,
    Map<String, Object?> values,
  ) async {
    final reply = Completer<ByteData?>();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'com.abandoft.webview_all_ohos/download/${controller.webViewIdentifier}',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, values),
          ),
          reply.complete,
        );
    final bytes = await reply.future;
    return bytes == null
        ? null
        : const StandardMethodCodec().decodeEnvelope(bytes);
  }

  test(
    'native download decisions preserve metadata without reloading',
    () async {
      final value = controller();
      final requests = <WebViewDownloadRequest>[];
      final progress = <WebViewDownloadProgress>[];
      final results = <WebViewDownloadResult>[];
      await value.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (request) {
            requests.add(request);
            return const WebViewDownloadDecision.saveToFile('/data/chosen.txt');
          },
          onDownloadProgress: progress.add,
          onDownloadResult: results.add,
        ),
      );
      final decision =
          await send(value, 'request', <String, Object?>{
                'id': 'native-guid',
                'url': 'blob:attachment',
                'suggestedFilename': 'report.txt',
                'mimeType': 'text/plain',
              })
              as Map;
      expect(decision['action'], 'saveToFile');
      expect(decision['path'], '/data/chosen.txt');
      expect(requests.single.contentLength, isNull);
      expect(requests.single.userAgent, isNull);
      expect(requests.single.suggestedFilename, 'report.txt');
      await send(value, 'progress', <String, Object?>{
        'id': 'native-guid',
        'bytesReceived': 9,
      });
      await send(value, 'result', <String, Object?>{
        'id': 'native-guid',
        'status': 'completed',
        'path': '/data/chosen.txt',
      });
      expect(progress.single.totalBytes, isNull);
      expect(results.single.status, WebViewDownloadStatus.completed);
      expect(results.single.path, '/data/chosen.txt');
      expect(calls.where((call) => call.method == 'WebView.loadUrl'), isEmpty);
      await value.setDownloadDelegate(null);
      expect(
        calls
            .where((call) => call.method == 'WebView.setDownloadDelegate')
            .last
            .arguments,
        <String, Object?>{
          'instanceId': value.webViewIdentifier,
          'enabled': false,
        },
      );
    },
  );
  test(
    'application exceptions cancel instead of replaying a request',
    () async {
      final value = controller();
      final results = <WebViewDownloadResult>[];
      await value.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) =>
              throw StateError('application download failure'),
          onDownloadResult: results.add,
        ),
      );
      final decision =
          await send(value, 'request', <String, Object?>{
                'id': 'failed',
                'url': 'https://example.test/attachment',
              })
              as Map;
      expect(decision['action'], 'cancel');
      expect(decision['error'], contains('application download failure'));
      for (var i = 0; i < 2; i++) {
        await send(value, 'result', <String, Object?>{
          'id': 'failed',
          'status': 'failed',
          'errorCode': 'download_decision_failed',
        });
      }
      expect(results, hasLength(1));
      expect(calls.where((call) => call.method == 'WebView.loadUrl'), isEmpty);
    },
  );
  test(
    'disposal cancels pending handlers and ignores late decisions',
    () async {
      final value = controller();
      final decision = Completer<WebViewDownloadDecision>();
      final results = <WebViewDownloadResult>[];
      await value.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) => decision.future,
          onDownloadResult: results.add,
        ),
      );
      final pending = send(value, 'request', <String, Object?>{
        'id': 'pending',
        'url': 'https://example.test/attachment',
      });
      await Future<void>.delayed(Duration.zero);
      await send(value, 'disposed', <String, Object?>{});
      expect(results.single.status, WebViewDownloadStatus.cancelled);
      decision.complete(const WebViewDownloadDecision.platformDefault());
      final response = await pending as Map;
      expect(response['action'], 'cancel');
      expect(results, hasLength(1));
      await expectLater(value.setDownloadDelegate(null), throwsStateError);
    },
  );

  test('replacing a delegate cancels only its undecided requests', () async {
    final value = controller();
    final decision = Completer<WebViewDownloadDecision>();
    final previousResults = <WebViewDownloadResult>[];
    final nextResults = <WebViewDownloadResult>[];
    await value.setDownloadDelegate(
      WebViewDownloadDelegate(
        onDownloadRequest: (_) => decision.future,
        onDownloadResult: previousResults.add,
      ),
    );
    final pending = send(value, 'request', <String, Object?>{
      'id': 'replacement',
      'url': 'https://example.test/attachment',
    });
    await Future<void>.delayed(Duration.zero);
    await value.setDownloadDelegate(
      WebViewDownloadDelegate(
        onDownloadRequest: (_) =>
            const WebViewDownloadDecision.platformDefault(),
        onDownloadResult: nextResults.add,
      ),
    );
    final response = await pending.timeout(const Duration(seconds: 1)) as Map;
    expect(response['action'], 'cancel');
    expect(response['error'], isNull);
    await send(value, 'result', <String, Object?>{
      'id': 'replacement',
      'status': 'cancelled',
    });
    expect(previousResults.single.status, WebViewDownloadStatus.cancelled);
    expect(nextResults, isEmpty);
    decision.complete(const WebViewDownloadDecision.platformDefault());
  });

  test(
    'stale native configuration failures preserve the current delegate',
    () async {
      final value = controller();
      WebViewDownloadDelegate delegate(WebViewDownloadDecision decision) =>
          WebViewDownloadDelegate(onDownloadRequest: (_) => decision);
      await value.setDownloadDelegate(
        delegate(const WebViewDownloadDecision.cancel()),
      );
      final blocked = Completer<Object?>();
      var configurations = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(host, (call) async {
            if (call.method == 'WebView.setDownloadDelegate' &&
                configurations++ == 0) {
              return blocked.future;
            }
            return null;
          });
      final stale = value.setDownloadDelegate(
        delegate(const WebViewDownloadDecision.handledExternally()),
      );
      final staleError = expectLater(stale, throwsA(isA<PlatformException>()));
      await Future<void>.delayed(Duration.zero);
      await value.setDownloadDelegate(
        delegate(const WebViewDownloadDecision.platformDefault()),
      );
      blocked.completeError(PlatformException(code: 'stale_configuration'));
      await staleError;
      final response =
          await send(value, 'request', <String, Object?>{
                'id': 'latest-handler',
                'url': 'https://example.test/attachment',
              })
              as Map;
      expect(response['action'], 'platformDefault');
      await send(value, 'disposed', <String, Object?>{});
    },
  );

  test(
    'native setup failures are observable before an application decision',
    () async {
      final value = controller();
      final results = <WebViewDownloadResult>[];
      var decisions = 0;
      await value.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) {
            decisions++;
            return const WebViewDownloadDecision.cancel();
          },
          onDownloadResult: results.add,
        ),
      );
      for (var i = 0; i < 2; i++) {
        await send(value, 'result', <String, Object?>{
          'id': 'setup-failure',
          'status': 'failed',
          'errorCode': 'temporary_file_failed',
        });
      }
      expect(decisions, 0);
      expect(results.single.errorCode, 'temporary_file_failed');
    },
  );

  test(
    'native failure releases a pending application decision immediately',
    () async {
      final value = controller();
      final application = Completer<WebViewDownloadDecision>();
      final results = <WebViewDownloadResult>[];
      await value.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) => application.future,
          onDownloadResult: results.add,
        ),
      );
      final pending = send(value, 'request', <String, Object?>{
        'id': 'network-failure',
        'url': 'https://example.test/attachment',
      });
      await Future<void>.delayed(Duration.zero);
      await send(value, 'result', <String, Object?>{
        'id': 'network-failure',
        'status': 'failed',
        'errorCode': 'network',
      });
      final response = await pending.timeout(const Duration(seconds: 1)) as Map;
      expect(response['action'], 'cancel');
      expect(response['error'], isNull);
      expect(results.single.status, WebViewDownloadStatus.failed);
      application.completeError(StateError('late application failure'));
      await Future<void>.delayed(Duration.zero);
      await send(value, 'disposed', <String, Object?>{});
    },
  );
}

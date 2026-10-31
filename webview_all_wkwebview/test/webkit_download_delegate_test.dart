import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_wkwebview/src/common/webkit_download_delegate.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const registration = MethodChannel(
    'com.abandoft.webview_all_wkwebview/downloads',
  );
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  Future<Object?> native(String method, Map<String, Object?> args) async {
    final result = Completer<ByteData?>();
    await messenger.handlePlatformMessage(
      'com.abandoft.webview_all_wkwebview/downloads/42',
      codec.encodeMethodCall(MethodCall(method, args)),
      result.complete,
    );
    final value = await result.future;
    return value == null ? null : codec.decodeEnvelope(value);
  }

  Map<String, Object?> request(String id) => <String, Object?>{
    'id': id,
    'url': 'https://example.test/attachment',
    'suggestedFilename': 'report.txt',
    'contentLength': -1,
    'supportedActions': <String>['cancel', 'saveToFile', 'handledExternally'],
  };

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(registration, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(registration, null);
  });

  test(
    'keeps unknown metadata null and returns the selected file target',
    () async {
      WebViewDownloadRequest? received;
      final bridge = WebKitDownloadDelegateBridge(
        42,
        WebViewDownloadDelegate(
          onDownloadRequest: (value) {
            received = value;
            return const WebViewDownloadDecision.saveToFile('/tmp/report.txt');
          },
        ),
      );
      await bridge.enable();
      expect(await native('request', request('one')), <String, Object?>{
        'action': 'saveToFile',
        'path': '/tmp/report.txt',
      });
      expect(received!.contentLength, isNull);
      expect(received!.mimeType, isNull);
      expect(received!.suggestedFilename, 'report.txt');
      expect(
        received!.supportedActions,
        isNot(contains(WebViewDownloadAction.platformDefault)),
      );
      await bridge.close();
      expect(calls.map((call) => call.arguments['enabled']), <bool>[
        true,
        false,
      ]);
    },
  );

  test('unsupported decisions cancel with an explicit failure', () async {
    final bridge = WebKitDownloadDelegateBridge(
      42,
      WebViewDownloadDelegate(
        onDownloadRequest: (_) =>
            const WebViewDownloadDecision.platformDefault(),
      ),
    );
    await bridge.enable();
    final reply = await native('request', request('unsupported')) as Map;
    expect(reply['action'], 'cancel');
    expect(reply['errorCode'], 'download_decision_failed');
    await bridge.close();
  });

  test(
    'forwards progress and one result without treating handoff as saved',
    () async {
      final progress = <WebViewDownloadProgress>[];
      final results = <WebViewDownloadResult>[];
      final bridge = WebKitDownloadDelegateBridge(
        42,
        WebViewDownloadDelegate(
          onDownloadRequest: (_) =>
              const WebViewDownloadDecision.handledExternally(),
          onDownloadProgress: progress.add,
          onDownloadResult: results.add,
        ),
      );
      await bridge.enable();
      await native('request', request('handoff'));
      await native('progress', <String, Object?>{
        'id': 'handoff',
        'bytesReceived': 12,
        'totalBytes': 20,
      });
      final result = <String, Object?>{'id': 'handoff', 'status': 'handedOff'};
      await native('result', result);
      await native('result', result);
      await native('progress', <String, Object?>{
        'id': 'handoff',
        'bytesReceived': 20,
        'totalBytes': 20,
      });
      expect(progress, hasLength(1));
      expect(results, hasLength(1));
      expect(results.single.status, WebViewDownloadStatus.handedOff);
      expect(results.single.path, isNull);
      await bridge.close();
    },
  );

  test(
    'late asynchronous decisions cannot start a closed view download',
    () async {
      final decision = Completer<WebViewDownloadDecision>();
      final bridge = WebKitDownloadDelegateBridge(
        42,
        WebViewDownloadDelegate(onDownloadRequest: (_) => decision.future),
      );
      await bridge.enable();
      final pending = native('request', request('late'));
      await Future<void>.delayed(Duration.zero);
      await bridge.close();
      decision.complete(
        const WebViewDownloadDecision.saveToFile('/tmp/late.txt'),
      );
      expect(await pending, <String, Object?>{'action': 'cancel'});
    },
  );

  test(
    'unsupported operating systems fail registration without a live handler',
    () async {
      messenger.setMockMethodCallHandler(registration, (_) async {
        throw PlatformException(code: 'not_supported');
      });
      final bridge = WebKitDownloadDelegateBridge(
        42,
        WebViewDownloadDelegate(
          onDownloadRequest: (_) => const WebViewDownloadDecision.cancel(),
        ),
      );
      await expectLater(bridge.enable(), throwsA(isA<PlatformException>()));
      expect(await native('request', request('unsupported-os')), isNull);
      await bridge.close();
    },
  );

  test(
    'accepted transfers keep their owner after delegate replacement and removal',
    () async {
      final oldResults = <WebViewDownloadResult>[];
      final newResults = <WebViewDownloadResult>[];
      WebViewDownloadDelegate handler(List<WebViewDownloadResult> results) =>
          WebViewDownloadDelegate(
            onDownloadRequest: (_) =>
                const WebViewDownloadDecision.saveToFile('/tmp/owned.txt'),
            onDownloadResult: results.add,
          );
      final bridge = WebKitDownloadDelegateBridge(42, handler(oldResults));
      await bridge.enable();
      await native('request', request('old'));
      await bridge.update(handler(newResults));
      await native('result', <String, Object?>{
        'id': 'old',
        'status': 'completed',
        'path': '/tmp/owned.txt',
      });
      expect(oldResults.single.status, WebViewDownloadStatus.completed);
      expect(newResults, isEmpty);
      await native('request', request('new'));
      await bridge.update(null);
      await native('result', <String, Object?>{
        'id': 'new',
        'status': 'completed',
        'path': '/tmp/owned.txt',
      });
      expect(newResults.single.status, WebViewDownloadStatus.completed);
      expect(await native('request', request('no-handler')), <String, Object?>{
        'action': 'cancel',
      });
      await bridge.close();
    },
  );

  test(
    'replacement cancels pending decisions and rejects old native generations',
    () async {
      final choice = Completer<WebViewDownloadDecision>();
      var newRequests = 0;
      final bridge = WebKitDownloadDelegateBridge(
        42,
        WebViewDownloadDelegate(onDownloadRequest: (_) => choice.future),
      );
      await bridge.enable();
      final pending = native('request', request('pending'));
      await Future<void>.delayed(Duration.zero);
      await bridge.update(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) {
            newRequests++;
            return const WebViewDownloadDecision.cancel();
          },
        ),
      );
      expect(await pending, <String, Object?>{'action': 'cancel'});
      expect(
        await native('request', <String, Object?>{
          ...request('stale'),
          'generation': 1,
        }),
        <String, Object?>{'action': 'cancel'},
      );
      expect(newRequests, 0);
      choice.complete(
        const WebViewDownloadDecision.saveToFile('/tmp/late.txt'),
      );
      await bridge.close();
    },
  );
}

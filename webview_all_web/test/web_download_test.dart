import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:web/web.dart' as web;
import 'package:webview_all_web/webview_all_web.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'web_webview_controller_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockHttpRequestFactory factory;
  late WebWebViewController controller;
  late WebWebViewControllerCreationParams params;
  late List<web.HTMLAnchorElement> anchors;
  late JSFunction clickListener;

  setUp(() {
    factory = MockHttpRequestFactory();
    params = WebWebViewControllerCreationParams(httpRequestFactory: factory);
    controller = WebWebViewController(params);
    anchors = [];
    clickListener = ((web.Event event) {
      final target = event.target;
      if (target != null && (target as web.Element).tagName == 'A') {
        final anchor = target as web.HTMLAnchorElement;
        if (anchor.download.isNotEmpty) {
          event.preventDefault();
          anchors.add(anchor);
        }
      }
    }).toJS;
    web.document.addEventListener('click', clickListener);
    when(
      factory.request(
        any,
        method: anyNamed('method'),
        requestHeaders: anyNamed('requestHeaders'),
        sendData: anyNamed('sendData'),
      ),
    ).thenAnswer(
      (_) async => web.Response(
        'original response'.toJS,
        web.ResponseInit(
          headers:
              <String, String>{
                    'content-type': 'text/plain',
                    'content-disposition':
                        "attachment; filename*=UTF-8''report%20one.txt",
                  }.jsify()!
                  as web.HeadersInit,
        ),
      ),
    );
  });
  tearDown(() {
    web.document.removeEventListener('click', clickListener);
  });

  test(
    'POST attachment downloads original bytes without navigating or adding history',
    () async {
      await controller.loadHtmlString(
        '<p>original page</p>',
        baseUrl: 'https://example.test/original',
      );
      final originalFrame = params.iFrame.getAttribute('src');
      final results = <WebViewDownloadResult>[];
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (request) {
            expect(request.suggestedFilename, 'report one.txt');
            expect(
              request.supportedActions,
              isNot(contains(WebViewDownloadAction.saveToFile)),
            );
            return const WebViewDownloadDecision.platformDefault();
          },
          onDownloadResult: results.add,
        ),
      );
      final body = Uint8List.fromList([1, 2, 3]);
      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/attachment'),
          method: LoadRequestMethod.post,
          body: body,
          headers: {'Authorization': 'test'},
        ),
      );
      expect(anchors, hasLength(1));
      expect(anchors.single.download, 'report one.txt');
      final response = await web.window.fetch(anchors.single.href.toJS).toDart;
      expect((await response.text().toDart).toDart, 'original response');
      expect(await controller.currentUrl(), 'https://example.test/original');
      expect(params.iFrame.getAttribute('src'), originalFrame);
      expect(await controller.canGoBack(), isFalse);
      expect(results.single.status, WebViewDownloadStatus.handedOff);
      verify(
        factory.request(
          'https://example.test/attachment',
          method: 'post',
          requestHeaders: {'Authorization': 'test'},
          sendData: body,
        ),
      ).called(1);
    },
  );

  test(
    'header GET attachments also work without a download delegate',
    () async {
      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/attachment'),
          headers: {'X-Test': 'yes'},
        ),
      );
      expect(anchors, hasLength(1));
      expect(await controller.currentUrl(), isNull);
      expect(await controller.canGoBack(), isFalse);
    },
  );

  test(
    'cancelled or unsupported decisions never start a second request',
    () async {
      final results = <WebViewDownloadResult>[];
      for (final decision in [
        const WebViewDownloadDecision.cancel(),
        const WebViewDownloadDecision.saveToFile('/tmp/not-supported'),
      ]) {
        await controller.setDownloadDelegate(
          WebViewDownloadDelegate(
            onDownloadRequest: (_) => decision,
            onDownloadResult: results.add,
          ),
        );
        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.test/attachment'),
            method: LoadRequestMethod.post,
          ),
        );
      }
      expect(anchors, isEmpty);
      expect(results.map((result) => result.status), [
        WebViewDownloadStatus.cancelled,
        WebViewDownloadStatus.failed,
      ]);
      verify(
        factory.request(
          any,
          method: 'post',
          requestHeaders: anyNamed('requestHeaders'),
          sendData: anyNamed('sendData'),
        ),
      ).called(2);
    },
  );

  test(
    'attachment handling respects an explicit sandbox download restriction',
    () async {
      await controller.setIFrameSandbox('allow-scripts');
      final results = <WebViewDownloadResult>[];
      var requests = 0;
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) {
            requests++;
            return const WebViewDownloadDecision.platformDefault();
          },
          onDownloadResult: results.add,
        ),
      );
      await controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/attachment'),
          method: LoadRequestMethod.post,
        ),
      );
      expect(requests, 0);
      expect(anchors, isEmpty);
      expect(results.single.status, WebViewDownloadStatus.failed);
    },
  );

  test(
    'replacing the delegate releases a pending decision without downloading',
    () async {
      final pending = Completer<WebViewDownloadDecision>();
      final called = Completer<void>();
      final result = Completer<WebViewDownloadResult>();
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) {
            called.complete();
            return pending.future;
          },
          onDownloadResult: result.complete,
        ),
      );
      final loading = controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/attachment'),
          method: LoadRequestMethod.post,
        ),
      );
      await called.future;
      await controller.setDownloadDelegate(null);
      await loading;
      expect((await result.future).status, WebViewDownloadStatus.cancelled);
      expect(anchors, isEmpty);
      pending.complete(const WebViewDownloadDecision.platformDefault());
    },
  );

  test('page navigation does not cancel an identified attachment', () async {
    final pending = Completer<WebViewDownloadDecision>();
    final called = Completer<void>();
    final results = <WebViewDownloadResult>[];
    await controller.setDownloadDelegate(
      WebViewDownloadDelegate(
        onDownloadRequest: (_) {
          called.complete();
          return pending.future;
        },
        onDownloadResult: results.add,
      ),
    );
    final loading = controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.test/attachment'),
        method: LoadRequestMethod.post,
      ),
    );
    await called.future;
    await controller.loadHtmlString(
      '<p>next page</p>',
      baseUrl: 'https://example.test/next',
    );
    final nextFrame = params.iFrame.getAttribute('src');
    pending.complete(const WebViewDownloadDecision.platformDefault());
    await loading;
    expect(anchors, hasLength(1));
    expect(results.single.status, WebViewDownloadStatus.handedOff);
    expect(await controller.currentUrl(), 'https://example.test/next');
    expect(params.iFrame.getAttribute('src'), nextFrame);
    expect(await controller.canGoBack(), isFalse);
  });

  test(
    'accepted body retains its delegate across replacement and navigation',
    () async {
      final body = Completer<web.Blob>();
      final reading = Completer<void>();
      final response = web.Response(
        'ignored'.toJS,
        web.ResponseInit(
          headers:
              <String, String>{
                    'content-disposition': 'attachment; filename=delayed.txt',
                  }.jsify()!
                  as web.HeadersInit,
        ),
      );
      response.setProperty(
        'blob'.toJS,
        (() {
          reading.complete();
          return body.future.toJS;
        }).toJS,
      );
      when(
        factory.request(
          any,
          method: anyNamed('method'),
          requestHeaders: anyNamed('requestHeaders'),
          sendData: anyNamed('sendData'),
        ),
      ).thenAnswer((_) async => response);
      final originalResults = <WebViewDownloadResult>[];
      final newResults = <WebViewDownloadResult>[];
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) =>
              const WebViewDownloadDecision.platformDefault(),
          onDownloadResult: originalResults.add,
        ),
      );
      final loading = controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/attachment'),
          method: LoadRequestMethod.post,
        ),
      );
      await reading.future;
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) => throw StateError('Unexpected new request'),
          onDownloadResult: newResults.add,
        ),
      );
      await controller.loadHtmlString(
        '<p>next</p>',
        baseUrl: 'https://example.test/next',
      );
      body.complete(web.Blob(<JSAny>['original response'.toJS].toJS));
      await loading;
      expect(anchors, hasLength(1));
      expect(originalResults.single.status, WebViewDownloadStatus.handedOff);
      expect(newResults, isEmpty);
      expect(await controller.currentUrl(), 'https://example.test/next');
    },
  );
}

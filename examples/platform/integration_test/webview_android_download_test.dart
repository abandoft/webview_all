import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android download notifications, decisions and navigation fallback',
    (tester) async {
      final requests = <Map<String, String>>[];
      const payload = 'original Android download response';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          try {
            final body = await utf8.decoder.bind(request).join();
            requests.add({
              'path': request.uri.path,
              'method': request.method,
              'body': body,
              'header': request.headers.value('X-Download-Test') ?? '',
              'cookie': request.headers.value('Cookie') ?? '',
            });
            if (request.uri.path == '/page') {
              request.response.headers.contentType = ContentType.html;
              request.response.headers.add(
                'Set-Cookie',
                'download_auth=retained; Path=/; HttpOnly',
              );
              request.response.write('<title>Android download origin</title>');
            } else {
              request.response.headers.set('Content-Type', 'text/plain');
              request.response.headers.set(
                'Content-Disposition',
                'attachment; filename="report.txt"',
              );
              request.response.contentLength = payload.length;
              request.response.write(payload);
            }
            await request.response.close();
          } on HttpException {
            // Notification-only downloads may close the original response early.
          } on SocketException {
            // The session can close while the server is writing a response.
          }
        }),
      );
      final origin = Uri.parse('http://127.0.0.1:${server.port}/');
      final session = await OffscreenWebViewSession.create();
      addTearDown(session.close);
      final controller = session.controller;
      final loaded = Completer<void>();
      final navigationRequests = <String>[];
      Future<void> installNavigationDelegate() =>
          controller.setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (url) {
                if (url == origin.resolve('page').toString() &&
                    !loaded.isCompleted) {
                  loaded.complete();
                }
              },
              onNavigationRequest: (request) {
                navigationRequests.add(request.url);
                return NavigationDecision.prevent;
              },
            ),
          );
      final notifications = <WebViewDownloadRequest>[];
      final results = <WebViewDownloadResult>[];
      var next = Completer<WebViewDownloadResult>();
      var seen = Completer<void>();
      var decision = const WebViewDownloadDecision.cancel();
      Completer<WebViewDownloadDecision>? pending;
      var failDecision = false;
      final delegate = WebViewDownloadDelegate(
        onDownloadRequest: (request) {
          notifications.add(request);
          if (!seen.isCompleted) seen.complete();
          expect(request.supportedActions, {
            WebViewDownloadAction.cancel,
            WebViewDownloadAction.handledExternally,
          });
          expect(request.suggestedFilename, 'report.txt');
          expect(request.mimeType, 'text/plain');
          expect(request.contentLength, payload.length);
          expect(request.userAgent, isNotEmpty);
          if (failDecision) throw StateError('Application decision failed');
          return pending?.future ?? decision;
        },
        onDownloadResult: (result) {
          results.add(result);
          if (!next.isCompleted) next.complete(result);
        },
      );
      await controller.setDownloadDelegate(delegate);
      await installNavigationDelegate();
      await controller.loadRequest(origin.resolve('page'));
      await loaded.future.timeout(const Duration(seconds: 20));

      await controller.loadRequest(
        origin.resolve('attachment'),
        headers: {'X-Download-Test': 'retained'},
      );
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.cancelled,
      );
      final get = requests.singleWhere((r) => r['path'] == '/attachment');
      expect(get['header'], 'retained');
      expect(get['cookie'], contains('download_auth=retained'));
      expect(
        navigationRequests,
        isEmpty,
        reason:
            'A download delegate suppresses the legacy download navigation callback.',
      );

      next = Completer<WebViewDownloadResult>();
      decision = const WebViewDownloadDecision.handledExternally();
      await installNavigationDelegate();
      await controller.loadRequest(
        origin.resolve('post'),
        method: LoadRequestMethod.post,
        body: Uint8List.fromList(utf8.encode('original-post-body')),
      );
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.handedOff,
      );
      final post = requests.where((r) => r['path'] == '/post').toList();
      expect(post, hasLength(1));
      expect(post.single['method'], 'POST');
      expect(post.single['body'], 'original-post-body');
      expect(post.single['cookie'], contains('download_auth=retained'));

      next = Completer<WebViewDownloadResult>();
      decision = const WebViewDownloadDecision.saveToFile('/unsupported.txt');
      await controller.loadRequest(origin.resolve('unsupported'));
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.failed,
      );
      expect(requests.where((r) => r['path'] == '/unsupported'), hasLength(1));

      next = Completer<WebViewDownloadResult>();
      failDecision = true;
      await controller.loadRequest(origin.resolve('failed-decision'));
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.failed,
      );
      failDecision = false;

      next = Completer<WebViewDownloadResult>();
      seen = Completer<void>();
      pending = Completer<WebViewDownloadDecision>();
      await controller.loadRequest(origin.resolve('replacement'));
      await seen.future.timeout(const Duration(seconds: 20));
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) =>
              throw StateError('No new request is expected'),
        ),
      );
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.cancelled,
      );
      pending.complete(const WebViewDownloadDecision.handledExternally());
      pending = null;

      final legacy = Completer<String>();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!legacy.isCompleted) legacy.complete(request.url);
            return NavigationDecision.prevent;
          },
        ),
      );
      await controller.setDownloadDelegate(null);
      await controller.loadRequest(origin.resolve('legacy'));
      expect(
        await legacy.future.timeout(const Duration(seconds: 20)),
        origin.resolve('legacy').toString(),
      );
      expect(requests.where((r) => r['path'] == '/legacy'), hasLength(1));

      next = Completer<WebViewDownloadResult>();
      seen = Completer<void>();
      pending = Completer<WebViewDownloadDecision>();
      await controller.setDownloadDelegate(delegate);
      await controller.loadRequest(origin.resolve('close'));
      await seen.future.timeout(const Duration(seconds: 20));
      await session.close();
      expect(
        (await next.future.timeout(const Duration(seconds: 20))).status,
        WebViewDownloadStatus.cancelled,
      );
      pending.complete(const WebViewDownloadDecision.handledExternally());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(notifications, hasLength(6));
      expect(results, hasLength(6));
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip: !Platform.isAndroid,
  );
}

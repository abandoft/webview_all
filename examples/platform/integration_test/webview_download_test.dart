import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

// Run in a separate process: native environments outlive individual views.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'downloads preserve requests and never replace existing files',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'webview-download-test-',
      );
      // Native profiles stay open until process exit. Keep this directory until
      // then, just as the separate environment integration test does.
      if (Platform.isWindows) {
        await WindowsWebViewController.ensureEnvironment(
          userDataPath: '${root.path}/profile',
        );
      } else if (Platform.isLinux) {
        await LinuxWebViewController.ensureEnvironment(
          userDataPath: '${root.path}/profile',
          cachePath: '${root.path}/cache',
        );
      }

      final payload = 'native attachment response\n${'x' * 65536}';
      final activePayload = 'native active response\n${'a' * 2097152}';
      final activeRelease = Completer<void>();
      final raceRelease = Completer<void>();
      addTearDown(() {
        if (!activeRelease.isCompleted) activeRelease.complete();
        if (!raceRelease.isCompleted) raceRelease.complete();
      });
      final requests = <Map<String, String>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          try {
            final body = await utf8.decoder.bind(request).join();
            requests.add(<String, String>{
              'path': request.uri.path,
              'method': request.method,
              'body': body,
              'header': request.headers.value('X-Download-Test') ?? '',
              'cookie': request.headers.value('cookie') ?? '',
            });
            if (request.uri.path == '/page') {
              request.response.headers.contentType = ContentType.html;
              request.response.headers.add(
                'Set-Cookie',
                'download_auth=retained; Path=/; HttpOnly',
              );
              request.response.write('<title>download origin</title>');
            } else {
              request.response.headers.set('Content-Type', 'text/plain');
              request.response.headers.set(
                'Content-Disposition',
                'attachment; filename="report.txt"',
              );
              request.response.contentLength = request.uri.path == '/active'
                  ? activePayload.length
                  : payload.length;
              if (request.uri.path == '/active') {
                // Deliver bytes after the native download observer is installed.
                // A single small initial chunk may be buffered before that.
                const chunkSize = 32768;
                const pauseAt = 1048576;
                for (var offset = 0; offset < pauseAt; offset += chunkSize) {
                  request.response.write(
                    activePayload.substring(offset, offset + chunkSize),
                  );
                  await request.response.flush();
                  await Future<void>.delayed(const Duration(milliseconds: 50));
                }
                await activeRelease.future;
                request.response.write(activePayload.substring(pauseAt));
              } else if (request.uri.path == '/race') {
                request.response.write(payload.substring(0, 32768));
                await request.response.flush();
                await raceRelease.future;
                request.response.write(payload.substring(32768));
              } else {
                request.response.write(payload);
              }
            }
            await request.response.close();
          } on HttpException {
            // Cancellation can close a response while the server is writing it.
          } on SocketException {
            // The session may close its connection during teardown.
          }
        }),
      );
      final origin = Uri.parse('http://127.0.0.1:${server.port}/');
      final session = await OffscreenWebViewSession.create();
      addTearDown(session.close);
      final controller = session.controller;
      final results = <WebViewDownloadResult>[];
      final errors = <WebResourceError>[];
      var next = Completer<WebViewDownloadResult>();
      var target = '${root.path}/saved.txt';
      var action = WebViewDownloadAction.saveToFile;
      var pending = Completer<void>();
      Completer<WebViewDownloadDecision>? deferredDecision;
      Future<void>? concurrentWriter;
      Completer<void>? activeProgress;
      var expectedResultCount = 8;

      final downloadDelegate = WebViewDownloadDelegate(
        onDownloadRequest: (request) async {
          expect(request.id, isNotEmpty);
          expect(request.supportedActions, contains(action));
          if (!pending.isCompleted) pending.complete();
          final deferred = deferredDecision;
          if (deferred != null) return deferred.future;
          if (action == WebViewDownloadAction.cancel) {
            return const WebViewDownloadDecision.cancel();
          }
          if (action == WebViewDownloadAction.handledExternally) {
            return const WebViewDownloadDecision.handledExternally();
          }
          if (request.url.endsWith('/race')) {
            final path = target;
            concurrentWriter =
                Future<void>.delayed(const Duration(milliseconds: 60)).then((
                  _,
                ) async {
                  await File(path).writeAsString('concurrent sentinel');
                  raceRelease.complete();
                });
          }
          return WebViewDownloadDecision.saveToFile(target);
        },
        onDownloadResult: (result) {
          results.add(result);
          if (!next.isCompleted) next.complete(result);
        },
        onDownloadProgress: (progress) {
          final pendingProgress = activeProgress;
          if (progress.bytesReceived > 0 &&
              pendingProgress != null &&
              !pendingProgress.isCompleted) {
            pendingProgress.complete();
          }
        },
      );
      await controller.setDownloadDelegate(downloadDelegate);

      var loaded = Completer<void>();
      Future<void> installNavigationDelegate() =>
          controller.setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (_) => NavigationDecision.navigate,
              onWebResourceError: errors.add,
              onPageFinished: (url) {
                if (url == origin.resolve('page').toString() &&
                    !loaded.isCompleted) {
                  loaded.complete();
                }
              },
            ),
          );
      // Setting and replacing navigation handling must not remove download
      // handling, or cause the original POST below to be replayed as a GET.
      await installNavigationDelegate();
      await controller.loadRequest(origin.resolve('page'));
      await loaded.future.timeout(const Duration(seconds: 20));
      expect(await controller.getTitle(), 'download origin');

      await controller.loadRequest(origin.resolve('attachment'));
      final saved = await next.future.timeout(const Duration(seconds: 25));
      expect(saved.status, WebViewDownloadStatus.completed);
      expect(await File(target).readAsString(), payload);

      next = Completer<WebViewDownloadResult>();
      await controller.loadRequest(origin.resolve('existing'));
      expect(
        (await next.future.timeout(const Duration(seconds: 25))).status,
        WebViewDownloadStatus.failed,
      );
      expect(await File(target).readAsString(), payload);

      next = Completer<WebViewDownloadResult>();
      action = WebViewDownloadAction.cancel;
      await controller.loadRequest(origin.resolve('cancel'));
      expect(
        (await next.future.timeout(const Duration(seconds: 25))).status,
        WebViewDownloadStatus.cancelled,
      );

      if (Platform.isWindows ||
          Platform.isLinux ||
          Platform.isMacOS ||
          Platform.isIOS) {
        expectedResultCount++;
        next = Completer<WebViewDownloadResult>();
        action = WebViewDownloadAction.saveToFile;
        target = '${root.path}/active.txt';
        activeProgress = Completer<void>();
        await controller.loadRequest(origin.resolve('active'));
        await activeProgress.future.timeout(const Duration(seconds: 25));
        var replacementRequests = 0;
        final replacementResults = <WebViewDownloadResult>[];
        await controller.setDownloadDelegate(
          WebViewDownloadDelegate(
            onDownloadRequest: (_) {
              replacementRequests++;
              return const WebViewDownloadDecision.cancel();
            },
            onDownloadResult: replacementResults.add,
          ),
        );
        activeRelease.complete();
        expect(
          (await next.future.timeout(const Duration(seconds: 25))).status,
          WebViewDownloadStatus.completed,
        );
        expect(await File(target).readAsString(), activePayload);
        expect(replacementRequests, 0);
        expect(replacementResults, isEmpty);
        activeProgress = null;
        await controller.setDownloadDelegate(downloadDelegate);
      }

      next = Completer<WebViewDownloadResult>();
      action = WebViewDownloadAction.saveToFile;
      target = '${root.path}/post.txt';
      await installNavigationDelegate();
      await controller.loadRequest(
        origin.resolve('post'),
        method: LoadRequestMethod.post,
        headers: <String, String>{'X-Download-Test': 'retained'},
        body: Uint8List.fromList(utf8.encode('original-post-body')),
      );
      expect(
        (await next.future.timeout(const Duration(seconds: 25))).status,
        WebViewDownloadStatus.completed,
      );
      expect(await File(target).readAsString(), payload);
      final post = requests
          .where((request) => request['path'] == '/post')
          .toList();
      expect(post, hasLength(1));
      expect(post.single['method'], 'POST');
      expect(post.single['body'], 'original-post-body');
      expect(post.single['header'], 'retained');
      expect(post.single['cookie'], contains('download_auth=retained'));

      // Linux's custom-method path uses Soup with WebKit profile cookies.
      // A caller-supplied Cookie header must still take precedence.
      if (Platform.isLinux) {
        expectedResultCount++;
        next = Completer<WebViewDownloadResult>();
        target = '${root.path}/explicit-cookie.txt';
        await controller.loadRequest(
          origin.resolve('explicit-cookie'),
          method: LoadRequestMethod.post,
          headers: <String, String>{'Cookie': 'manual_cookie=retained'},
          body: Uint8List.fromList(utf8.encode('explicit-cookie-body')),
        );
        expect(
          (await next.future.timeout(const Duration(seconds: 25))).status,
          WebViewDownloadStatus.completed,
        );
        expect(await File(target).readAsString(), payload);
        final explicitCookie = requests.singleWhere(
          (request) => request['path'] == '/explicit-cookie',
        );
        expect(explicitCookie['method'], 'POST');
        expect(explicitCookie['body'], 'explicit-cookie-body');
        expect(explicitCookie['cookie'], 'manual_cookie=retained');
      }

      next = Completer<WebViewDownloadResult>();
      target = '${root.path}/race.txt';
      await controller.loadRequest(origin.resolve('race'));
      expect(
        (await next.future.timeout(const Duration(seconds: 25))).status,
        WebViewDownloadStatus.failed,
      );
      await concurrentWriter;
      expect(await File(target).readAsString(), 'concurrent sentinel');

      next = Completer<WebViewDownloadResult>();
      action = WebViewDownloadAction.handledExternally;
      await controller.loadRequest(origin.resolve('external'));
      expect(
        (await next.future.timeout(const Duration(seconds: 25))).status,
        WebViewDownloadStatus.handedOff,
      );

      next = Completer<WebViewDownloadResult>();
      action = WebViewDownloadAction.saveToFile;
      pending = Completer<void>();
      deferredDecision = Completer<WebViewDownloadDecision>();
      target = '${root.path}/replacement.txt';
      await controller.loadRequest(origin.resolve('pending-replacement'));
      await pending.future.timeout(const Duration(seconds: 15));
      await controller.setDownloadDelegate(
        WebViewDownloadDelegate(
          onDownloadRequest: (_) => const WebViewDownloadDecision.cancel(),
        ),
      );
      expect(
        (await next.future.timeout(const Duration(seconds: 15))).status,
        WebViewDownloadStatus.cancelled,
      );
      deferredDecision.complete(WebViewDownloadDecision.saveToFile(target));
      expect(await File(target).exists(), isFalse);
      deferredDecision = null;
      await controller.setDownloadDelegate(downloadDelegate);

      next = Completer<WebViewDownloadResult>();
      action = WebViewDownloadAction.saveToFile;
      pending = Completer<void>();
      deferredDecision = Completer<WebViewDownloadDecision>();
      target = '${root.path}/late.txt';
      await controller.loadRequest(origin.resolve('late'));
      await pending.future.timeout(const Duration(seconds: 15));
      await session.close();
      expect(
        (await next.future.timeout(const Duration(seconds: 15))).status,
        WebViewDownloadStatus.cancelled,
      );
      deferredDecision.complete(WebViewDownloadDecision.saveToFile(target));
      expect(await File(target).exists(), isFalse);
      expect(results, hasLength(expectedResultCount));
      expect(errors, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 3)),
    skip:
        !Platform.isWindows &&
        !Platform.isLinux &&
        !Platform.isMacOS &&
        !Platform.isIOS,
  );
}

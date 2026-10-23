// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:web/web.dart' as web;
import 'package:webview_platform_interface/webview_platform_interface.dart';
import 'package:webview_all_web/webview_all_web.dart';

import 'web_webview_controller_test.mocks.dart';

@JS('Object.defineProperty')
external JSObject _defineProperty(
  JSObject object,
  JSString property,
  JSObject descriptor,
);

@GenerateMocks(
  <Type>[],
  customMocks: <MockSpec<Object>>[
    MockSpec<HttpRequestFactory>(onMissingStub: OnMissingStub.returnDefault),
  ],
)
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  group('WebWebViewController', () {
    group('WebWebViewControllerCreationParams', () {
      test('sets iFrame fields', () {
        final params = WebWebViewControllerCreationParams();

        expect(params.iFrame.id, startsWith('webview_all_web_'));
        expect(params.iFrame.style.width, '100%');
        expect(params.iFrame.style.height, '100%');
        expect(params.iFrame.style.borderStyle, 'none');
        expect(params.iFrame.style.borderWidth, '0px');
      });

      test('applies custom iFrame attributes', () {
        final params = WebWebViewControllerCreationParams(
          iFrameAllow: 'camera',
          iFrameSandbox: 'allow-scripts',
          iFrameReferrerPolicy: 'no-referrer',
          iFrameAttributes: const <String, String?>{
            'allow': 'fullscreen',
            'title': 'Embedded preview',
          },
        );

        expect(params.iFrame.getAttribute('allow'), 'fullscreen');
        expect(params.iFrame.getAttribute('sandbox'), 'allow-scripts');
        expect(params.iFrame.getAttribute('referrerpolicy'), 'no-referrer');
        expect(params.iFrame.getAttribute('title'), 'Embedded preview');
      });

      test('rejects empty custom iFrame attribute names', () {
        expect(
          () => WebWebViewControllerCreationParams(
            iFrameAttributes: const <String, String?>{'': 'value'},
          ),
          throwsArgumentError,
        );
      });

      test(
        'rejects attributes reserved for controller identity and loading',
        () {
          for (final String name in <String>['id', 'ID', 'src', 'srcdoc']) {
            expect(
              () => WebWebViewControllerCreationParams(
                iFrameAttributes: <String, String?>{name: 'value'},
              ),
              throwsArgumentError,
            );
          }
        },
      );

      test('rejects malformed custom iFrame attribute names', () {
        for (final String name in <String>[
          'bad name',
          'bad=name',
          'bad/name',
        ]) {
          expect(
            () => WebWebViewControllerCreationParams(
              iFrameAttributes: <String, String?>{name: 'value'},
            ),
            throwsArgumentError,
          );
        }
      });
    });

    group('loadHtmlString', () {
      test('loadHtmlString loads html into iframe srcdoc', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await controller.loadHtmlString('test html');
        expect(
          (controller.params as WebWebViewControllerCreationParams).iFrame
              .getAttribute('srcdoc'),
          'test html',
        );
      });

      test('loadHtmlString keeps logical current URL', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await controller.loadHtmlString(
          '<p>content</p>',
          baseUrl: 'https://example.com/base/',
        );

        expect(await controller.currentUrl(), 'https://example.com/base/');
      });

      test('loadHtmlString preserves raw HTML in srcdoc', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await controller.loadHtmlString('#');
        expect(
          (controller.params as WebWebViewControllerCreationParams).iFrame
              .getAttribute('srcdoc'),
          '#',
        );
      });

      test(
        'keeps sandboxed inline HTML isolated while exposing controller APIs',
        () async {
          final params = WebWebViewControllerCreationParams(
            iFrameSandbox: 'allow-scripts allow-forms',
          );
          final controller = WebWebViewController(params);
          addTearDown(() {
            params.iFrame.remove();
          });
          web.document.body!.append(params.iFrame);

          final Future<web.Event> load = params.iFrame.onLoad.first;
          await controller.loadHtmlString(
            '<title>Sandboxed</title><main id="value">safe</main>',
          );
          await load;

          expect(
            () => params.iFrame.contentWindow!.document,
            throwsA(anything),
          );
          expect(await controller.getTitle(), 'Sandboxed');
          expect(
            await controller.runJavaScriptReturningResult(
              'document.getElementById("value").textContent',
            ),
            'safe',
          );
          expect(
            await controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: 'await Promise.resolve(); return left + right;',
                arguments: const <String, Object?>{'left': 19, 'right': 23},
              ),
            ),
            42,
          );
          await expectLater(
            controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: 'await new Promise(() => {});',
                timeout: const Duration(milliseconds: 50),
              ),
            ),
            throwsA(isA<TimeoutException>()),
          );
        },
      );

      test('does not install a bridge when sandbox blocks scripts', () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: 'allow-forms',
        );
        final controller = WebWebViewController(params);

        await controller.loadHtmlString('<p>content</p>');

        expect(
          params.iFrame.getAttribute('srcdoc'),
          isNot(contains('isolatedBridgeReady')),
        );
      });

      test('restores the isolated bridge after document.open', () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: 'allow-scripts',
        );
        final controller = WebWebViewController(params);
        final changes = <ScrollPositionChange>[];
        final messages = <JavaScriptMessage>[];
        addTearDown(() => params.iFrame.remove());
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnScrollPositionChange(changes.add);
        await controller.addJavaScriptChannel(
          JavaScriptChannelParams(
            name: 'LifecycleChannel',
            onMessageReceived: messages.add,
          ),
        );

        for (final bool closeDocument in <bool>[false, true]) {
          await controller.runJavaScript(
            _rewriteCurrentDocumentScript(closeDocument: closeDocument),
          );
          expect(
            await controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: 'await Promise.resolve(); return 6 * 7;',
                timeout: const Duration(seconds: 1),
              ),
            ),
            42,
          );
          expect(await controller.getTitle(), 'Scrollable');
          await controller.runJavaScript(
            'LifecycleChannel.postMessage("$closeDocument");',
          );
          expect(await controller.runJavaScriptReturningResult('1 + 1'), 2);
          final double expectedY = closeDocument ? 160 : 80;
          changes.clear();
          await controller.scrollTo(0, expectedY.toInt());
          await _waitForScrollChange(changes, expectedY);
          expect(await controller.getScrollPosition(), Offset(0, expectedY));
          expect(
            changes.map((ScrollPositionChange change) => change.y),
            contains(expectedY),
          );
          changes.clear();
          await controller.runJavaScript(
            'window.dispatchEvent(new Event("scroll"));',
          );
          expect(changes, hasLength(1));
        }
        expect(
          messages.map((JavaScriptMessage message) => message.message),
          <String>['false', 'true'],
        );
        expect(
          messages.every(
            (JavaScriptMessage message) => message.isMainFrame == true,
          ),
          isTrue,
        );
        expect(
          messages.map((JavaScriptMessage message) => message.sourceOrigin),
          everyElement('null'),
        );
        expect(() => params.iFrame.contentWindow!.document, throwsA(anything));
      });
    });

    group('isolated message ports', () {
      test(
        'allows initial operations before an unclosed document loads',
        () async {
          final params = WebWebViewControllerCreationParams(
            iFrameSandbox: 'allow-scripts',
          );
          final controller = WebWebViewController(params);
          addTearDown(() => params.iFrame.remove());
          web.document.body!.append(params.iFrame);
          await controller.loadHtmlString('<script>document.open();</script>');
          expect(
            await controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: 'return 6 * 7;',
                timeout: const Duration(seconds: 1),
              ),
            ),
            42,
          );
        },
      );

      test('installs hooks when reload makes the iframe accessible', () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: 'allow-scripts',
        );
        final controller = WebWebViewController(params);
        final messages = <JavaScriptMessage>[];
        addTearDown(() => params.iFrame.remove());
        await controller.addJavaScriptChannel(
          JavaScriptChannelParams(
            name: 'ReloadChannel',
            onMessageReceived: messages.add,
          ),
        );
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setIFrameSandbox('allow-scripts allow-same-origin');
        final Future<web.Event> reloaded = params.iFrame.onLoad.first;
        await controller.callAsyncJavaScript(
          JavaScriptInvocationParams(
            functionBody: '''
            setTimeout(function() { location.reload(); }, 25);
            return 'scheduled';
          ''',
          ),
        );
        await reloaded;
        expect(params.iFrame.contentWindow!.document.title, 'Scrollable');
        await controller.runJavaScript(
          'ReloadChannel.postMessage("accessible")',
        );
        for (int i = 0; i < 40 && messages.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(messages.map((message) => message.message), <String>[
          'accessible',
        ]);
        expect(messages.single.sourceOrigin, web.window.location.origin);
      });

      for (final bool fetchedData in <bool>[false, true]) {
        test('reconnects after page-initiated reload ($fetchedData)', () async {
          final params = WebWebViewControllerCreationParams(
            httpRequestFactory: MockHttpRequestFactory(),
            iFrameSandbox: fetchedData ? null : 'allow-scripts',
          );
          final controller = WebWebViewController(params);
          final messages = <JavaScriptMessage>[];
          final changes = <ScrollPositionChange>[];
          addTearDown(() => params.iFrame.remove());
          await controller.addJavaScriptChannel(
            JavaScriptChannelParams(
              name: 'ReloadChannel',
              onMessageReceived: messages.add,
            ),
          );
          await controller.setOnScrollPositionChange(changes.add);
          await _attachAndLoadReloadableHtml(
            controller,
            params,
            fetchedData: fetchedData,
          );
          expect(await controller.runJavaScriptReturningResult('6 * 7'), 42);

          final Future<web.Event> reloaded = params.iFrame.onLoad.first;
          await controller.callAsyncJavaScript(
            JavaScriptInvocationParams(
              functionBody: '''
              setTimeout(function() { location.reload(); }, 25);
              return 'scheduled';
            ''',
            ),
          );
          await reloaded;
          expect(
            await controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: 'return 6 * 7;',
                timeout: const Duration(seconds: 1),
              ),
            ),
            42,
          );
          expect(await controller.getTitle(), 'Reloadable');
          await controller.runJavaScript(
            'ReloadChannel.postMessage("reloaded")',
          );
          for (int i = 0; i < 40 && messages.isEmpty; i += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(messages.map((message) => message.message), <String>[
            'reloaded',
          ]);
          expect(messages.single.sourceOrigin, 'null');
          await controller.scrollTo(0, 80);
          await _waitForScrollChange(changes, 80);
          expect(changes.last.y, 80);
        });

        test(
          'keeps same-document requests and invalidates reload requests ($fetchedData)',
          () async {
            final params = WebWebViewControllerCreationParams(
              httpRequestFactory: MockHttpRequestFactory(),
              iFrameSandbox: fetchedData ? null : 'allow-scripts',
            );
            final controller = WebWebViewController(params);
            final requests = <PlatformWebViewPermissionRequest>[];
            addTearDown(() => params.iFrame.remove());
            await _attachAndLoadReloadableHtml(
              controller,
              params,
              fetchedData: fetchedData,
            );
            await controller.setOnPlatformPermissionRequest(requests.add);
            final Future<Object?> operation = controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: '''
              window.operationStarted = true;
              await new Promise(function() {});
              return 'old document';
            ''',
              ),
            );
            bool operationInvalidated = false;
            final Future<void> invalidated =
                expectLater(
                  operation,
                  throwsA(isA<JavaScriptExecutionException>()),
                ).then<void>((_) {
                  operationInvalidated = true;
                });
            expect(
              await _waitForJavaScriptValue(
                controller,
                'Boolean(window.operationStarted)',
                isTrue,
              ),
              isTrue,
            );
            const String startPermission = '''
            window.permissionResult = 'pending';
            navigator.mediaDevices.getUserMedia({video: true}).then(
              function() { window.permissionResult = 'granted'; },
              function(error) { window.permissionResult = error.name; }
            );
          ''';
            await controller.runJavaScript(startPermission);
            for (int i = 0; i < 40 && requests.isEmpty; i += 1) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            expect(requests, hasLength(1));
            final Future<web.Event> rewritten = params.iFrame.onLoad.first;
            await controller.runJavaScript(
              _rewriteCurrentDocumentScript(closeDocument: true),
            );
            await rewritten;
            expect(await controller.getTitle(), 'Reloadable');
            expect(operationInvalidated, isFalse);
            await requests.single.deny();
            expect(
              await _waitForJavaScriptValue(
                controller,
                'window.permissionResult',
                isNot('pending'),
              ),
              'NotAllowedError',
            );

            await controller.runJavaScript('document.open();');
            final Future<web.Event> emptyClosed = params.iFrame.onLoad.first;
            await controller.runJavaScript(
              'document.open(); document.close();',
            );
            await emptyClosed;
            expect(
              await controller.callAsyncJavaScript(
                JavaScriptInvocationParams(functionBody: 'return 6 * 7;'),
              ),
              42,
            );
            expect(operationInvalidated, isFalse);

            await controller.runJavaScript(startPermission);
            for (int i = 0; i < 40 && requests.length < 2; i += 1) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            expect(requests, hasLength(2));
            final Future<web.Event> reloaded = params.iFrame.onLoad.first;
            await controller.callAsyncJavaScript(
              JavaScriptInvocationParams(
                functionBody: '''
              setTimeout(function() { location.reload(); }, 25);
              return 'scheduled';
            ''',
              ),
            );
            await reloaded;
            expect(await controller.getTitle(), 'Reloadable');
            await invalidated.timeout(const Duration(seconds: 1));
            await controller.runJavaScript(startPermission);
            for (int i = 0; i < 40 && requests.length < 3; i += 1) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            expect(requests, hasLength(3));
            await requests[1].grant();
            await Future<void>.delayed(const Duration(milliseconds: 25));
            expect(
              await controller.runJavaScriptReturningResult(
                'window.permissionResult',
              ),
              'pending',
            );
            await requests[2].deny();
            expect(
              await _waitForJavaScriptValue(
                controller,
                'window.permissionResult',
                isNot('pending'),
              ),
              'NotAllowedError',
            );
          },
        );
      }

      test(
        'keeps operations working across empty document.open calls',
        () async {
          final params = WebWebViewControllerCreationParams(
            iFrameSandbox: 'allow-scripts',
          );
          final controller = WebWebViewController(params);
          addTearDown(() => params.iFrame.remove());
          await _attachAndLoadScrollableHtml(controller, params);

          await controller.runJavaScript('document.open();');
          for (int i = 1; i <= 3; i += 1) {
            expect(
              await controller.callAsyncJavaScript(
                JavaScriptInvocationParams(
                  functionBody: '''
                  document.open();
                  window.operationCount = (window.operationCount || 0) + 1;
                  return document.childNodes.length;
                ''',
                  timeout: const Duration(seconds: 1),
                ),
              ),
              0,
            );
            expect(
              await controller.runJavaScriptReturningResult(
                'window.operationCount',
              ),
              i,
            );
          }
          expect(await controller.getTitle(), isNull);
        },
      );

      test('rejects stale and duplicate isolated port handshakes', () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: 'allow-scripts',
        );
        final controller = WebWebViewController(params);
        addTearDown(() => params.iFrame.remove());
        await _attachAndLoadScrollableHtml(controller, params);
        expect(await controller.runJavaScriptReturningResult('6 * 7'), 42);
        final String bootstrap = params.iFrame.getAttribute('srcdoc')!;
        final int generation = int.parse(
          RegExp(r'const generation = (\d+);').firstMatch(bootstrap)!.group(1)!,
        );
        final Object documentId = await controller.runJavaScriptReturningResult(
          'window.__webviewAllDocumentId',
        );

        for (final int spoofGeneration in <int>[-1, generation]) {
          await controller.runJavaScript('''
            (function() {
              const channel = new MessageChannel();
              channel.port1.onmessage = function(event) {
                const data = event.data;
                channel.port1.postMessage(Object.assign({}, data, {
                  __webview_all_type: 'isolatedBridgeResponse',
                  ok: true,
                  result: 'wrong-port'
                }));
              };
              window.parent.postMessage({
                __webview_all_type: 'isolatedBridgeReady',
                webViewId: ${jsonEncode(params.iFrame.id)},
                generation: $spoofGeneration,
                documentId: ${jsonEncode(documentId)}
              }, '*', [channel.port2]);
            })();
          ''');
          expect(await controller.runJavaScriptReturningResult('6 * 7'), 42);
        }
      });

      test('rejects same-origin handshakes during opaque navigation', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() => params.iFrame.remove());
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setIFrameSandbox('allow-scripts');
        final Future<web.Event> loaded = params.iFrame.onLoad.first;
        await controller.loadHtmlString('<title>Opaque destination</title>');
        final int generation = int.parse(
          RegExp(
            r'const generation = (\d+);',
          ).firstMatch(params.iFrame.getAttribute('srcdoc')!)!.group(1)!,
        );

        // Navigation has not committed yet. This old, still-accessible Window
        // has the same source/id/generation, but its real origin is not opaque.
        expect(params.iFrame.contentWindow!.document.body, isNotNull);
        await controller.runJavaScript('''
          (function() {
            const channel = new MessageChannel();
            channel.port1.onmessage = function(event) {
              channel.port1.postMessage(Object.assign({}, event.data, {
                __webview_all_type: 'isolatedBridgeResponse',
                ok: true,
                result: 'wrong-origin'
              }));
            };
            window.parent.postMessage({
              __webview_all_type: 'isolatedBridgeReady',
              webViewId: ${jsonEncode(params.iFrame.id)},
              generation: $generation,
              documentId: 'wrong-origin-document'
            }, '*', [channel.port2]);
          })();
        ''');
        await loaded;
        expect(
          await controller.callAsyncJavaScript(
            JavaScriptInvocationParams(
              functionBody: 'return 6 * 7;',
              timeout: const Duration(seconds: 1),
            ),
          ),
          42,
        );
        expect(await controller.getTitle(), 'Opaque destination');
      });

      test('invalidates pending isolated operations on navigation', () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: 'allow-scripts',
        );
        final controller = WebWebViewController(params);
        addTearDown(() => params.iFrame.remove());
        await _attachAndLoadScrollableHtml(controller, params);
        final Future<Object?> pending = controller.callAsyncJavaScript(
          JavaScriptInvocationParams(
            functionBody: '''
            window.operationStarted = true;
            await new Promise(function() {});
            return 'old document';
          ''',
          ),
        );
        final Future<void> invalidated = expectLater(
          pending,
          throwsA(isA<JavaScriptExecutionException>()),
        );
        expect(
          await _waitForJavaScriptValue(
            controller,
            'Boolean(window.operationStarted)',
            isTrue,
          ),
          isTrue,
        );
        final Future<web.Event> loaded = params.iFrame.onLoad.first;
        await controller.loadHtmlString('<title>New document</title>');
        await loaded;
        await invalidated;
        expect(await controller.getTitle(), 'New document');
        expect(await controller.runJavaScriptReturningResult('6 * 7'), 42);
      });
    });

    group('loadRequest', () {
      test('throws ArgumentError on missing scheme', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await expectLater(
          () async => controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('flutter.dev')),
          ),
          throwsA(const TypeMatcher<ArgumentError>()),
        );
      });

      test('skips XHR for simple GETs (no headers, no data)', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );

        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenThrow(
          StateError('The `request` method should not have been called.'),
        );

        await controller.loadRequest(
          LoadRequestParams(uri: Uri.parse('https://flutter.dev')),
        );

        expect(
          (controller.params as WebWebViewControllerCreationParams).iFrame.src,
          'https://flutter.dev/',
        );
        expect(await controller.currentUrl(), 'https://flutter.dev');
      });

      test('makes request and loads response into iframe', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );

        final fakeResponse = web.Response(
          'test data'.toJS,
          <String, Object>{
                'headers': <String, Object>{'content-type': 'text/plain'},
              }.jsify()!
              as web.ResponseInit,
        );

        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://flutter.dev'),
            method: LoadRequestMethod.post,
            body: Uint8List.fromList('test body'.codeUnits),
            headers: const <String, String>{'Foo': 'Bar'},
          ),
        );

        verify(
          mockHttpRequestFactory.request(
            'https://flutter.dev',
            method: 'post',
            requestHeaders: <String, String>{'Foo': 'Bar'},
            sendData: Uint8List.fromList('test body'.codeUnits),
          ),
        );

        expect(
          Uri.parse(
            (controller.params as WebWebViewControllerCreationParams)
                .iFrame
                .src,
          ).data!.contentAsString(),
          'test data',
        );
        expect(await controller.currentUrl(), 'https://flutter.dev');
      });

      test('preserves binary response bytes', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final params = WebWebViewControllerCreationParams(
          httpRequestFactory: mockHttpRequestFactory,
        );
        final controller = WebWebViewController(params);
        final Uint8List bytes = Uint8List.fromList(<int>[0, 255, 216, 0, 1]);
        final web.Response fakeResponse = web.Response(
          bytes.toJS,
          <String, Object>{
                'headers': <String, Object>{
                  'content-type': 'application/octet-stream',
                },
              }.jsify()!
              as web.ResponseInit,
        );
        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) async => fakeResponse);

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.test/binary'),
            method: LoadRequestMethod.post,
          ),
        );

        final UriData data = Uri.parse(params.iFrame.src).data!;
        expect(data.mimeType, 'application/octet-stream');
        expect(data.contentAsBytes(), bytes);
      });

      test('uses the final response URL after redirects', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final params = WebWebViewControllerCreationParams(
          httpRequestFactory: mockHttpRequestFactory,
        );
        final controller = WebWebViewController(params);
        final WebNavigationDelegate delegate = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        final List<String?> changedUrls = <String?>[];
        final List<String> navigationRequests = <String>[];
        final web.Response fakeResponse = web.Response(
          '<main>redirected</main>'.toJS,
          <String, Object>{
                'headers': <String, Object>{'content-type': 'text/html'},
              }.jsify()!
              as web.ResponseInit,
        );
        _defineProperty(
          fakeResponse,
          'url'.toJS,
          <String, Object>{'value': 'https://example.test/final/'}.jsify()!
              as JSObject,
        );
        await delegate.setOnUrlChange(
          (UrlChange change) => changedUrls.add(change.url),
        );
        await delegate.setOnNavigationRequest((NavigationRequest request) {
          navigationRequests.add(request.url);
          return NavigationDecision.navigate;
        });
        await controller.setPlatformNavigationDelegate(delegate);
        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) async => fakeResponse);

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.test/original'),
            method: LoadRequestMethod.post,
          ),
        );

        expect(await controller.currentUrl(), 'https://example.test/final/');
        expect(changedUrls.last, 'https://example.test/final/');
        expect(navigationRequests, <String>[
          'https://example.test/original',
          'https://example.test/final/',
        ]);
        expect(
          Uri.parse(params.iFrame.src).data!.contentAsString(),
          contains('<base href="https://example.test/final/">'),
        );
      });

      test('can reject the final URL after a fetch redirect', () async {
        final MockHttpRequestFactory requestFactory = MockHttpRequestFactory();
        final WebWebViewControllerCreationParams params =
            WebWebViewControllerCreationParams(
              httpRequestFactory: requestFactory,
            );
        final WebWebViewController controller = WebWebViewController(params);
        final WebNavigationDelegate delegate = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        final List<String?> changedUrls = <String?>[];
        final web.Response response = web.Response('<main>blocked</main>'.toJS);
        _defineProperty(
          response,
          'url'.toJS,
          <String, Object>{'value': 'https://blocked.example/final'}.jsify()!
              as JSObject,
        );
        when(
          requestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) async => response);
        await delegate.setOnNavigationRequest(
          (NavigationRequest request) => request.url.contains('blocked.example')
              ? NavigationDecision.prevent
              : NavigationDecision.navigate,
        );
        await delegate.setOnUrlChange(
          (UrlChange change) => changedUrls.add(change.url),
        );
        await controller.setPlatformNavigationDelegate(delegate);

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.test/original'),
            method: LoadRequestMethod.post,
          ),
        );

        expect(params.iFrame.src, isEmpty);
        expect(await controller.currentUrl(), isNull);
        expect(await controller.canGoBack(), isFalse);
        expect(changedUrls, <String?>['https://example.test/original', null]);
      });

      test('reports HTTP status errors with request and response', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );
        final delegate = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        final List<HttpResponseError> errors = <HttpResponseError>[];
        final fakeResponse = web.Response(
          'not found'.toJS,
          <String, Object>{
                'status': 404,
                'statusText': 'Not Found',
                'headers': <String, Object>{
                  'content-type': 'text/plain',
                  'x-test': 'yes',
                },
              }.jsify()!
              as web.ResponseInit,
        );

        await delegate.setOnHttpError(errors.add);
        await controller.setPlatformNavigationDelegate(delegate);
        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://flutter.dev/missing'),
            method: LoadRequestMethod.post,
            headers: const <String, String>{'Accept': 'text/plain'},
          ),
        );

        expect(errors, hasLength(1));
        expect(
          errors.single.request?.uri,
          Uri.parse('https://flutter.dev/missing'),
        );
        expect(errors.single.request, isA<WebWebResourceRequest>());
        final WebWebResourceRequest request =
            errors.single.request! as WebWebResourceRequest;
        expect(request.method, 'POST');
        expect(request.headers, const <String, String>{'Accept': 'text/plain'});
        expect(request.isForMainFrame, isTrue);
        expect(
          errors.single.response?.uri,
          Uri.parse('https://flutter.dev/missing'),
        );
        expect(errors.single.response, isA<WebWebResourceResponse>());
        final WebWebResourceResponse response =
            errors.single.response! as WebWebResourceResponse;
        expect(errors.single.response?.statusCode, 404);
        expect(errors.single.response?.headers, const <String, String>{
          'content-type': 'text/plain',
          'x-test': 'yes',
        });
        expect(response.mimeType, 'text/plain');
        expect(response.reasonPhrase, 'Not Found');
      });

      test('parses content-type response header correctly', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );

        final Encoding iso = Encoding.getByName('latin1')!;

        final fakeResponse = web.Response(
          Uint8List.fromList(iso.encode('España')).toJS,
          <String, Object>{
                'headers': <String, Object>{
                  'content-type': 'Text/HTmL; charset=latin1',
                },
              }.jsify()!
              as web.ResponseInit,
        );

        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://flutter.dev'),
            method: LoadRequestMethod.post,
          ),
        );

        expect(
          (controller.params as WebWebViewControllerCreationParams).iFrame.src,
          allOf(
            startsWith('data:text/html;charset=iso-8859-1,'),
            contains('Espa%F1a'),
            contains('isolatedBridgeReady'),
          ),
        );
      });

      test('ignores valid extension content-type parameters', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );
        final fakeResponse = web.Response(
          'profiled'.toJS,
          <String, Object>{
                'headers': <String, Object>{
                  'content-type':
                      'text/plain; profile="https://example.test/a=b"',
                },
              }.jsify()!
              as web.ResponseInit,
        );
        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://example.test/profiled'),
            method: LoadRequestMethod.post,
          ),
        );

        expect(
          Uri.parse(
            (controller.params as WebWebViewControllerCreationParams)
                .iFrame
                .src,
          ).data!.contentAsString(),
          'profiled',
        );
      });

      test(
        'keeps fetched HTML isolated while exposing controlled WebView APIs',
        () async {
          final mockHttpRequestFactory = MockHttpRequestFactory();
          final params = WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          );
          final controller = WebWebViewController(params);
          final List<String> channelMessages = <String>[];
          JavaScriptMessage? receivedChannelMessage;
          addTearDown(() {
            params.iFrame.remove();
          });
          web.document.body!.append(params.iFrame);
          final fakeResponse = web.Response(
            '''
<!doctype html>
<html>
  <head><title>Fetched page</title></head>
  <body style="height: 2000px"><a id="relative" href="next">next</a></body>
</html>
'''
                .toJS,
            <String, Object>{
                  'headers': <String, Object>{
                    'content-type': 'text/html; charset=utf-8',
                  },
                }.jsify()!
                as web.ResponseInit,
          );
          when(
            mockHttpRequestFactory.request(
              any,
              method: anyNamed('method'),
              requestHeaders: anyNamed('requestHeaders'),
              sendData: anyNamed('sendData'),
            ),
          ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

          final Future<web.Event> load = params.iFrame.onLoad.first;
          await controller.loadRequest(
            LoadRequestParams(
              uri: Uri.parse('https://example.test/base/page'),
              method: LoadRequestMethod.post,
              headers: const <String, String>{'X-Test': 'yes'},
            ),
          );
          await load;

          expect(
            () => params.iFrame.contentWindow!.document,
            throwsA(anything),
          );
          expect(await controller.getTitle(), 'Fetched page');
          expect(
            await controller.runJavaScriptReturningResult(
              'document.getElementById("relative").href',
            ),
            'https://example.test/base/next',
          );

          await controller.addJavaScriptChannel(
            JavaScriptChannelParams(
              name: 'FetchedChannel',
              onMessageReceived: (JavaScriptMessage message) {
                channelMessages.add(message.message);
                receivedChannelMessage = message;
              },
            ),
          );
          await controller.runJavaScript(
            'FetchedChannel.postMessage("isolated")',
          );
          for (int i = 0; i < 20 && channelMessages.isEmpty; i += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(channelMessages, <String>['isolated']);
          expect(receivedChannelMessage!.sourceOrigin, 'null');
          expect(receivedChannelMessage!.sourceUrl, isNull);
          expect(receivedChannelMessage!.isMainFrame, isTrue);

          await controller.scrollTo(0, 120);
          expect((await controller.getScrollPosition()).dy, 120);
        },
      );

      test('escapes "#" correctly', () async {
        final mockHttpRequestFactory = MockHttpRequestFactory();
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: mockHttpRequestFactory,
          ),
        );

        final fakeResponse = web.Response(
          '#'.toJS,
          <String, Object>{
                'headers': <String, Object>{'content-type': 'text/html'},
              }.jsify()!
              as web.ResponseInit,
        );

        when(
          mockHttpRequestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer((_) => Future<web.Response>.value(fakeResponse));

        await controller.loadRequest(
          LoadRequestParams(
            uri: Uri.parse('https://flutter.dev'),
            method: LoadRequestMethod.post,
            body: Uint8List.fromList('test body'.codeUnits),
            headers: const <String, String>{'Foo': 'Bar'},
          ),
        );

        expect(
          (controller.params as WebWebViewControllerCreationParams).iFrame.src,
          contains('%23'),
        );
      });

      test(
        'reports XHR request failures as main-frame resource errors',
        () async {
          final mockHttpRequestFactory = MockHttpRequestFactory();
          final controller = WebWebViewController(
            WebWebViewControllerCreationParams(
              httpRequestFactory: mockHttpRequestFactory,
            ),
          );
          final delegate = WebNavigationDelegate(
            const WebNavigationDelegateCreationParams(),
          );
          WebResourceError? resourceError;

          await delegate.setOnWebResourceError((WebResourceError error) {
            resourceError = error;
          });
          await controller.setPlatformNavigationDelegate(delegate);

          when(
            mockHttpRequestFactory.request(
              any,
              method: anyNamed('method'),
              requestHeaders: anyNamed('requestHeaders'),
              sendData: anyNamed('sendData'),
            ),
          ).thenThrow(StateError('network down'));

          await expectLater(
            () => controller.loadRequest(
              LoadRequestParams(
                uri: Uri.parse('https://flutter.dev'),
                method: LoadRequestMethod.post,
              ),
            ),
            throwsStateError,
          );

          expect(resourceError, isNotNull);
          expect(resourceError!.isForMainFrame, isTrue);
          expect(resourceError!.errorType, WebResourceErrorType.connect);
          expect(resourceError!.url, 'https://flutter.dev');
        },
      );

      test(
        'prevents delegated simple GET navigation before state changes',
        () async {
          final mockHttpRequestFactory = MockHttpRequestFactory();
          final controller = WebWebViewController(
            WebWebViewControllerCreationParams(
              httpRequestFactory: mockHttpRequestFactory,
            ),
          );
          final delegate = WebNavigationDelegate(
            const WebNavigationDelegateCreationParams(),
          );
          final List<NavigationRequest> navigationRequests =
              <NavigationRequest>[];
          final List<String> pageStarts = <String>[];
          final List<String?> urlChanges = <String?>[];
          final List<int> progressValues = <int>[];

          await delegate.setOnNavigationRequest((NavigationRequest request) {
            navigationRequests.add(request);
            return NavigationDecision.prevent;
          });
          await delegate.setOnPageStarted(pageStarts.add);
          await delegate.setOnUrlChange((UrlChange change) {
            urlChanges.add(change.url);
          });
          await delegate.setOnProgress(progressValues.add);
          await controller.setPlatformNavigationDelegate(delegate);

          await controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('https://flutter.dev/prevented')),
          );

          expect(navigationRequests, hasLength(1));
          expect(
            navigationRequests.single.url,
            'https://flutter.dev/prevented',
          );
          expect(navigationRequests.single.isMainFrame, isTrue);
          expect(await controller.currentUrl(), isNull);
          expect(
            (controller.params as WebWebViewControllerCreationParams)
                .iFrame
                .src,
            isEmpty,
          );
          expect(pageStarts, isEmpty);
          expect(urlChanges, isEmpty);
          expect(progressValues, isEmpty);
          verifyNever(
            mockHttpRequestFactory.request(
              any,
              method: anyNamed('method'),
              requestHeaders: anyNamed('requestHeaders'),
              sendData: anyNamed('sendData'),
            ),
          );
        },
      );
    });

    group('controller-managed history', () {
      test(
        'restores URL and inline HTML entries without stale srcdoc',
        () async {
          final WebWebViewControllerCreationParams params =
              WebWebViewControllerCreationParams();
          final WebWebViewController controller = WebWebViewController(params);

          await controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('https://example.test/first')),
          );
          await controller.loadHtmlString(
            '<main>inline history entry</main>',
            baseUrl: 'https://example.test/inline/',
          );

          expect(await controller.canGoBack(), isTrue);
          expect(
            params.iFrame.getAttribute('srcdoc'),
            contains('inline history'),
          );

          await controller.goBack();

          expect(await controller.currentUrl(), 'https://example.test/first');
          expect(params.iFrame.getAttribute('srcdoc'), isNull);
          expect(params.iFrame.src, 'https://example.test/first');
          expect(await controller.canGoForward(), isTrue);

          await controller.goForward();

          expect(await controller.currentUrl(), 'https://example.test/inline/');
          expect(
            params.iFrame.getAttribute('srcdoc'),
            contains('inline history'),
          );
        },
      );

      test(
        'restores fetch responses without replaying POST requests',
        () async {
          final MockHttpRequestFactory requestFactory =
              MockHttpRequestFactory();
          final WebWebViewControllerCreationParams params =
              WebWebViewControllerCreationParams(
                httpRequestFactory: requestFactory,
              );
          final WebWebViewController controller = WebWebViewController(params);
          final web.Response response = web.Response(
            '<main>saved response</main>'.toJS,
            <String, Object>{
                  'headers': <String, Object>{
                    'content-type': 'text/html; charset=utf-8',
                  },
                }.jsify()!
                as web.ResponseInit,
          );
          when(
            requestFactory.request(
              any,
              method: anyNamed('method'),
              requestHeaders: anyNamed('requestHeaders'),
              sendData: anyNamed('sendData'),
            ),
          ).thenAnswer((_) async => response);

          await controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('https://example.test/first')),
          );
          await controller.loadRequest(
            LoadRequestParams(
              uri: Uri.parse('https://example.test/form'),
              method: LoadRequestMethod.post,
              headers: const <String, String>{'X-Test': 'history'},
              body: Uint8List.fromList(<int>[1, 2, 3]),
            ),
          );
          expect(params.iFrame.src, contains('saved%20response'));

          await controller.goBack();
          await controller.goForward();

          expect(await controller.currentUrl(), 'https://example.test/form');
          expect(params.iFrame.src, contains('saved%20response'));
          verify(
            requestFactory.request(
              'https://example.test/form',
              method: 'post',
              requestHeaders: const <String, String>{'X-Test': 'history'},
              sendData: anyNamed('sendData'),
            ),
          ).called(1);
        },
      );

      test(
        'does not move the history index when navigation is denied',
        () async {
          final WebWebViewController controller = WebWebViewController(
            WebWebViewControllerCreationParams(),
          );
          final WebNavigationDelegate delegate = WebNavigationDelegate(
            const WebNavigationDelegateCreationParams(),
          );
          var allowNavigation = false;

          await controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('https://example.test/first')),
          );
          await controller.loadRequest(
            LoadRequestParams(uri: Uri.parse('https://example.test/second')),
          );
          await delegate.setOnNavigationRequest((NavigationRequest request) {
            return allowNavigation
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          });
          await controller.setPlatformNavigationDelegate(delegate);

          await controller.goBack();

          expect(await controller.currentUrl(), 'https://example.test/second');
          expect(await controller.canGoBack(), isTrue);
          expect(await controller.canGoForward(), isFalse);

          allowNavigation = true;
          await controller.goBack();

          expect(await controller.currentUrl(), 'https://example.test/first');
          expect(await controller.canGoBack(), isFalse);
          expect(await controller.canGoForward(), isTrue);
        },
      );

      test('bounds retained response history by total bytes', () async {
        final MockHttpRequestFactory requestFactory = MockHttpRequestFactory();
        final WebWebViewController controller = WebWebViewController(
          WebWebViewControllerCreationParams(
            httpRequestFactory: requestFactory,
          ),
        );
        when(
          requestFactory.request(
            any,
            method: anyNamed('method'),
            requestHeaders: anyNamed('requestHeaders'),
            sendData: anyNamed('sendData'),
          ),
        ).thenAnswer(
          (_) async => web.Response(
            Uint8List(4 * 1024 * 1024).toJS,
            <String, Object>{
                  'headers': <String, Object>{
                    'content-type': 'application/octet-stream',
                  },
                }.jsify()!
                as web.ResponseInit,
          ),
        );

        for (int index = 0; index < 9; index += 1) {
          await controller.loadRequest(
            LoadRequestParams(
              uri: Uri.parse('https://example.test/history/$index'),
              method: LoadRequestMethod.post,
            ),
          );
        }

        var retainedBackEntries = 0;
        while (await controller.canGoBack()) {
          await controller.goBack();
          retainedBackEntries += 1;
        }
        expect(retainedBackEntries, 6);
      });

      test(
        'a stale fetch response cannot replace a newer navigation',
        () async {
          final MockHttpRequestFactory requestFactory =
              MockHttpRequestFactory();
          final Completer<web.Response> firstResponse =
              Completer<web.Response>();
          final Completer<web.Response> secondResponse =
              Completer<web.Response>();
          final WebWebViewControllerCreationParams params =
              WebWebViewControllerCreationParams(
                httpRequestFactory: requestFactory,
              );
          final WebWebViewController controller = WebWebViewController(params);

          when(
            requestFactory.request(
              any,
              method: anyNamed('method'),
              requestHeaders: anyNamed('requestHeaders'),
              sendData: anyNamed('sendData'),
            ),
          ).thenAnswer((Invocation invocation) {
            return invocation.positionalArguments.single ==
                    'https://example.test/first'
                ? firstResponse.future
                : secondResponse.future;
          });

          final Future<void> firstLoad = controller.loadRequest(
            LoadRequestParams(
              uri: Uri.parse('https://example.test/first'),
              headers: const <String, String>{'X-WebView-Test': 'first'},
            ),
          );
          await Future<void>.delayed(Duration.zero);
          final Future<void> secondLoad = controller.loadRequest(
            LoadRequestParams(
              uri: Uri.parse('https://example.test/second'),
              headers: const <String, String>{'X-WebView-Test': 'second'},
            ),
          );

          secondResponse.complete(
            web.Response('<main>second response</main>'.toJS),
          );
          await secondLoad;
          firstResponse.complete(
            web.Response('<main>stale first response</main>'.toJS),
          );
          await firstLoad;

          expect(await controller.currentUrl(), 'https://example.test/second');
          expect(
            Uri.parse(params.iFrame.src).data!.contentAsString(),
            '<main>second response</main>',
          );
        },
      );
    });

    group('loadFlutterAsset', () {
      test('keeps loadFileWithParams unsupported on web', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await expectLater(
          () => controller.loadFileWithParams(
            const LoadFileParams(absoluteFilePath: '/tmp/index.html'),
          ),
          throwsUnsupportedError,
        );
      });

      test(
        'resolves Flutter web asset URLs under the assets directory',
        () async {
          final controller = WebWebViewController(
            WebWebViewControllerCreationParams(),
          );

          await controller.loadFlutterAsset('docs/My File.html');

          expect(
            (controller.params as WebWebViewControllerCreationParams)
                .iFrame
                .src,
            Uri.base.resolve('assets/docs/My%20File.html').toString(),
          );
        },
      );

      test('rejects empty asset keys', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await expectLater(
          () => controller.loadFlutterAsset(''),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('rejects root-only asset keys', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );

        await expectLater(
          () => controller.loadFlutterAsset('/'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('userAgent', () {
      test('safely ignores unsupported overrides and allows reset', () async {
        final controller = WebWebViewController(
          WebWebViewControllerCreationParams(),
        );
        final String? originalUserAgent = await controller.getUserAgent();

        await controller.setUserAgent('custom-agent');

        expect(await controller.getUserAgent(), originalUserAgent);

        await controller.setUserAgent(null);
        expect(await controller.getUserAgent(), originalUserAgent);
      });
    });

    group('javascript', () {
      test('runs JavaScript in accessible iframe content', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);

        await controller.runJavaScript('window.webViewAllValue = 37');
        expect(
          await controller.runJavaScriptReturningResult(
            'window.webViewAllValue + 5',
          ),
          42,
        );
        expect(
          await controller.runJavaScriptReturningResult(
            '({message: "ok", count: 2, values: [1, 2]})',
          ),
          <String, Object>{
            'message': 'ok',
            'count': 2,
            'values': <Object>[1, 2],
          },
        );
      });

      test(
        'awaits asynchronous JavaScript with structured arguments',
        () async {
          final WebWebViewControllerCreationParams params =
              WebWebViewControllerCreationParams();
          final WebWebViewController controller = WebWebViewController(params);
          addTearDown(() => params.iFrame.remove());
          await _attachAndLoadScrollableHtml(controller, params);

          final Object? result = await controller.callAsyncJavaScript(
            JavaScriptInvocationParams(
              functionBody:
                  'await Promise.resolve(); return value + nested.count;',
              arguments: const <String, Object?>{
                'value': 40,
                'nested': <String, Object?>{'count': 2},
              },
            ),
          );

          expect(result, 42);
          await expectLater(
            controller.callAsyncJavaScript(
              JavaScriptInvocationParams(functionBody: 'return (;'),
            ),
            throwsA(isA<JavaScriptExecutionException>()),
          );
          expect(
            await controller.isUserScriptInjectionSupported(
              WebViewUserScriptInjectionTime.documentStart,
            ),
            isFalse,
          );
        },
      );

      test('rejects null or undefined JavaScript results', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);

        await expectLater(
          () => controller.runJavaScriptReturningResult('undefined'),
          throwsA(isA<ArgumentError>()),
        );
        await expectLater(
          () => controller.runJavaScriptReturningResult('null'),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('can disable JavaScript for iframe loads', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() {
          params.iFrame.remove();
        });
        web.document.body!.append(params.iFrame);

        await controller.setJavaScriptMode(JavaScriptMode.disabled);
        final Future<web.Event> disabledLoad = params.iFrame.onLoad.first;
        await controller.loadHtmlString('''
<!doctype html>
<html>
  <body>
    <script>
      document.body.setAttribute('data-script-ran', 'yes');
    </script>
  </body>
</html>
''');
        await disabledLoad;

        expect(params.iFrame.getAttribute('sandbox'), isNotNull);
        expect(
          params.iFrame.contentDocument?.body?.getAttribute('data-script-ran'),
          isNull,
        );
        await expectLater(
          () => controller.runJavaScript('window.webViewAllValue = 1'),
          throwsStateError,
        );

        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        final Future<web.Event> unrestrictedLoad = params.iFrame.onLoad.first;
        await controller.loadHtmlString('''
<!doctype html>
<html>
  <body>
    <script>
      document.body.setAttribute('data-script-ran', 'yes');
    </script>
  </body>
</html>
''');
        await unrestrictedLoad;

        expect(params.iFrame.getAttribute('sandbox'), isNull);
        expect(
          params.iFrame.contentDocument?.body?.getAttribute('data-script-ran'),
          'yes',
        );
      });

      test(
        'preserves custom iframe sandbox around JavaScript mode changes',
        () async {
          final params = WebWebViewControllerCreationParams(
            iFrameSandbox: 'allow-scripts allow-forms',
          );
          final controller = WebWebViewController(params);

          expect(
            params.iFrame.getAttribute('sandbox'),
            'allow-scripts allow-forms',
          );

          await controller.setJavaScriptMode(JavaScriptMode.disabled);

          expect(params.iFrame.getAttribute('sandbox'), 'allow-forms');

          await controller.setIFrameSandbox('allow-popups');

          expect(params.iFrame.getAttribute('sandbox'), 'allow-popups');

          await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

          expect(params.iFrame.getAttribute('sandbox'), 'allow-popups');

          await controller.setIFrameSandbox(null);

          expect(params.iFrame.getAttribute('sandbox'), isNull);
        },
      );

      test(
        'keeps explicit sandbox permissions when scripts are disabled',
        () async {
          final params = WebWebViewControllerCreationParams(iFrameSandbox: '');
          final controller = WebWebViewController(params);
          await controller.setJavaScriptMode(JavaScriptMode.disabled);
          expect(params.iFrame.getAttribute('sandbox'), '');

          await controller.setIFrameSandbox(
            'ALLOW-SCRIPTS\tallow-downloads\nallow-forms',
          );
          expect(
            params.iFrame.getAttribute('sandbox'),
            'allow-downloads allow-forms',
          );
          await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
          expect(
            params.iFrame.getAttribute('sandbox'),
            'ALLOW-SCRIPTS\tallow-downloads\nallow-forms',
          );

          await controller.setJavaScriptMode(JavaScriptMode.disabled);
          await controller.setIFrameSandbox(null);
          expect(
            params.iFrame.getAttribute('sandbox'),
            isNot(contains('allow-scripts')),
          );
          await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
          expect(params.iFrame.hasAttribute('sandbox'), isFalse);
        },
      );

      test('sets and removes custom iframe attributes at runtime', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);

        await controller.setIFrameAllow('camera; microphone');
        await controller.setIFrameReferrerPolicy('origin');
        await controller.setIFrameAttribute('title', 'Runtime preview');

        expect(params.iFrame.getAttribute('allow'), 'camera; microphone');
        expect(params.iFrame.getAttribute('referrerpolicy'), 'origin');
        expect(params.iFrame.getAttribute('title'), 'Runtime preview');

        await controller.setIFrameAllow(null);
        await controller.setIFrameReferrerPolicy(null);
        await controller.setIFrameAttribute('title', null);

        expect(params.iFrame.getAttribute('allow'), isNull);
        expect(params.iFrame.getAttribute('referrerpolicy'), isNull);
        expect(params.iFrame.getAttribute('title'), isNull);
        await expectLater(
          controller.setIFrameAttribute('', 'value'),
          throwsArgumentError,
        );
        for (final String name in <String>['id', 'src', 'srcdoc']) {
          await expectLater(
            controller.setIFrameAttribute(name, 'value'),
            throwsArgumentError,
          );
        }
      });

      test('delivers JavaScript channel messages', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final messages = <JavaScriptMessage>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await controller.addJavaScriptChannel(
          JavaScriptChannelParams(
            name: 'TestChannel',
            onMessageReceived: (JavaScriptMessage message) {
              messages.add(message);
            },
          ),
        );

        await controller.runJavaScript('TestChannel.postMessage("hello")');
        for (int i = 0; i < 20 && messages.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(messages.single.message, 'hello');
        expect(messages.single.sourceUrl, isNull);
        expect(messages.single.sourceOrigin, web.window.location.origin);
        expect(messages.single.isMainFrame, isTrue);

        await controller.removeJavaScriptChannel('TestChannel');
        expect(
          await controller.runJavaScriptReturningResult('typeof TestChannel'),
          'undefined',
        );
      });

      test(
        'uses browser origin and rejects messages from other windows',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final messages = <JavaScriptMessage>[];
          addTearDown(() => params.iFrame.remove());
          await _attachAndLoadScrollableHtml(controller, params);
          await controller.addJavaScriptChannel(
            JavaScriptChannelParams(
              name: 'Sender',
              onMessageReceived: messages.add,
            ),
          );
          final payload = <String, Object?>{
            '__webview_all_type': 'javascriptChannel',
            'webViewId': params.iFrame.id,
            'channelName': 'Sender',
            'message': 'forged metadata',
            'sourceUrl': 'https://forged.example/allowed',
            'sourceOrigin': 'https://forged.example',
            'isMainFrame': false,
          };
          web.window.dispatchEvent(
            web.MessageEvent(
              'message',
              web.MessageEventInit(
                data: payload.jsify(),
                source: web.window,
                origin: 'https://forged.example',
              ),
            ),
          );
          expect(messages, isEmpty);
          web.window.dispatchEvent(
            web.MessageEvent(
              'message',
              web.MessageEventInit(
                data: payload.jsify(),
                source: params.iFrame.contentWindow,
                origin: 'https://forged.example',
              ),
            ),
          );
          expect(messages, isEmpty);
          final otherWindowMessage = web.window.onMessage.first;
          web.window.postMessage(payload.jsify(), '*'.toJS);
          await otherWindowMessage;
          expect(messages, isEmpty);
          // Use the real iframe's postMessage so the browser supplies the origin.
          await controller.runJavaScript('''
          window.parent.postMessage(${jsonEncode(payload)}, '*');
        ''');
          for (int i = 0; i < 20 && messages.isEmpty; i += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }
          expect(messages.single.sourceOrigin, web.window.location.origin);
          expect(messages.single.sourceUrl, isNull);
          expect(messages.single.isMainFrame, isTrue);
        },
      );

      test('installs JavaScript channels added before content loads', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final messages = <String>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await controller.addJavaScriptChannel(
          JavaScriptChannelParams(
            name: 'EarlyChannel',
            onMessageReceived: (JavaScriptMessage message) {
              messages.add(message.message);
            },
          ),
        );
        await _attachAndLoadScrollableHtml(controller, params);

        await controller.runJavaScript('EarlyChannel.postMessage(123)');
        for (int i = 0; i < 20 && messages.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(messages, <String>['123']);
      });
    });

    group('console', () {
      test(
        'forwards console messages from accessible iframe content',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final messages = <JavaScriptConsoleMessage>[];
          addTearDown(() {
            params.iFrame.remove();
          });

          await _attachAndLoadScrollableHtml(controller, params);
          await controller.setOnConsoleMessage(messages.add);
          await controller.runJavaScript('''
          console.log('plain', 7);
          console.warn({kind: 'warning'});
          const circular = {};
          circular.self = circular;
          console.log(undefined, circular);
          console.error('bad');
          console.debug('details');
          console.info('note');
        ''');

          for (int i = 0; i < 20 && messages.length < 6; i += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(
            messages.map((JavaScriptConsoleMessage message) => message.level),
            <JavaScriptLogLevel>[
              JavaScriptLogLevel.log,
              JavaScriptLogLevel.warning,
              JavaScriptLogLevel.log,
              JavaScriptLogLevel.error,
              JavaScriptLogLevel.debug,
              JavaScriptLogLevel.info,
            ],
          );
          expect(messages[0].message, 'plain 7');
          expect(messages[1].message, '{"kind":"warning"}');
          expect(messages[2].message, 'undefined [object Object]');
          expect(messages[3].message, 'bad');
          expect(messages[4].message, 'details');
          expect(messages[5].message, 'note');
        },
      );

      test('installs console forwarding after content loads', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final messages = <JavaScriptConsoleMessage>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await controller.setOnConsoleMessage(messages.add);
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.runJavaScript("console.log('early')");

        for (int i = 0; i < 20 && messages.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(messages, hasLength(1));
        expect(messages.single.level, JavaScriptLogLevel.log);
        expect(messages.single.message, 'early');
      });
    });

    group('javascript dialogs', () {
      test(
        'forwards alert dialog requests from accessible iframe content',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final requests = <JavaScriptAlertDialogRequest>[];
          addTearDown(() {
            params.iFrame.remove();
          });

          await _attachAndLoadScrollableHtml(controller, params);
          await controller.setOnJavaScriptAlertDialog((
            JavaScriptAlertDialogRequest request,
          ) async {
            requests.add(request);
          });
          await controller.runJavaScript("alert('hello alert')");

          for (int i = 0; i < 20 && requests.isEmpty; i += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          }

          expect(requests, hasLength(1));
          expect(requests.single.message, 'hello alert');
          expect(requests.single.url, isNotEmpty);
        },
      );

      test('contains asynchronous alert callback failures', () async {
        final WebWebViewControllerCreationParams params =
            WebWebViewControllerCreationParams();
        final WebWebViewController controller = WebWebViewController(params);
        final DebugPrintCallback previousDebugPrint = debugPrint;
        final List<String> messages = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            messages.add(message);
          }
        };
        addTearDown(() {
          debugPrint = previousDebugPrint;
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnJavaScriptAlertDialog((_) {
          return Future<void>.error(StateError('first line\nsecond line'));
        });
        await controller.runJavaScript("alert('failing alert')");

        for (int i = 0; i < 20 && messages.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(messages, hasLength(1));
        expect(messages.single, contains('JavaScript alert callback failed'));
        expect(messages.single, isNot(contains('\n')));
      });

      test('installs alert forwarding after content loads', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final requests = <JavaScriptAlertDialogRequest>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await controller.setOnJavaScriptAlertDialog((
          JavaScriptAlertDialogRequest request,
        ) async {
          requests.add(request);
        });
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.runJavaScript('alert(123)');

        for (int i = 0; i < 20 && requests.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(requests, hasLength(1));
        expect(requests.single.message, '123');
      });

      test(
        'forwards confirm dialog requests and returns the decision',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final requests = <JavaScriptConfirmDialogRequest>[];
          addTearDown(() {
            params.iFrame.remove();
          });

          await _attachAndLoadScrollableHtml(controller, params);
          await controller.setOnJavaScriptConfirmDialog((
            JavaScriptConfirmDialogRequest request,
          ) {
            requests.add(request);
            return SynchronousFuture<bool>(request.message == 'continue?');
          });

          final Object accepted = await controller.runJavaScriptReturningResult(
            "confirm('continue?')",
          );
          final Object rejected = await controller.runJavaScriptReturningResult(
            "confirm('stop?')",
          );

          expect(accepted, isTrue);
          expect(rejected, isFalse);
          expect(requests, hasLength(2));
          expect(requests.first.message, 'continue?');
          expect(requests.first.url, isNotEmpty);
          expect(requests.last.message, 'stop?');
        },
      );

      test('uses a safe fallback for asynchronous confirm callbacks', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnJavaScriptConfirmDialog((_) async => true);

        expect(
          await controller.runJavaScriptReturningResult("confirm('continue?')"),
          isFalse,
        );
      });

      test('keeps dialog bridge entries for multiple controllers', () async {
        final paramsA = WebWebViewControllerCreationParams();
        final paramsB = WebWebViewControllerCreationParams();
        final controllerA = WebWebViewController(paramsA);
        final controllerB = WebWebViewController(paramsB);
        addTearDown(() {
          paramsA.iFrame.remove();
          paramsB.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controllerA, paramsA);
        await _attachAndLoadScrollableHtml(controllerB, paramsB);
        await controllerA.setOnJavaScriptConfirmDialog((
          JavaScriptConfirmDialogRequest request,
        ) {
          return SynchronousFuture<bool>(request.message == 'controller-a');
        });
        await controllerB.setOnJavaScriptConfirmDialog((
          JavaScriptConfirmDialogRequest request,
        ) {
          return SynchronousFuture<bool>(request.message == 'controller-b');
        });

        final Object resultA = await controllerA.runJavaScriptReturningResult(
          "confirm('controller-a')",
        );
        final Object resultB = await controllerB.runJavaScriptReturningResult(
          "confirm('controller-b')",
        );
        final Object rejectedA = await controllerA.runJavaScriptReturningResult(
          "confirm('controller-b')",
        );

        expect(resultA, isTrue);
        expect(resultB, isTrue);
        expect(rejectedA, isFalse);
      });

      test('installs prompt forwarding after content loads', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final requests = <JavaScriptTextInputDialogRequest>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await controller.setOnJavaScriptTextInputDialog((
          JavaScriptTextInputDialogRequest request,
        ) {
          requests.add(request);
          return SynchronousFuture<String>('hello ${request.defaultText}');
        });
        await _attachAndLoadScrollableHtml(controller, params);

        final Object result = await controller.runJavaScriptReturningResult(
          "prompt('name', 'world')",
        );

        expect(result, 'hello world');
        expect(requests, hasLength(1));
        expect(requests.single.message, 'name');
        expect(requests.single.url, isNotEmpty);
        expect(requests.single.defaultText, 'world');
      });

      test('uses safe fallbacks when dialog callbacks throw', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final DebugPrintCallback previousDebugPrint = debugPrint;
        final List<String> messages = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            messages.add(message);
          }
        };
        addTearDown(() {
          debugPrint = previousDebugPrint;
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnJavaScriptConfirmDialog((_) {
          throw StateError('confirm failure\nsecond line');
        });
        await controller.setOnJavaScriptTextInputDialog((_) {
          throw StateError('prompt failure\nsecond line');
        });

        expect(
          await controller.runJavaScriptReturningResult("confirm('continue?')"),
          isFalse,
        );
        expect(
          await controller.runJavaScriptReturningResult(
            "prompt('name', 'fallback')",
          ),
          'fallback',
        );
        expect(messages, hasLength(2));
        expect(messages, contains(contains('confirm callback failed')));
        expect(messages, contains(contains('prompt callback failed')));
        expect(
          messages.every((String message) => !message.contains('\n')),
          isTrue,
        );
      });
    });

    group('permissions', () {
      for (final String? sandbox in <String?>[null, 'allow-scripts']) {
        test(
          'restores permission decisions after document.open ($sandbox)',
          () async {
            final params = WebWebViewControllerCreationParams(
              iFrameSandbox: sandbox,
            );
            final controller = WebWebViewController(params);
            final requests = <PlatformWebViewPermissionRequest>[];
            addTearDown(() => params.iFrame.remove());
            await _attachAndLoadScrollableHtml(controller, params);
            await _installFakeGetUserMedia(controller);
            await controller.setOnPlatformPermissionRequest((request) {
              requests.add(request);
              request.deny();
            });
            await _waitForJavaScriptValue(
              controller,
              'Boolean(window.__webviewAllPermissionRequestHookInstalled)',
              isTrue,
            );
            await controller.runJavaScript('''
            window.permissionWrapper = navigator.mediaDevices.getUserMedia;
          ''');

            for (final bool closeDocument in <bool>[false, true]) {
              // The pending request must settle even when document.open()
              // clears Window listeners before the host handles the request.
              await controller.runJavaScript('''
              window.permissionResult = 'pending';
              navigator.mediaDevices.getUserMedia({video: true}).then(
                function() { window.permissionResult = 'granted'; },
                function(error) { window.permissionResult = error.name; }
              );
              ${_rewriteCurrentDocumentScript(closeDocument: closeDocument)}
            ''');
              expect(
                await _waitForJavaScriptValue(
                  controller,
                  'window.permissionResult',
                  isNot('pending'),
                ),
                'NotAllowedError',
              );
              expect(
                await controller.runJavaScriptReturningResult(
                  'navigator.mediaDevices.getUserMedia === window.permissionWrapper',
                ),
                isTrue,
              );
            }
            expect(requests, hasLength(2));
            expect(
              await controller.runJavaScriptReturningResult(
                'document.body.getAttribute("data-original-get-user-media-called")',
              ),
              'no',
            );
          },
        );
      }

      for (final String? sandbox in <String?>[null, 'allow-scripts']) {
        test(
          'settles permission decisions after repeated empty open ($sandbox)',
          () async {
            final params = WebWebViewControllerCreationParams(
              iFrameSandbox: sandbox,
            );
            final controller = WebWebViewController(params);
            final requests = <PlatformWebViewPermissionRequest>[];
            addTearDown(() => params.iFrame.remove());
            await _attachAndLoadScrollableHtml(controller, params);
            await _installFakeGetUserMedia(controller);
            await controller.setOnPlatformPermissionRequest((request) {
              requests.add(request);
              request.deny();
            });
            await controller.runJavaScript('document.open();');

            for (int i = 0; i < 3; i += 1) {
              await controller.runJavaScript('''
              document.open();
              window.permissionResult = 'pending';
              navigator.mediaDevices.getUserMedia({video: true}).then(
                function() { window.permissionResult = 'granted'; },
                function(error) { window.permissionResult = error.name; }
              );
              document.open();
            ''');
              expect(
                await _waitForJavaScriptValue(
                  controller,
                  'window.permissionResult',
                  isNot('pending'),
                ),
                'NotAllowedError',
              );
            }
            expect(requests, hasLength(3));
          },
        );

        test(
          'ignores permission decisions from a previous document ($sandbox)',
          () async {
            final params = WebWebViewControllerCreationParams(
              iFrameSandbox: sandbox,
            );
            final controller = WebWebViewController(params);
            final requests = <PlatformWebViewPermissionRequest>[];
            addTearDown(() => params.iFrame.remove());
            await _attachAndLoadScrollableHtml(controller, params);
            await _installFakeGetUserMedia(controller);
            await controller.setOnPlatformPermissionRequest(requests.add);
            const String startRequest = '''
            window.permissionResult = 'pending';
            navigator.mediaDevices.getUserMedia({video: true}).then(
              function() { window.permissionResult = 'granted'; },
              function(error) { window.permissionResult = error.name; }
            );
          ''';
            await controller.runJavaScript(startRequest);
            for (int i = 0; i < 40 && requests.isEmpty; i += 1) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            expect(requests, hasLength(1));

            final Future<web.Event> loaded = params.iFrame.onLoad.first;
            await controller.loadHtmlString('''
              <body>New document<script>$_fakeGetUserMediaScript</script></body>
            ''');
            await loaded;
            await controller.runJavaScript(startRequest);
            for (int i = 0; i < 40 && requests.length < 2; i += 1) {
              await Future<void>.delayed(const Duration(milliseconds: 25));
            }
            expect(requests, hasLength(2));

            await requests.first.grant();
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(
              await controller.runJavaScriptReturningResult(
                'window.permissionResult',
              ),
              'pending',
            );
            await requests.last.deny();
            expect(
              await _waitForJavaScriptValue(
                controller,
                'window.permissionResult',
                isNot('pending'),
              ),
              'NotAllowedError',
            );
            expect(
              await controller.runJavaScriptReturningResult(
                'document.body.getAttribute("data-original-get-user-media-called")',
              ),
              'no',
            );
          },
        );
      }

      test(
        'rejects permission requests queued by a previous document',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final requests = <PlatformWebViewPermissionRequest>[];
          addTearDown(() => params.iFrame.remove());
          await _attachAndLoadScrollableHtml(controller, params);
          await _installFakeGetUserMedia(controller);
          await controller.setOnPlatformPermissionRequest(requests.add);

          // Same-origin evaluation completes before the posted Window message
          // runs, allowing navigation to invalidate this queued request first.
          await controller.runJavaScript('''
          navigator.mediaDevices.getUserMedia({video: true}).catch(function() {});
        ''');
          final Future<web.Event> loaded = params.iFrame.onLoad.first;
          await controller.loadHtmlString('<body>New document</body>');
          await loaded;
          expect(requests, isEmpty);
        },
      );

      test('denies same-origin getUserMedia requests', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final requests = <PlatformWebViewPermissionRequest>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await _installFakeGetUserMedia(controller);
        await controller.setOnPlatformPermissionRequest((
          PlatformWebViewPermissionRequest request,
        ) {
          requests.add(request);
          request.deny();
        });

        await controller.runJavaScript('''
          window.permissionResult = 'pending';
          navigator.mediaDevices.getUserMedia({ audio: true, video: true })
            .then(function() {
              window.permissionResult = 'granted';
            })
            .catch(function(error) {
              window.permissionResult = error.name;
            });
        ''');

        final Object result = await _waitForJavaScriptValue(
          controller,
          'window.permissionResult',
          isNot('pending'),
        );

        expect(result, 'NotAllowedError');
        expect(requests, hasLength(1));
        expect(
          requests.single.types,
          containsAll(<WebViewPermissionResourceType>{
            WebViewPermissionResourceType.camera,
            WebViewPermissionResourceType.microphone,
          }),
        );
        expect(
          await controller.runJavaScriptReturningResult(
            'document.body.getAttribute("data-original-get-user-media-called")',
          ),
          'no',
        );
      });

      test('grants same-origin getUserMedia requests', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final requests = <PlatformWebViewPermissionRequest>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await _installFakeGetUserMedia(controller);
        await controller.setOnPlatformPermissionRequest((
          PlatformWebViewPermissionRequest request,
        ) {
          requests.add(request);
          request.grant();
        });

        await controller.runJavaScript('''
          window.permissionResult = 'pending';
          navigator.mediaDevices.getUserMedia({ audio: true })
            .then(function(stream) {
              window.permissionResult = stream;
            })
            .catch(function(error) {
              window.permissionResult = error.name;
            });
        ''');

        final Object result = await _waitForJavaScriptValue(
          controller,
          'window.permissionResult',
          isNot('pending'),
        );

        expect(result, 'fake-stream');
        expect(requests, hasLength(1));
        expect(requests.single.types, <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
        });
        expect(
          await controller.runJavaScriptReturningResult(
            'document.body.getAttribute("data-original-get-user-media-called")',
          ),
          'yes',
        );
      });

      test('denies permission requests when the callback throws', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final DebugPrintCallback previousDebugPrint = debugPrint;
        final List<String> messages = <String>[];
        debugPrint = (String? message, {int? wrapWidth}) {
          if (message != null) {
            messages.add(message);
          }
        };
        addTearDown(() {
          debugPrint = previousDebugPrint;
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await _installFakeGetUserMedia(controller);
        await controller.setOnPlatformPermissionRequest((_) {
          throw StateError('permission failure\nsecond line');
        });

        await controller.runJavaScript('''
          window.permissionResult = 'pending';
          navigator.mediaDevices.getUserMedia({ audio: true })
            .then(function() {
              window.permissionResult = 'granted';
            })
            .catch(function(error) {
              window.permissionResult = error.name;
            });
        ''');

        expect(
          await _waitForJavaScriptValue(
            controller,
            'window.permissionResult',
            isNot('pending'),
          ),
          'NotAllowedError',
        );
        expect(messages, hasLength(1));
        expect(messages.single, contains('permission callback failed'));
        expect(messages.single, isNot(contains('\n')));
      });

      test(
        'preserves a completed permission decision when the callback throws',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          final DebugPrintCallback previousDebugPrint = debugPrint;
          final List<String> messages = <String>[];
          debugPrint = (String? message, {int? wrapWidth}) {
            if (message != null) {
              messages.add(message);
            }
          };
          addTearDown(() {
            debugPrint = previousDebugPrint;
            params.iFrame.remove();
          });

          await _attachAndLoadScrollableHtml(controller, params);
          await _installFakeGetUserMedia(controller);
          await controller.setOnPlatformPermissionRequest((request) {
            request.grant();
            throw StateError('failure after decision\nsecond line');
          });

          await controller.runJavaScript('''
            window.permissionResult = 'pending';
            navigator.mediaDevices.getUserMedia({ audio: true })
              .then(function(stream) {
                window.permissionResult = stream;
              })
              .catch(function(error) {
                window.permissionResult = error.name;
              });
          ''');

          expect(
            await _waitForJavaScriptValue(
              controller,
              'window.permissionResult',
              isNot('pending'),
            ),
            'fake-stream',
          );
          expect(messages, hasLength(1));
          expect(messages.single, contains('completed decision was preserved'));
          expect(messages.single, isNot(contains('\n')));
        },
      );

      test('rejects forged in-frame permission decisions', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final requests = <PlatformWebViewPermissionRequest>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await _installFakeGetUserMedia(controller);
        await controller.setOnPlatformPermissionRequest(requests.add);
        await controller.runJavaScript('''
          window.permissionResult = 'pending';
          navigator.mediaDevices.getUserMedia({ audio: true })
            .then(function() {
              window.permissionResult = 'granted';
            })
            .catch(function(error) {
              window.permissionResult = error.name;
            });
        ''');
        for (int i = 0; i < 20 && requests.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        expect(requests, hasLength(1));

        await controller.runJavaScript('''
          window.postMessage({
            "__webview_all_type": "platformPermissionDecision",
            "webViewId": ${jsonEncode(params.iFrame.id)},
            "requestId": "1",
            "granted": true
          }, "*");
        ''');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          await controller.runJavaScriptReturningResult(
            'window.permissionResult',
          ),
          'pending',
        );

        await requests.single.deny();
        expect(
          await _waitForJavaScriptValue(
            controller,
            'window.permissionResult',
            isNot('pending'),
          ),
          'NotAllowedError',
        );
      });
    });

    group('enableZoom', () {
      test('toggles iframe touch-action zoom suppression', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);

        await controller.enableZoom(false);
        expect(
          params.iFrame.style.getPropertyValue('touch-action'),
          'pan-x pan-y',
        );

        await controller.enableZoom(true);
        expect(params.iFrame.style.getPropertyValue('touch-action'), '');
      });
    });

    group('scrolling', () {
      test('scrolls accessible iframe content', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);

        await controller.scrollTo(20, 40);
        expect(await controller.getScrollPosition(), const Offset(20, 40));

        await controller.scrollBy(5, 6);
        expect(await controller.getScrollPosition(), const Offset(25, 46));
      });

      test('reports scroll position changes for accessible content', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final changes = <ScrollPositionChange>[];
        addTearDown(() {
          params.iFrame.remove();
        });

        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnScrollPositionChange(changes.add);
        await controller.scrollTo(0, 80);

        for (int i = 0; i < 20 && changes.isEmpty; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }

        expect(changes, isNotEmpty);
        expect(changes.last.y, 80);
      });

      test('restores accessible scroll listeners after document.open', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);
        final changes = <ScrollPositionChange>[];
        addTearDown(() => params.iFrame.remove());
        await _attachAndLoadScrollableHtml(controller, params);
        await controller.setOnScrollPositionChange(changes.add);

        for (final bool closeDocument in <bool>[false, true]) {
          await controller.runJavaScript(
            _rewriteCurrentDocumentScript(closeDocument: closeDocument),
          );
          final double expectedY = closeDocument ? 160 : 80;
          changes.clear();
          await controller.scrollTo(0, expectedY.toInt());
          await _waitForScrollChange(changes, expectedY);
          expect(await controller.getScrollPosition(), Offset(0, expectedY));
          expect(changes.last.y, expectedY);
          changes.clear();
          await controller.runJavaScript(
            'window.dispatchEvent(new Event("scroll"));',
          );
          expect(changes, hasLength(1));
        }

        // Removing the callback must also stop the observer from reattaching it.
        await controller.setOnScrollPositionChange(null);
        changes.clear();
        await controller.runJavaScript(_rewriteCurrentDocumentScript());
        await controller.scrollTo(0, 240);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(changes, isEmpty);
      });
    });

    group('scrollbars', () {
      test(
        'applies scrollbar stylesheet to accessible iframe content',
        () async {
          final params = WebWebViewControllerCreationParams();
          final controller = WebWebViewController(params);
          addTearDown(() {
            params.iFrame.remove();
          });

          await _attachAndLoadScrollableHtml(controller, params);

          expect(controller.supportsSetScrollBarsEnabled(), isTrue);

          await controller.setVerticalScrollBarEnabled(false);
          expect(
            _scrollbarStyle(params)?.textContent,
            contains('::-webkit-scrollbar:vertical'),
          );
          expect(
            _scrollbarStyle(params)?.textContent,
            isNot(contains('::-webkit-scrollbar:horizontal')),
          );

          await controller.setHorizontalScrollBarEnabled(false);
          expect(
            _scrollbarStyle(params)?.textContent,
            contains('::-webkit-scrollbar:vertical'),
          );
          expect(
            _scrollbarStyle(params)?.textContent,
            contains('::-webkit-scrollbar:horizontal'),
          );

          await controller.setVerticalScrollBarEnabled(true);
          expect(
            _scrollbarStyle(params)?.textContent,
            isNot(contains('::-webkit-scrollbar:vertical')),
          );
          expect(
            _scrollbarStyle(params)?.textContent,
            contains('::-webkit-scrollbar:horizontal'),
          );

          await controller.setHorizontalScrollBarEnabled(true);
          expect(_scrollbarStyle(params), isNull);
        },
      );
    });

    group('setOverScrollMode', () {
      test('sets iframe overscroll behavior', () async {
        final params = WebWebViewControllerCreationParams();
        final controller = WebWebViewController(params);

        await controller.setOverScrollMode(WebViewOverScrollMode.never);
        expect(
          params.iFrame.style.getPropertyValue('overscroll-behavior'),
          'none',
        );

        await controller.setOverScrollMode(
          WebViewOverScrollMode.ifContentScrolls,
        );
        expect(
          params.iFrame.style.getPropertyValue('overscroll-behavior'),
          'contain',
        );

        await controller.setOverScrollMode(WebViewOverScrollMode.always);
        expect(
          params.iFrame.style.getPropertyValue('overscroll-behavior'),
          'auto',
        );
      });
    });
  });
}

const String _fakeGetUserMediaScript = '''
    Object.defineProperty(navigator, 'mediaDevices', {
      configurable: true,
      value: {
        getUserMedia: function() {
          document.body.setAttribute(
            'data-original-get-user-media-called',
            'yes'
          );
          return Promise.resolve('fake-stream');
        }
      }
    });
    document.body.setAttribute('data-original-get-user-media-called', 'no');
  ''';

Future<void> _installFakeGetUserMedia(WebWebViewController controller) {
  return controller.runJavaScript(_fakeGetUserMediaScript);
}

Future<void> _attachAndLoadReloadableHtml(
  WebWebViewController controller,
  WebWebViewControllerCreationParams params, {
  required bool fetchedData,
}) async {
  final String html =
      '''
    <!doctype html><html><head><title>Reloadable</title></head>
    <body style="margin:0;width:2000px;height:2000px;">
      <script>$_fakeGetUserMediaScript</script>
    </body></html>
  ''';
  params.iFrame.style.width = '200px';
  params.iFrame.style.height = '200px';
  web.document.body!.append(params.iFrame);
  final Future<web.Event> loaded = params.iFrame.onLoad.first;
  if (fetchedData) {
    final MockHttpRequestFactory factory =
        params.httpRequestFactory as MockHttpRequestFactory;
    when(
      factory.request(
        any,
        method: anyNamed('method'),
        requestHeaders: anyNamed('requestHeaders'),
        sendData: anyNamed('sendData'),
      ),
    ).thenAnswer(
      (_) async => web.Response(
        html.toJS,
        <String, Object>{
              'headers': <String, Object>{'content-type': 'text/html'},
            }.jsify()!
            as web.ResponseInit,
      ),
    );
    await controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.com/reloadable'),
        headers: const <String, String>{'x-load': 'fetch'},
      ),
    );
  } else {
    await controller.loadHtmlString(html);
  }
  await loaded;
}

String _rewriteCurrentDocumentScript({bool closeDocument = false}) =>
    '''
  (function() {
    const root = document.documentElement;
    document.open();
    document.appendChild(root);
    ${closeDocument ? 'document.close();' : ''}
  })();
''';

Future<void> _waitForScrollChange(
  List<ScrollPositionChange> changes,
  double expectedY,
) async {
  for (int i = 0; i < 40; i += 1) {
    if (changes.any((ScrollPositionChange change) => change.y == expectedY)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<Object> _waitForJavaScriptValue(
  WebWebViewController controller,
  String expression,
  Matcher matcher,
) async {
  Object? result;
  for (int i = 0; i < 40; i += 1) {
    result = await controller.runJavaScriptReturningResult(expression);
    if (matcher.matches(result, <Object, Object>{})) {
      return result;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return result!;
}

Future<void> _attachAndLoadScrollableHtml(
  WebWebViewController controller,
  WebWebViewControllerCreationParams params,
) async {
  params.iFrame.style.width = '200px';
  params.iFrame.style.height = '200px';
  web.document.body!.append(params.iFrame);

  final Future<web.Event> loadFuture = params.iFrame.onLoad.first;
  await controller.loadHtmlString('''
<!doctype html>
<html>
  <head><title>Scrollable</title></head>
  <body style="margin:0;width:2000px;height:2000px;">
    <div style="width:2000px;height:2000px;"></div>
  </body>
</html>
''');
  await loadFuture.timeout(const Duration(seconds: 5));
  await Future<void>.delayed(Duration.zero);
}

web.Element? _scrollbarStyle(WebWebViewControllerCreationParams params) {
  return params.iFrame.contentDocument?.getElementById(
    '__webview_all_scrollbars',
  );
}

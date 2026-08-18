// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// This test is run using `flutter drive` by the CI (see /script/tool/README.md
// in this repository for details on driving that tooling manually), but can
// also be run using `flutter test` directly during development.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  unawaited(
    server.forEach((HttpRequest request) {
      if (request.uri.path == '/hello.txt') {
        request.response.writeln('Hello, world.');
      } else if (request.uri.path == '/secondary.txt') {
        request.response.writeln('How are you today?');
      } else if (request.uri.path == '/headers') {
        request.response.writeln('${request.headers}');
      } else if (request.uri.path == '/favicon.ico') {
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.uri.path == '/http-basic-authentication') {
        final List<String>? authHeader =
            request.headers[HttpHeaders.authorizationHeader];
        if (authHeader != null) {
          final String encodedCredential = authHeader.first.split(' ')[1];
          final credential = String.fromCharCodes(
            base64Decode(encodedCredential),
          );
          if (credential == 'user:password') {
            request.response.writeln('Authorized');
          } else {
            request.response.headers.add(
              HttpHeaders.wwwAuthenticateHeader,
              'Basic realm="Test realm"',
            );
            request.response.statusCode = HttpStatus.unauthorized;
          }
        } else {
          request.response.headers.add(
            HttpHeaders.wwwAuthenticateHeader,
            'Basic realm="Test realm"',
          );
          request.response.statusCode = HttpStatus.unauthorized;
        }
      } else {
        fail('unexpected request: ${request.method} ${request.uri}');
      }
      request.response.close();
    }),
  );
  final prefixUrl = 'http://${server.address.address}:${server.port}';
  final primaryUrl = '$prefixUrl/hello.txt';
  final secondaryUrl = '$prefixUrl/secondary.txt';
  final headersUrl = '$prefixUrl/headers';
  final basicAuthUrl = '$prefixUrl/http-basic-authentication';

  testWidgets('Windows controller releases its renderer process', (
    WidgetTester tester,
  ) async {
    if (!Platform.isWindows) {
      return;
    }

    final int rendererCountBefore = await _countWindowsRendererProcesses();
    final Completer<void> pageFinished = Completer<void>();
    final WebViewController controller = WebViewController();
    final WindowsWebViewController windowsController =
        controller.platform as WindowsWebViewController;
    var disposed = false;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (!disposed) {
        await windowsController.dispose();
      }
    });
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) {
            pageFinished.complete();
          }
        },
      ),
    );
    await controller.loadHtmlString('''
<!DOCTYPE html>
<html><head><title>Windows lifecycle test</title></head>
<body>Windows lifecycle test</body></html>
''');

    await tester.pumpWidget(WebViewWidget(controller: controller));
    await pageFinished.future.timeout(const Duration(seconds: 15));
    await _waitForCondition(
      () async => await _countWindowsRendererProcesses() > rendererCountBefore,
      reason: 'Creating a Windows WebView did not start a renderer process.',
      timeout: const Duration(seconds: 15),
    );
    final int rendererCountWhileMounted =
        await _countWindowsRendererProcesses();

    await tester.pumpWidget(const SizedBox.shrink());
    await windowsController.dispose();
    disposed = true;

    await _waitForCondition(
      () async => await _countWindowsRendererProcesses() <= rendererCountBefore,
      reason:
          'Disposing the Windows controller did not restore the renderer '
          'process count from $rendererCountWhileMounted to '
          '$rendererCountBefore.',
      timeout: const Duration(seconds: 15),
    );
    await expectLater(controller.currentUrl(), throwsStateError);
  });

  testWidgets('loadRequest', (WidgetTester tester) async {
    final pageFinished = Completer<void>();

    final controller = WebViewController();
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(WebViewWidget(controller: controller));
    await pageFinished.future;

    final String? currentUrl = await controller.currentUrl();
    expect(currentUrl, primaryUrl);
  });

  testWidgets('Linux native view receives system pointer and keyboard input', (
    WidgetTester tester,
  ) async {
    if (!Platform.isLinux) {
      return;
    }

    final bool hasXdotool = await _hasExecutable('xdotool');
    if (!hasXdotool) {
      if (Platform.environment['CI'] == 'true') {
        fail('xdotool is required for the Linux native input test.');
      }
      return;
    }

    final Completer<void> pageFinished = Completer<void>();
    final Completer<void> pointerDown = Completer<void>();
    final Completer<void> flutterPointerDown = Completer<void>();
    final controller = WebViewController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await (controller.platform as LinuxWebViewController).dispose();
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'LinuxPointerTest',
      onMessageReceived: (JavaScriptMessage message) {
        if (message.message == 'pointer-down' && !pointerDown.isCompleted) {
          pointerDown.complete();
        }
      },
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!pageFinished.isCompleted) {
            pageFinished.complete();
          }
        },
      ),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          children: <Widget>[
            Expanded(
              child: SizedBox.expand(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (!flutterPointerDown.isCompleted) {
                      flutterPointerDown.complete();
                    }
                  },
                  child: const Center(child: Text('Flutter input target')),
                ),
              ),
            ),
            Expanded(child: WebViewWidget(controller: controller)),
          ],
        ),
      ),
    );
    await controller.loadHtmlString('''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin: 0; min-height: 3000px; }
    #target {
      position: fixed;
      left: calc(50% - 140px);
      top: calc(50% - 35px);
      width: 280px;
      height: 70px;
      font-size: 20px;
    }
  </style>
</head>
<body>
  <input id="target" onmousedown="LinuxPointerTest.postMessage('pointer-down')">
</body>
</html>
''');
    await pageFinished.future.timeout(const Duration(seconds: 10));
    await _waitForJavaScriptPredicate(
      controller,
      'document.getElementById("target") !== null',
      (Object value) => value == true,
    );

    final _X11Window window = await _findCurrentX11Window();
    await _runXdotool(<String>['windowfocus', window.id]);
    await _runXdotool(<String>[
      'mousemove',
      '--sync',
      '--window',
      window.id,
      '${window.width * 3 ~/ 4}',
      '${window.height ~/ 2}',
    ]);
    await _runXdotool(<String>['click', '1']);
    await pointerDown.future.timeout(const Duration(seconds: 5));

    await _runXdotool(<String>['type', '--delay', '20', 'commercial-input']);
    await _waitForJavaScriptResult(
      controller,
      'document.getElementById("target").value',
      'commercial-input',
    );

    await _runXdotool(<String>['click', '--repeat', '3', '--delay', '50', '5']);
    await _waitForJavaScriptPredicate(
      controller,
      'window.scrollY > 0',
      (Object value) => value == true,
    );

    final bool propagatedDeviceEvents =
        tester.binding.shouldPropagateDevicePointerEvents;
    tester.binding.shouldPropagateDevicePointerEvents = true;
    try {
      await _runXdotool(<String>[
        'mousemove',
        '--sync',
        '--window',
        window.id,
        '${window.width ~/ 4}',
        '${window.height ~/ 2}',
      ]);
      await _runXdotool(<String>['click', '1']);
      await flutterPointerDown.future.timeout(const Duration(seconds: 5));
    } finally {
      tester.binding.shouldPropagateDevicePointerEvents =
          propagatedDeviceEvents;
    }
  });

  testWidgets('runJavaScriptReturningResult', (WidgetTester tester) async {
    final pageFinished = Completer<void>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await pageFinished.future;

    await expectLater(
      controller.runJavaScriptReturningResult('1 + 1'),
      completion(2),
    );
  });

  testWidgets('loadRequest with headers', (WidgetTester tester) async {
    final headers = <String, String>{'test_header': 'flutter_test_header'};

    final pageLoads = StreamController<String>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (String url) => pageLoads.add(url)),
    );

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await controller.loadRequest(Uri.parse(headersUrl), headers: headers);

    await pageLoads.stream.firstWhere((String url) => url == headersUrl);

    final content =
        await controller.runJavaScriptReturningResult(
              'document.documentElement.innerText',
            )
            as String;
    expect(content.contains('flutter_test_header'), isTrue);
  });

  testWidgets('JavascriptChannel', (WidgetTester tester) async {
    final pageFinished = Completer<void>();
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );

    final channelCompleter = Completer<String>();
    await controller.addJavaScriptChannel(
      'Echo',
      onMessageReceived: (JavaScriptMessage message) {
        channelCompleter.complete(message.message);
      },
    );

    await controller.loadHtmlString(
      'data:text/html;charset=utf-8;base64,PCFET0NUWVBFIGh0bWw+',
    );

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await pageFinished.future;

    await controller.runJavaScript('Echo.postMessage("hello");');
    await expectLater(channelCompleter.future, completion('hello'));
  });

  testWidgets('resize webview', (WidgetTester tester) async {
    final initialResizeCompleter = Completer<void>();
    final buttonTapResizeCompleter = Completer<void>();
    final onPageFinished = Completer<void>();

    var resizeButtonTapped = false;
    await tester.pumpWidget(
      ResizableWebView(
        onResize: () {
          if (resizeButtonTapped) {
            if (!buttonTapResizeCompleter.isCompleted) {
              buttonTapResizeCompleter.complete();
            }
          } else if (!initialResizeCompleter.isCompleted) {
            initialResizeCompleter.complete();
          }
        },
        onPageFinished: () {
          if (!onPageFinished.isCompleted) {
            onPageFinished.complete();
          }
        },
      ),
    );

    await onPageFinished.future;
    // Wait for a potential call to resize after page is loaded.
    await initialResizeCompleter.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );

    resizeButtonTapped = true;

    await tester.tap(find.byKey(const ValueKey<String>('resizeButton')));
    await tester.pumpAndSettle();

    await expectLater(buttonTapResizeCompleter.future, completes);
  });

  testWidgets('set custom userAgent', (WidgetTester tester) async {
    final pageFinished = Completer<void>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageFinished.complete()),
    );
    await controller.setUserAgent('Custom_User_Agent1');
    await controller.loadRequest(Uri.parse('about:blank'));

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await pageFinished.future;

    final String? customUserAgent = await controller.getUserAgent();
    expect(customUserAgent, 'Custom_User_Agent1');
  });

  group(
    'Video playback policy',
    () {
      testWidgets('Auto media playback', (WidgetTester tester) async {
        final String videoTestBase64 = await getTestVideoBase64();
        var pageLoaded = Completer<void>();

        late PlatformWebViewControllerCreationParams params;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          params = WebKitWebViewControllerCreationParams(
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }

        var controller = WebViewController.fromPlatformCreationParams(params);
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );

        if (controller.platform is AndroidWebViewController) {
          await (controller.platform as AndroidWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        } else if (controller.platform is LinuxWebViewController) {
          await (controller.platform as LinuxWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        }

        await controller.loadRequest(
          Uri.parse('data:text/html;charset=utf-8;base64,$videoTestBase64'),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));

        await tester.pumpAndSettle();

        await pageLoaded.future;
        await _waitForCondition(
          () async =>
              await controller.runJavaScriptReturningResult('isPaused();') ==
              false,
          reason: 'Media playback did not start after disabling the gesture.',
        );

        var isPaused =
            await controller.runJavaScriptReturningResult('isPaused();')
                as bool;
        expect(isPaused, false);

        pageLoaded = Completer<void>();
        controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );

        await controller.loadRequest(
          Uri.parse('data:text/html;charset=utf-8;base64,$videoTestBase64'),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));

        await tester.pumpAndSettle();

        await pageLoaded.future;

        isPaused =
            await controller.runJavaScriptReturningResult('isPaused();')
                as bool;
        expect(isPaused, true);
      });

      testWidgets('Video plays inline', (WidgetTester tester) async {
        final String videoTestBase64 = await getTestVideoBase64();
        final pageLoaded = Completer<void>();
        final videoPlaying = Completer<void>();

        late PlatformWebViewControllerCreationParams params;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          params = WebKitWebViewControllerCreationParams(
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            allowsInlineMediaPlayback: true,
          );
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }
        final controller = WebViewController.fromPlatformCreationParams(params);
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );

        await controller.addJavaScriptChannel(
          'VideoTestTime',
          onMessageReceived: (JavaScriptMessage message) {
            final double currentTime = double.parse(message.message);
            // Let it play for at least 1 second to make sure the related video's properties are set.
            if (currentTime > 1 && !videoPlaying.isCompleted) {
              videoPlaying.complete(null);
            }
          },
        );

        if (controller.platform is AndroidWebViewController) {
          await (controller.platform as AndroidWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        } else if (controller.platform is LinuxWebViewController) {
          await (controller.platform as LinuxWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        }

        await controller.loadRequest(
          Uri.parse('data:text/html;charset=utf-8;base64,$videoTestBase64'),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));
        await tester.pumpAndSettle();

        await pageLoaded.future;

        // Makes sure we get the correct event that indicates the video is actually playing.
        await videoPlaying.future;

        final fullScreen =
            await controller.runJavaScriptReturningResult('isFullScreen();')
                as bool;
        expect(fullScreen, false);
      });
    },
    // TODO(bparrishMines): Stop skipping once https://github.com/flutter/flutter/issues/148487 is resolved
    skip: true,
  );

  group(
    'Audio playback policy',
    () {
      late String audioTestBase64;
      setUpAll(() async {
        final ByteData audioData = await rootBundle.load(
          'assets/sample_audio.ogg',
        );
        final String base64AudioData = base64Encode(
          Uint8List.view(audioData.buffer),
        );
        final audioTest =
            '''
        <!DOCTYPE html><html>
        <head><title>Audio auto play</title>
          <script type="text/javascript">
            function play() {
              var audio = document.getElementById("audio");
              audio.play();
            }
            function isPaused() {
              var audio = document.getElementById("audio");
              return audio.paused;
            }
          </script>
        </head>
        <body onload="play();">
        <audio controls id="audio">
          <source src="data:audio/ogg;charset=utf-8;base64,$base64AudioData">
        </audio>
        </body>
        </html>
      ''';
        audioTestBase64 = base64Encode(const Utf8Encoder().convert(audioTest));
      });

      testWidgets('Auto media playback', (WidgetTester tester) async {
        var pageLoaded = Completer<void>();

        late PlatformWebViewControllerCreationParams params;
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          params = WebKitWebViewControllerCreationParams(
            mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
          );
        } else {
          params = const PlatformWebViewControllerCreationParams();
        }

        var controller = WebViewController.fromPlatformCreationParams(params);
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );

        if (controller.platform is AndroidWebViewController) {
          await (controller.platform as AndroidWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        } else if (controller.platform is LinuxWebViewController) {
          await (controller.platform as LinuxWebViewController)
              .setMediaPlaybackRequiresUserGesture(false);
        }

        await controller.loadRequest(
          Uri.parse('data:text/html;charset=utf-8;base64,$audioTestBase64'),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));
        await tester.pumpAndSettle();

        await pageLoaded.future;
        await _waitForCondition(
          () async =>
              await controller.runJavaScriptReturningResult('isPaused();') ==
              false,
          reason: 'Audio playback did not start after disabling the gesture.',
        );

        var isPaused =
            await controller.runJavaScriptReturningResult('isPaused();')
                as bool;
        expect(isPaused, false);

        pageLoaded = Completer<void>();
        controller = WebViewController();
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );
        if (controller.platform is LinuxWebViewController) {
          await (controller.platform as LinuxWebViewController)
              .setMediaPlaybackRequiresUserGesture(true);
        }

        await controller.loadRequest(
          Uri.parse('data:text/html;charset=utf-8;base64,$audioTestBase64'),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));

        await tester.pumpAndSettle();
        await pageLoaded.future;

        isPaused =
            await controller.runJavaScriptReturningResult('isPaused();')
                as bool;
        expect(isPaused, true);
      });
    },
    // OGG playback is not supported on macOS. WebView2 does not expose the
    // per-controller user-gesture setting exercised by this test.
    skip: Platform.isMacOS || Platform.isWindows,
  );

  testWidgets('getTitle', (WidgetTester tester) async {
    const getTitleTest = '''
        <!DOCTYPE html><html>
        <head><title>Some title</title>
        </head>
        <body>
        </body>
        </html>
      ''';
    final String getTitleTestBase64 = base64Encode(
      const Utf8Encoder().convert(getTitleTest),
    );
    final pageLoaded = Completer<void>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
    );
    await controller.loadRequest(
      Uri.parse('data:text/html;charset=utf-8;base64,$getTitleTestBase64'),
    );

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await pageLoaded.future;

    // On at least iOS, it does not appear to be guaranteed that the native
    // code has the title when the page load completes. Execute some JavaScript
    // before checking the title to ensure that the page has been fully parsed
    // and processed.
    await controller.runJavaScript('1;');

    final String? title = await controller.getTitle();
    expect(title, 'Some title');
  });

  group(
    'Programmatic Scroll',
    () {
      testWidgets('setAndGetScrollPosition', (WidgetTester tester) async {
        const scrollTestPage = '''
        <!DOCTYPE html>
        <html>
          <head>
            <style>
              body {
                height: 100%;
                width: 100%;
              }
              #container{
                width:5000px;
                height:5000px;
            }
            </style>
          </head>
          <body>
            <div id="container"/>
          </body>
        </html>
      ''';

        final String scrollTestPageBase64 = base64Encode(
          const Utf8Encoder().convert(scrollTestPage),
        );

        final pageLoaded = Completer<void>();
        final controller = WebViewController();
        ScrollPositionChange? recordedPosition;
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
        await controller.setNavigationDelegate(
          NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
        );
        await controller.setOnScrollPositionChange((
          ScrollPositionChange contentOffsetChange,
        ) {
          recordedPosition = contentOffsetChange;
        });

        await controller.loadRequest(
          Uri.parse(
            'data:text/html;charset=utf-8;base64,$scrollTestPageBase64',
          ),
        );

        await tester.pumpWidget(WebViewWidget(controller: controller));

        await pageLoaded.future;

        await tester.pumpAndSettle(const Duration(seconds: 3));

        Offset scrollPos = await controller.getScrollPosition();

        // Check scrollTo()
        const xScroll = 123;
        const yScroll = 321;
        // Get the initial position; this ensures that scrollTo is actually
        // changing something, but also gives the native view's scroll position
        // time to settle.
        expect(scrollPos.dx, isNot(xScroll));
        expect(scrollPos.dy, isNot(yScroll));
        expect(recordedPosition?.x, isNot(xScroll));
        expect(recordedPosition?.y, isNot(yScroll));

        await controller.scrollTo(xScroll, yScroll);
        scrollPos = await controller.getScrollPosition();
        expect(scrollPos.dx, closeTo(xScroll, 1));
        expect(scrollPos.dy, closeTo(yScroll, 1));
        await _waitForCondition(
          () =>
              _isWithinOnePixel(recordedPosition?.x, xScroll) &&
              _isWithinOnePixel(recordedPosition?.y, yScroll),
          reason: 'The scrollTo callback did not report the final position.',
        );
        expect(recordedPosition?.x, closeTo(xScroll, 1));
        expect(recordedPosition?.y, closeTo(yScroll, 1));

        // Check scrollBy() (on top of scrollTo())
        await controller.scrollBy(xScroll, yScroll);
        scrollPos = await controller.getScrollPosition();
        expect(scrollPos.dx, closeTo(xScroll * 2, 1));
        expect(scrollPos.dy, closeTo(yScroll * 2, 1));
        await _waitForCondition(
          () =>
              _isWithinOnePixel(recordedPosition?.x, xScroll * 2) &&
              _isWithinOnePixel(recordedPosition?.y, yScroll * 2),
          reason: 'The scrollBy callback did not report the final position.',
        );
        expect(recordedPosition?.x, closeTo(xScroll * 2, 1));
        expect(recordedPosition?.y, closeTo(yScroll * 2, 1));
      });
    },
    // Scroll position is currently not implemented for macOS.
    // Flakes on iOS: https://github.com/flutter/flutter/issues/154826
    skip: Platform.isMacOS || Platform.isIOS,
  );

  group('NavigationDelegate', () {
    const blankPage = '<!DOCTYPE html><head></head><body></body></html>';
    final blankPageEncoded =
        'data:text/html;charset=utf-8;base64,'
        '${base64Encode(const Utf8Encoder().convert(blankPage))}';

    testWidgets('can allow requests', (WidgetTester tester) async {
      var pageLoaded = Completer<void>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => pageLoaded.complete(),
          onNavigationRequest: (NavigationRequest navigationRequest) {
            return navigationRequest.url.contains('youtube.com')
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await controller.loadRequest(Uri.parse(blankPageEncoded));

      await pageLoaded.future; // Wait for initial page load.

      pageLoaded = Completer<void>();
      await controller.runJavaScript('location.href = "$secondaryUrl"');
      await pageLoaded.future; // Wait for the next page load.

      final String? currentUrl = await controller.currentUrl();
      expect(currentUrl, secondaryUrl);
    });

    testWidgets('onWebResourceError', (WidgetTester tester) async {
      final errorCompleter = Completer<WebResourceError>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onWebResourceError: (WebResourceError error) {
            errorCompleter.complete(error);
          },
        ),
      );
      await controller.loadRequest(Uri.parse('https://www.notawebsite..com'));

      await tester.pumpWidget(WebViewWidget(controller: controller));

      final WebResourceError error = await errorCompleter.future;
      expect(error, isNotNull);
    });

    testWidgets('onWebResourceError is not called with valid url', (
      WidgetTester tester,
    ) async {
      final errorCompleter = Completer<WebResourceError>();
      final pageFinishCompleter = Completer<void>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => pageFinishCompleter.complete(),
          onWebResourceError: (WebResourceError error) {
            errorCompleter.complete(error);
          },
        ),
      );
      await controller.loadRequest(
        Uri.parse('data:text/html;charset=utf-8;base64,PCFET0NUWVBFIGh0bWw+'),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      expect(errorCompleter.future, doesNotComplete);
      await pageFinishCompleter.future;
    });

    testWidgets('can block requests', (WidgetTester tester) async {
      var pageLoaded = Completer<void>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => pageLoaded.complete(),
          onNavigationRequest: (NavigationRequest navigationRequest) {
            return navigationRequest.url.contains('youtube.com')
                ? NavigationDecision.prevent
                : NavigationDecision.navigate;
          },
        ),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await controller.loadRequest(Uri.parse(blankPageEncoded));

      await pageLoaded.future; // Wait for initial page load.

      pageLoaded = Completer<void>();
      await controller.runJavaScript(
        'location.href = "https://www.youtube.com/"',
      );

      // There should never be any second page load, since our new URL is
      // blocked. Still wait for a potential page change for some time in order
      // to give the test a chance to fail.
      await pageLoaded.future.timeout(
        const Duration(milliseconds: 500),
        onTimeout: () => '',
      );
      final String? currentUrl = await controller.currentUrl();
      expect(currentUrl, isNot(contains('youtube.com')));
    });

    testWidgets('onHttpError', (WidgetTester tester) async {
      final errorCompleter = Completer<HttpResponseError>();

      final controller = WebViewController();
      unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));

      final delegate = NavigationDelegate(
        onHttpError: (HttpResponseError error) {
          errorCompleter.complete(error);
        },
      );
      unawaited(controller.setNavigationDelegate(delegate));

      unawaited(controller.loadRequest(Uri.parse('$prefixUrl/favicon.ico')));

      await tester.pumpWidget(WebViewWidget(controller: controller));

      final HttpResponseError error = await errorCompleter.future;

      expect(error, isNotNull);
      expect(error.response?.statusCode, 404);
    });

    testWidgets('onHttpError is not called when no HTTP error is received', (
      WidgetTester tester,
    ) async {
      const testPage = '''
        <!DOCTYPE html><html>
        </head>
        <body>
        </body>
        </html>
      ''';

      final errorCompleter = Completer<HttpResponseError>();
      final pageFinishCompleter = Completer<void>();

      final controller = WebViewController();
      unawaited(controller.setJavaScriptMode(JavaScriptMode.unrestricted));

      final delegate = NavigationDelegate(
        onPageFinished: pageFinishCompleter.complete,
        onHttpError: (HttpResponseError error) {
          errorCompleter.complete(error);
        },
      );
      unawaited(controller.setNavigationDelegate(delegate));

      unawaited(controller.loadHtmlString(testPage));

      await tester.pumpWidget(WebViewWidget(controller: controller));

      expect(errorCompleter.future, doesNotComplete);
      await pageFinishCompleter.future;
    });

    testWidgets('supports asynchronous decisions', (WidgetTester tester) async {
      var pageLoaded = Completer<void>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => pageLoaded.complete(),
          onNavigationRequest: (NavigationRequest navigationRequest) async {
            NavigationDecision decision = NavigationDecision.prevent;
            decision = await Future<NavigationDecision>.delayed(
              const Duration(milliseconds: 10),
              () => NavigationDecision.navigate,
            );
            return decision;
          },
        ),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await controller.loadRequest(Uri.parse(blankPageEncoded));

      await pageLoaded.future; // Wait for initial page load.

      pageLoaded = Completer<void>();
      await controller.runJavaScript('location.href = "$secondaryUrl"');
      await pageLoaded.future; // Wait for second page to load.

      final String? currentUrl = await controller.currentUrl();
      expect(currentUrl, secondaryUrl);
    });

    testWidgets('can receive url changes', (WidgetTester tester) async {
      final pageLoaded = Completer<void>();

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
      );
      await controller.loadRequest(Uri.parse(blankPageEncoded));

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await pageLoaded.future;

      final urlChangeCompleter = Completer<String>();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (UrlChange change) {
            if (change.url == primaryUrl && !urlChangeCompleter.isCompleted) {
              urlChangeCompleter.complete(change.url);
            }
          },
        ),
      );

      await controller.runJavaScript('location.href = "$primaryUrl"');

      await expectLater(urlChangeCompleter.future, completion(primaryUrl));
    });

    testWidgets('can receive updates to history state', (
      WidgetTester tester,
    ) async {
      final pageLoaded = Completer<void>();

      final navigationDelegate = NavigationDelegate(
        onPageFinished: (_) => pageLoaded.complete(),
      );

      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(navigationDelegate);
      await controller.loadRequest(Uri.parse(primaryUrl));

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await pageLoaded.future;

      final urlChangeCompleter = Completer<String>();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (UrlChange change) {
            if (change.url == secondaryUrl && !urlChangeCompleter.isCompleted) {
              urlChangeCompleter.complete(change.url);
            }
          },
        ),
      );

      await controller.runJavaScript(
        'window.history.pushState({}, "", "secondary.txt");',
      );

      await expectLater(urlChangeCompleter.future, completion(secondaryUrl));
    });

    testWidgets('can receive HTTP basic auth requests', (
      WidgetTester tester,
    ) async {
      final authRequested = Completer<void>();
      final controller = WebViewController();

      await controller.setNavigationDelegate(
        NavigationDelegate(
          onHttpAuthRequest: (HttpAuthRequest request) =>
              authRequested.complete(),
        ),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await controller.loadRequest(Uri.parse(basicAuthUrl));

      await expectLater(authRequested.future, completes);
    });

    testWidgets('can authenticate to HTTP basic auth requests', (
      WidgetTester tester,
    ) async {
      final controller = WebViewController();
      final pageFinished = Completer<void>();

      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onHttpAuthRequest: (HttpAuthRequest request) => request.onProceed(
            const WebViewCredential(user: 'user', password: 'password'),
          ),
          onPageFinished: (_) {
            if (!pageFinished.isCompleted) {
              pageFinished.complete();
            }
          },
        ),
      );

      await tester.pumpWidget(WebViewWidget(controller: controller));

      await controller.loadRequest(Uri.parse(basicAuthUrl));

      await expectLater(pageFinished.future, completes);
      await _waitForCondition(() async {
        try {
          return await controller.runJavaScriptReturningResult(
                'document.body.innerText.includes("Authorized")',
              ) ==
              true;
        } on PlatformException {
          return false;
        }
      }, reason: 'The authenticated page did not finish loading.');
    });
  });

  testWidgets('target _blank opens in same window', (
    WidgetTester tester,
  ) async {
    final pageLoaded = Completer<void>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (controller.platform is LinuxWebViewController) {
      await (controller.platform as LinuxWebViewController)
          .setJavaScriptCanOpenWindowsAutomatically(true);
    }
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageLoaded.complete()),
    );

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await controller.runJavaScript('window.open("$primaryUrl", "_blank")');
    await pageLoaded.future;
    final String? currentUrl = await controller.currentUrl();
    expect(currentUrl, primaryUrl);
  });

  testWidgets('can open new window and go back', (WidgetTester tester) async {
    final pageLoads = StreamController<String>.broadcast();
    addTearDown(pageLoads.close);

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (controller.platform is LinuxWebViewController) {
      await (controller.platform as LinuxWebViewController)
          .setJavaScriptCanOpenWindowsAutomatically(true);
    }
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: pageLoads.add),
    );
    final primaryLoaded = pageLoads.stream.firstWhere(
      (String url) => url == primaryUrl,
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await primaryLoaded;
    await expectLater(controller.currentUrl(), completion(primaryUrl));

    final secondaryLoaded = pageLoads.stream.firstWhere(
      (String url) => url == secondaryUrl,
    );
    await controller.runJavaScript('window.open("$secondaryUrl")');
    await secondaryLoaded;
    await expectLater(controller.currentUrl(), completion(secondaryUrl));

    await expectLater(controller.canGoBack(), completion(true));
    final primaryReloaded = pageLoads.stream.firstWhere(
      (String url) => url == primaryUrl,
    );
    await controller.goBack();
    await primaryReloaded;
    await expectLater(controller.currentUrl(), completion(primaryUrl));
  });

  testWidgets('clearLocalStorage', (WidgetTester tester) async {
    var pageLoadCompleter = Completer<void>();

    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => pageLoadCompleter.complete()),
    );
    await controller.loadRequest(Uri.parse(primaryUrl));

    await tester.pumpWidget(WebViewWidget(controller: controller));

    await pageLoadCompleter.future;
    pageLoadCompleter = Completer<void>();

    await controller.runJavaScript('localStorage.setItem("myCat", "Tom");');
    final myCatItem =
        await controller.runJavaScriptReturningResult(
              'localStorage.getItem("myCat");',
            )
            as String;
    expect(myCatItem, _webViewString('Tom'));

    await controller.clearLocalStorage();

    // Reload page to have changes take effect.
    await controller.reload();
    await pageLoadCompleter.future;

    String? nullItem;
    try {
      nullItem =
          await controller.runJavaScriptReturningResult(
                'localStorage.getItem("myCat");',
              )
              as String;
    } on ArgumentError catch (exception) {
      if (_usesDecodedJavaScriptResults() &&
          exception.message.toString().toLowerCase().contains('null')) {
        nullItem = '<null>';
      } else {
        rethrow;
      }
    }
    expect(nullItem, _webViewNull());
  });
}

// JavaScript `null` evaluate to different string values per platform.
// This utility method returns the string boolean value of the current platform.
String _webViewNull() {
  if (_usesDecodedJavaScriptResults()) {
    return '<null>';
  }
  return 'null';
}

// JavaScript String evaluates to different strings depending on the platform.
// This utility method returns the string boolean value of the current platform.
String _webViewString(String value) {
  if (_usesDecodedJavaScriptResults()) {
    return value;
  }
  return '"$value"';
}

bool _usesDecodedJavaScriptResults() {
  return _isWKWebView() ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
}

bool _isWKWebView() {
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Future<int> _countWindowsRendererProcesses() async {
  final String script =
      r'''
$rootProcessId = __ROOT_PROCESS_ID__
$processes = @(Get-CimInstance Win32_Process)
$descendantIds = [System.Collections.Generic.HashSet[uint32]]::new()
$pendingIds = [System.Collections.Generic.Queue[uint32]]::new()
$pendingIds.Enqueue([uint32]$rootProcessId)
while ($pendingIds.Count -gt 0) {
  $parentId = $pendingIds.Dequeue()
  foreach ($process in $processes) {
    if ($process.ParentProcessId -eq $parentId -and
        $descendantIds.Add([uint32]$process.ProcessId)) {
      $pendingIds.Enqueue([uint32]$process.ProcessId)
    }
  }
}
@($processes | Where-Object {
  $descendantIds.Contains([uint32]$_.ProcessId) -and
  $_.Name -ieq 'msedgewebview2.exe' -and
  $_.CommandLine -match '--type=renderer'
}).Count
'''
          .replaceFirst('__ROOT_PROCESS_ID__', '$pid');
  final ProcessResult result = await Process.run('powershell.exe', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ]).timeout(const Duration(seconds: 10));
  if (result.exitCode != 0) {
    throw TestFailure(
      'Failed to inspect Windows WebView2 renderer processes: '
      '${result.stderr}',
    );
  }
  final int? count = int.tryParse('${result.stdout}'.trim());
  if (count == null) {
    throw TestFailure('Unexpected renderer process count: ${result.stdout}');
  }
  return count;
}

Future<void> _waitForCondition(
  FutureOr<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail(reason);
}

bool _isWithinOnePixel(double? value, num expected) {
  return value != null && (value - expected).abs() <= 1;
}

class ResizableWebView extends StatefulWidget {
  const ResizableWebView({
    super.key,
    required this.onResize,
    required this.onPageFinished,
  });

  final VoidCallback onResize;
  final VoidCallback onPageFinished;

  @override
  State<StatefulWidget> createState() => ResizableWebViewState();
}

class ResizableWebViewState extends State<ResizableWebView> {
  late final WebViewController controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(onPageFinished: (_) => widget.onPageFinished()),
    )
    ..addJavaScriptChannel(
      'Resize',
      onMessageReceived: (_) {
        widget.onResize();
      },
    )
    ..loadRequest(
      Uri.parse(
        'data:text/html;charset=utf-8;base64,${base64Encode(const Utf8Encoder().convert(resizePage))}',
      ),
    );

  double webViewWidth = 200;
  double webViewHeight = 200;

  static const String resizePage = '''
        <!DOCTYPE html><html>
        <head><title>Resize test</title>
          <script type="text/javascript">
            function onResize() {
              Resize.postMessage("resize");
            }
            function onLoad() {
              window.onresize = onResize;
            }
          </script>
        </head>
        <body onload="onLoad();" bgColor="blue">
        </body>
        </html>
      ''';

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: <Widget>[
          SizedBox(
            width: webViewWidth,
            height: webViewHeight,
            child: WebViewWidget(controller: controller),
          ),
          TextButton(
            key: const Key('resizeButton'),
            onPressed: () {
              setState(() {
                webViewWidth += 100.0;
                webViewHeight += 100.0;
              });
            },
            child: const Text('ResizeButton'),
          ),
        ],
      ),
    );
  }
}

Future<String> getTestVideoBase64() async {
  final ByteData videoData = await rootBundle.load('assets/sample_video.mp4');
  final String base64VideoData = base64Encode(Uint8List.view(videoData.buffer));
  final videoTest =
      '''
        <!DOCTYPE html><html>
        <head><title>Video auto play</title>
          <script type="text/javascript">
            function play() {
              var video = document.getElementById("video");
              video.play();
              video.addEventListener('timeupdate', videoTimeUpdateHandler, false);
            }
            function videoTimeUpdateHandler(e) {
              var video = document.getElementById("video");
              VideoTestTime.postMessage(video.currentTime);
            }
            function isPaused() {
              var video = document.getElementById("video");
              return video.paused;
            }
            function isFullScreen() {
              var video = document.getElementById("video");
              return video.webkitDisplayingFullscreen;
            }
          </script>
        </head>
        <body onload="play();">
        <video controls playsinline autoplay id="video">
          <source src="data:video/mp4;charset=utf-8;base64,$base64VideoData">
        </video>
        </body>
        </html>
      ''';
  return base64Encode(const Utf8Encoder().convert(videoTest));
}

class _X11Window {
  const _X11Window({
    required this.id,
    required this.width,
    required this.height,
  });

  final String id;
  final int width;
  final int height;
}

Future<bool> _hasExecutable(String executable) async {
  try {
    final ProcessResult result = await Process.run(executable, <String>[
      'version',
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

Future<ProcessResult> _runXdotool(List<String> arguments) async {
  final Process process = await Process.start('xdotool', arguments);
  final Future<String> stdout = utf8.decoder.bind(process.stdout).join();
  final Future<String> stderr = utf8.decoder.bind(process.stderr).join();
  late final int exitCode;
  try {
    exitCode = await process.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    process.kill();
    throw TestFailure('xdotool ${arguments.join(' ')} timed out.');
  }
  final String output = await stdout;
  final String error = await stderr;
  if (exitCode != 0) {
    throw TestFailure(
      'xdotool ${arguments.join(' ')} failed with exit code '
      '$exitCode: $error',
    );
  }
  return ProcessResult(process.pid, exitCode, output, error);
}

Future<_X11Window> _findCurrentX11Window() async {
  final ProcessResult searchResult = await _runXdotool(<String>[
    'search',
    '--onlyvisible',
    '--pid',
    '$pid',
  ]);
  final List<String> ids = '${searchResult.stdout}'
      .split(RegExp(r'\s+'))
      .where((String value) => value.isNotEmpty)
      .toList();
  if (ids.isEmpty) {
    throw TestFailure('No visible X11 window was found for process $pid.');
  }

  _X11Window? largestWindow;
  for (final String id in ids) {
    final ProcessResult geometryResult = await _runXdotool(<String>[
      'getwindowgeometry',
      '--shell',
      id,
    ]);
    final Map<String, int> geometry = <String, int>{};
    for (final String line in '${geometryResult.stdout}'.split('\n')) {
      final int separator = line.indexOf('=');
      if (separator <= 0) {
        continue;
      }
      final int? value = int.tryParse(line.substring(separator + 1));
      if (value != null) {
        geometry[line.substring(0, separator)] = value;
      }
    }
    final int width = geometry['WIDTH'] ?? 0;
    final int height = geometry['HEIGHT'] ?? 0;
    if (width <= 0 || height <= 0) {
      continue;
    }
    final _X11Window candidate = _X11Window(
      id: id,
      width: width,
      height: height,
    );
    if (largestWindow == null ||
        width * height > largestWindow.width * largestWindow.height) {
      largestWindow = candidate;
    }
  }
  return largestWindow ??
      (throw TestFailure('No usable X11 window geometry was found.'));
}

Future<void> _waitForJavaScriptResult(
  WebViewController controller,
  String expression,
  Object expected,
) {
  return _waitForJavaScriptPredicate(
    controller,
    expression,
    (Object value) => value == expected,
  );
}

Future<void> _waitForJavaScriptPredicate(
  WebViewController controller,
  String expression,
  bool Function(Object value) predicate,
) async {
  final Stopwatch stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < const Duration(seconds: 5)) {
    final Object value = await controller.runJavaScriptReturningResult(
      expression,
    );
    if (predicate(value)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TestFailure('JavaScript result did not satisfy: $expression');
}

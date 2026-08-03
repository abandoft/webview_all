import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_windows/src/windows_webview_api.g.dart';
import 'package:webview_all_windows/src/windows_webview_constants.dart';
import 'package:webview_all_windows/src/windows_webview_native.dart'
    as native_webview;
import 'package:webview_all_windows/src/windows_webview_types.dart'
    as native_types;
import 'package:webview_all_windows/webview_all_windows.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    _activeMockTextureId = ++_lastMockTextureId;
    _mockWindowsWebViewCreation();
  });

  tearDown(() {
    _clearWindowsWebViewCreationMock();
  });

  test('registerWith sets the Windows WebView platform implementation', () {
    final WebViewPlatform? previousInstance = WebViewPlatform.instance;
    addTearDown(() {
      if (previousInstance != null) {
        WebViewPlatform.instance = previousInstance;
      }
    });

    WindowsWebViewPlatform.registerWith();

    expect(WebViewPlatform.instance, isA<WindowsWebViewPlatform>());
  });

  test('creates Windows platform implementation objects', () {
    final platform = WindowsWebViewPlatform();

    expect(
      platform.createPlatformWebViewController(
        const PlatformWebViewControllerCreationParams(),
      ),
      isA<WindowsWebViewController>(),
    );
    expect(
      platform.createPlatformNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      ),
      isA<WindowsNavigationDelegate>(),
    );
    expect(
      platform.createPlatformWebViewWidget(
        PlatformWebViewWidgetCreationParams(
          controller: WindowsWebViewController(
            const PlatformWebViewControllerCreationParams(),
          ),
        ),
      ),
      isA<WindowsWebViewWidget>(),
    );
    expect(
      platform.createPlatformCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
      isA<WindowsWebViewCookieManager>(),
    );
  });

  test('native controller releases its WebView exactly once', () async {
    var disposeCallCount = 0;
    _mockWindowsWebViewCreation(
      onDisposeWebView: () {
        disposeCallCount++;
      },
    );
    final native_webview.WebviewController controller =
        native_webview.WebviewController();

    await controller.initialize();
    await controller.dispose();
    await controller.dispose();

    expect(disposeCallCount, 1);
  });

  test('native controller unregisters callbacks and closes streams', () async {
    final native_webview.WebviewController controller =
        native_webview.WebviewController();
    final List<Future<void>> streamDoneFutures = <Future<void>>[
      controller.url.drain<void>(),
      controller.loadingState.drain<void>(),
      controller.onDownloadEvent.drain<void>(),
      controller.onLoadError.drain<void>(),
      controller.httpResponseError.drain<void>(),
      controller.historyChanged.drain<void>(),
      controller.securityStateChanged.drain<void>(),
      controller.title.drain<void>(),
      controller.webMessage.drain<void>(),
      controller.containsFullScreenElementChanged.drain<void>(),
    ];

    await controller.initialize();
    await controller.dispose();
    await Future.wait<void>(streamDoneFutures);

    final ByteData? response = await _sendWindowsWebViewMethod(
      'permissionRequested',
      <String, Object?>{
        'url': 'https://example.test/camera',
        'permissionKind': native_types.WebviewPermissionKind.camera.index,
        'isUserInitiated': true,
      },
    );
    expect(response, isNull);
  });

  test('native controller can retry after an initialization failure', () async {
    _mockWindowsWebViewCreation(creationFailureCount: 1);
    final native_webview.WebviewController controller =
        native_webview.WebviewController();

    await expectLater(
      controller.initialize(),
      throwsA(
        isA<PlatformException>().having(
          (PlatformException error) => error.code,
          'code',
          'environment_creation_failed',
        ),
      ),
    );
    await controller.initialize();
    await controller.dispose();
  });

  testWidgets('initialization error offers install and refresh actions', (
    WidgetTester tester,
  ) async {
    var openDownloadPageCount = 0;
    _mockWindowsWebViewCreation(
      creationFailureCount: 1,
      onOpenWebView2DownloadPage: () {
        openDownloadPageCount += 1;
      },
    );
    final WindowsWebViewController controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final WindowsWebViewWidget platformWidget = WindowsWebViewWidget(
      PlatformWebViewWidgetCreationParams(controller: controller),
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: Builder(builder: platformWidget.build),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Install Webview2'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.text('Install Webview2'));
    await tester.pump();
    expect(openDownloadPageCount, 1);

    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();

    expect(find.text('Install Webview2'), findsNothing);
    expect(find.text('Refresh'), findsNothing);
    expect(find.byType(Texture), findsOneWidget);
  });

  test('rejects invalid generic cookies before native cookie calls', () async {
    final WindowsWebViewCookieManager cookieManager =
        WindowsWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    const List<WebViewCookie> invalidCookies = <WebViewCookie>[
      WebViewCookie(name: 'bad name', value: 'value', domain: '', path: '/'),
      WebViewCookie(
        name: 'session',
        value: 'value',
        domain: 'example.com;bad',
        path: '/',
      ),
      WebViewCookie(
        name: 'session',
        value: 'value',
        domain: '',
        path: 'relative',
      ),
      WebViewCookie(
        name: 'session',
        value: 'value',
        domain: '',
        path: '/bad;path',
      ),
    ];

    for (final WebViewCookie cookie in invalidCookies) {
      await expectLater(
        () => cookieManager.setCookie(cookie),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('rejects invalid Windows cookies before native cookie calls', () async {
    final WindowsWebViewCookieManager cookieManager =
        WindowsWebViewCookieManager(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    const List<WindowsWebViewCookie> invalidCookies = <WindowsWebViewCookie>[
      WindowsWebViewCookie(
        name: 'bad name',
        value: 'value',
        domain: '',
        path: '/',
      ),
      WindowsWebViewCookie(
        name: 'session',
        value: 'value',
        domain: 'example.com;bad',
        path: '/',
      ),
      WindowsWebViewCookie(
        name: 'session',
        value: 'value',
        domain: '',
        path: 'relative',
      ),
      WindowsWebViewCookie(
        name: 'session',
        value: 'value',
        domain: '',
        path: '/bad;path',
      ),
    ];

    for (final WindowsWebViewCookie cookie in invalidCookies) {
      await expectLater(
        () => cookieManager.setWindowsCookie(cookie),
        throwsA(isA<ArgumentError>()),
      );
    }
  });

  test('enables and dispatches JavaScript dialog callbacks', () async {
    final dialogCallbackFlags = <List<bool>>[];
    _mockWindowsWebViewCreation(
      onSetJavaScriptDialogCallbacksEnabled:
          ({required bool alert, required bool confirm, required bool prompt}) {
            dialogCallbackFlags.add(<bool>[alert, confirm, prompt]);
          },
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final alertRequests = <JavaScriptAlertDialogRequest>[];
    final confirmRequests = <JavaScriptConfirmDialogRequest>[];
    final promptRequests = <JavaScriptTextInputDialogRequest>[];

    await controller.setOnJavaScriptAlertDialog((
      JavaScriptAlertDialogRequest request,
    ) async {
      alertRequests.add(request);
    });
    await controller.setOnJavaScriptConfirmDialog((
      JavaScriptConfirmDialogRequest request,
    ) async {
      confirmRequests.add(request);
      return false;
    });
    await controller.setOnJavaScriptTextInputDialog((
      JavaScriptTextInputDialogRequest request,
    ) async {
      promptRequests.add(request);
      return 'typed value';
    });

    expect(dialogCallbackFlags, <List<bool>>[
      <bool>[true, false, false],
      <bool>[true, true, false],
      <bool>[true, true, true],
    ]);

    final Object? alertResponse = await _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'alert',
        'message': 'hello alert',
        'url': 'https://example.test/alert',
      },
    );
    expect(alertResponse, <String, Object?>{'action': 'accept'});
    expect(alertRequests, hasLength(1));
    expect(alertRequests.single.message, 'hello alert');
    expect(alertRequests.single.url, 'https://example.test/alert');

    final Object? confirmResponse = await _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'confirm',
        'message': 'continue?',
        'url': 'https://example.test/confirm',
      },
    );
    expect(confirmResponse, <String, Object?>{'action': 'cancel'});
    expect(confirmRequests, hasLength(1));
    expect(confirmRequests.single.message, 'continue?');
    expect(confirmRequests.single.url, 'https://example.test/confirm');

    final Object? promptResponse = await _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'prompt',
        'message': 'name',
        'url': 'https://example.test/prompt',
        'defaultText': 'default value',
      },
    );
    expect(promptResponse, <String, Object?>{
      'action': 'confirm',
      'text': 'typed value',
    });
    expect(promptRequests, hasLength(1));
    expect(promptRequests.single.message, 'name');
    expect(promptRequests.single.url, 'https://example.test/prompt');
    expect(promptRequests.single.defaultText, 'default value');
  });

  test(
    'dispatches HTTP auth requests through the navigation delegate',
    () async {
      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final delegate = WindowsNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      final requests = <HttpAuthRequest>[];

      await delegate.setOnHttpAuthRequest((HttpAuthRequest request) {
        requests.add(request);
        request.onProceed(
          const WebViewCredential(user: 'test-user', password: 'test-password'),
        );
      });
      await controller.setPlatformNavigationDelegate(delegate);

      final Object? response = await _invokeWindowsWebViewMethod(
        'httpAuthRequested',
        <String, Object?>{
          'url': 'https://secure.example.test/private',
          'challenge': 'Basic realm="Restricted Area"',
        },
      );

      expect(response, <String, Object?>{
        'action': 'proceed',
        'user': 'test-user',
        'password': 'test-password',
      });
      expect(requests, hasLength(1));
      expect(requests.single.host, 'secure.example.test');
      expect(requests.single.realm, 'Restricted Area');
    },
  );

  test('cancels HTTP auth requests without a handler', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    await controller.currentUrl();

    final Object? response = await _invokeWindowsWebViewMethod(
      'httpAuthRequested',
      <String, Object?>{
        'url': 'https://secure.example.test/private',
        'challenge': 'Basic realm="Restricted Area"',
      },
    );

    expect(response, <String, Object?>{'action': 'cancel'});
  });

  test('dispatches SSL auth errors through the navigation delegate', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = WindowsNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final errors = <PlatformSslAuthError>[];

    await delegate.setOnSSlAuthError((PlatformSslAuthError error) {
      errors.add(error);
      unawaited(error.proceed());
    });
    await controller.setPlatformNavigationDelegate(delegate);

    final Object? response = await _invokeWindowsWebViewMethod(
      'sslAuthError',
      <String, Object?>{
        'url': 'https://expired.example.test/',
        'errorStatus': 2,
      },
    );

    expect(response, <String, Object?>{'action': 'proceed'});
    expect(errors, hasLength(1));
    expect(errors.single.certificate, isNull);
    expect(
      errors.single.description,
      contains('https://expired.example.test/'),
    );
    expect(
      errors.single.description,
      contains('WebErrorStatusCertificateExpired'),
    );
  });

  test('cancels SSL auth errors without a handler', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    await controller.currentUrl();

    final Object? response = await _invokeWindowsWebViewMethod(
      'sslAuthError',
      <String, Object?>{
        'url': 'https://expired.example.test/',
        'errorStatus': 2,
      },
    );

    expect(response, <String, Object?>{'action': 'cancel'});
  });

  test('loads requests with method headers and body', () async {
    final loadRequests = <WindowsLoadRequestData>[];
    _mockWindowsWebViewCreation(onLoadRequest: loadRequests.add);

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final body = Uint8List.fromList(<int>[1, 2, 3]);

    await controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.test/form'),
        method: LoadRequestMethod.post,
        headers: const <String, String>{
          'X-Test': 'yes',
          'Content-Type': 'application/octet-stream',
        },
        body: body,
      ),
    );

    expect(loadRequests, hasLength(1));
    expect(loadRequests.single.url, 'https://example.test/form');
    expect(loadRequests.single.method, 'post');
    expect(
      loadRequests.single.headers,
      'X-Test: yes\r\nContent-Type: application/octet-stream\r\n',
    );
    expect(loadRequests.single.body, orderedEquals(<int>[1, 2, 3]));
  });

  test('loads files with params through virtual host mapping', () async {
    final loadUrls = <String>[];
    final mappings = <WindowsVirtualHostMappingData>[];
    _mockWindowsWebViewCreation(
      onLoadUrl: loadUrls.add,
      onSetVirtualHostNameMapping: mappings.add,
    );
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'webview_all_windows_test_',
    );
    addTearDown(() {
      tempDir.deleteSync(recursive: true);
    });
    final File file = File('${tempDir.path}/index.html')
      ..writeAsStringSync('<html></html>');

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.loadFileWithParams(
      LoadFileParams(absoluteFilePath: file.path),
    );

    expect(mappings, hasLength(1));
    expect(mappings.single.hostName, 'app-file.webview.flutter.dev');
    expect(mappings.single.path, file.parent.absolute.path);
    expect(mappings.single.accessKind, 1);
    expect(loadUrls, <String>[
      Uri.https('app-file.webview.flutter.dev', '/index.html').toString(),
    ]);
  });

  test('rejects malformed request headers before native navigation', () async {
    final loadRequests = <WindowsLoadRequestData>[];
    _mockWindowsWebViewCreation(onLoadRequest: loadRequests.add);

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await expectLater(
      () => controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/'),
          headers: const <String, String>{'X-Test\r\nBad': 'value'},
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(loadRequests, isEmpty);
  });

  test('dispatches HTTP response errors from Windows events', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = WindowsNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final errors = <HttpResponseError>[];

    await delegate.setOnHttpError(errors.add);
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitWindowsWebViewEvent(<String, Object?>{
      'type': 'httpError',
      'value': <String, Object?>{
        'url': 'https://example.test/missing',
        'method': 'POST',
        'requestHeaders': <String, Object?>{'Accept': 'text/plain'},
        'statusCode': 404,
        'responseHeaders': <String, Object?>{'Content-Type': 'text/plain'},
        'reasonPhrase': 'Not Found',
      },
    });

    expect(errors, hasLength(1));
    expect(
      errors.single.request?.uri,
      Uri.parse('https://example.test/missing'),
    );
    expect(errors.single.request, isA<WindowsWebResourceRequest>());
    final WindowsWebResourceRequest request =
        errors.single.request! as WindowsWebResourceRequest;
    expect(request.method, 'POST');
    expect(request.headers, const <String, String>{'Accept': 'text/plain'});
    expect(
      errors.single.response?.uri,
      Uri.parse('https://example.test/missing'),
    );
    expect(errors.single.response, isA<WindowsWebResourceResponse>());
    final WindowsWebResourceResponse response =
        errors.single.response! as WindowsWebResourceResponse;
    expect(errors.single.response?.statusCode, 404);
    expect(response.headers, const <String, String>{
      'Content-Type': 'text/plain',
    });
    expect(response.reasonPhrase, 'Not Found');
    expect(response.mimeType, 'text/plain');
  });

  test('dispatches web resource errors from Windows events', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = WindowsNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final errors = <WebResourceError>[];

    await controller.currentUrl();
    await delegate.setOnWebResourceError(errors.add);
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitWindowsWebViewEvent(<String, Object?>{
      'type': 'urlChanged',
      'value': 'https://example.test/slow',
    });
    await _emitWindowsWebViewEvent(<String, Object?>{
      'type': 'onLoadError',
      'value': native_types.WebErrorStatus.WebErrorStatusTimeout.index,
    });

    expect(errors, hasLength(1));
    expect(errors.single, isA<WindowsWebResourceError>());
    final WindowsWebResourceError error =
        errors.single as WindowsWebResourceError;
    expect(
      error.errorCode,
      native_types.WebErrorStatus.WebErrorStatusTimeout.index,
    );
    expect(error.description, 'WebErrorStatusTimeout');
    expect(error.errorType, WebResourceErrorType.timeout);
    expect(error.isForMainFrame, isTrue);
    expect(error.url, 'https://example.test/slow');
  });

  test(
    'dispatches console and scroll messages from Windows web messages',
    () async {
      final List<String> addedScripts = <String>[];
      _mockWindowsWebViewCreation(
        onAddScript: (String script) {
          addedScripts.add(script);
          return 'script-${addedScripts.length}';
        },
      );

      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final List<JavaScriptConsoleMessage> consoleMessages =
          <JavaScriptConsoleMessage>[];
      final List<ScrollPositionChange> scrollChanges = <ScrollPositionChange>[];

      await controller.setOnConsoleMessage(consoleMessages.add);
      await controller.setOnScrollPositionChange(scrollChanges.add);

      expect(addedScripts, hasLength(2));
      expect(addedScripts[0], contains('__flutterWindowsConsoleHookInstalled'));
      expect(addedScripts[0], contains('function stringifyArg'));
      expect(
        addedScripts[0],
        contains('return json === undefined ? String(arg) : json'),
      );
      expect(addedScripts[0], contains('catch (_)'));
      expect(addedScripts[1], contains('__flutterWindowsScrollHookInstalled'));

      await _emitWindowsWebViewEvent(<String, Object?>{
        'type': 'webMessageReceived',
        'value': jsonEncode(<String, Object?>{
          '__windows_webview_all_type': 'consoleMessage',
          'level': 'warning',
          'message': 'careful',
        }),
      });
      await _emitWindowsWebViewEvent(<String, Object?>{
        'type': 'webMessageReceived',
        'value': jsonEncode(<String, Object?>{
          '__windows_webview_all_type': 'consoleMessage',
          'level': 'debug',
          'message': 'details',
        }),
      });
      await _emitWindowsWebViewEvent(<String, Object?>{
        'type': 'webMessageReceived',
        'value': jsonEncode(<String, Object?>{
          '__windows_webview_all_type': 'scrollPositionChange',
          'x': 12.5,
          'y': 34,
        }),
      });
      await _flushAsyncEvents();

      expect(consoleMessages, hasLength(2));
      expect(consoleMessages[0].level, JavaScriptLogLevel.warning);
      expect(consoleMessages[0].message, 'careful');
      expect(consoleMessages[1].level, JavaScriptLogLevel.debug);
      expect(consoleMessages[1].message, 'details');
      expect(scrollChanges, hasLength(1));
      expect(scrollChanges.single.x, 12.5);
      expect(scrollChanges.single.y, 34);
    },
  );

  test('supports and applies scrollbar visibility settings', () async {
    final addedScripts = <String>[];
    final removedScriptIds = <String>[];
    final executedScripts = <String>[];
    _mockWindowsWebViewCreation(
      onAddScript: (String script) {
        addedScripts.add(script);
        return 'script-${addedScripts.length}';
      },
      onRemoveScript: removedScriptIds.add,
      onExecuteScript: (String script) {
        executedScripts.add(script);
        return 'null';
      },
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.supportsSetScrollBarsEnabled(), isTrue);

    await controller.setVerticalScrollBarEnabled(false);
    expect(addedScripts, hasLength(1));
    expect(addedScripts.single, contains('::-webkit-scrollbar:vertical'));
    expect(
      addedScripts.single,
      isNot(contains('::-webkit-scrollbar:horizontal')),
    );
    expect(executedScripts.single, addedScripts.single);

    await controller.setHorizontalScrollBarEnabled(false);
    expect(removedScriptIds, <String>['script-1']);
    expect(addedScripts, hasLength(2));
    expect(addedScripts.last, contains('::-webkit-scrollbar:vertical'));
    expect(addedScripts.last, contains('::-webkit-scrollbar:horizontal'));

    await controller.setVerticalScrollBarEnabled(true);
    expect(removedScriptIds, <String>['script-1', 'script-2']);
    expect(addedScripts, hasLength(3));
    expect(addedScripts.last, isNot(contains('::-webkit-scrollbar:vertical')));
    expect(addedScripts.last, contains('::-webkit-scrollbar:horizontal'));

    await controller.setHorizontalScrollBarEnabled(true);
    expect(removedScriptIds, <String>['script-1', 'script-2', 'script-3']);
    expect(addedScripts, hasLength(3));
    expect(executedScripts.last, contains('if (!css)'));
  });

  test('sets JavaScript execution mode through WebView2 settings', () async {
    final javaScriptEnabledValues = <bool>[];
    _mockWindowsWebViewCreation(
      onSetJavaScriptEnabled: javaScriptEnabledValues.add,
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.setJavaScriptMode(JavaScriptMode.disabled);
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

    expect(javaScriptEnabledValues, <bool>[false, true]);
  });

  test(
    'sets, resets, and reads the user agent through WebView2 settings',
    () async {
      final userAgentValues = <String?>[];
      _mockWindowsWebViewCreation(
        onSetUserAgent: userAgentValues.add,
        onGetUserAgent: () => 'DefaultWebView2/1.0',
      );

      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );

      await controller.setUserAgent('CustomAgent/1.0');
      expect(await controller.getUserAgent(), 'CustomAgent/1.0');

      await controller.setUserAgent(null);
      expect(await controller.getUserAgent(), 'DefaultWebView2/1.0');
      expect(userAgentValues, <String?>['CustomAgent/1.0', null]);
    },
  );

  test('clears local storage through WebView2 profile data', () async {
    var clearLocalStorageCount = 0;
    final executedScripts = <String>[];
    _mockWindowsWebViewCreation(
      onClearLocalStorage: () {
        clearLocalStorageCount += 1;
      },
      onExecuteScript: (String script) {
        executedScripts.add(script);
        return 'null';
      },
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.clearLocalStorage();

    expect(clearLocalStorageCount, 1);
    expect(executedScripts, isEmpty);
  });

  test('sets zoom control mode through WebView2 settings', () async {
    final zoomControlEnabledValues = <bool>[];
    _mockWindowsWebViewCreation(
      onSetZoomControlEnabled: zoomControlEnabledValues.add,
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.enableZoom(false);
    await controller.enableZoom(true);

    expect(zoomControlEnabledValues, <bool>[false, true]);
  });

  test(
    'dispatches Windows permission requests and returns decisions',
    () async {
      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final requests = <PlatformWebViewPermissionRequest>[];

      await controller.setOnPlatformPermissionRequest(requests.add);

      final Future<Object?> cameraResult =
          _invokeWindowsWebViewMethod('permissionRequested', <String, Object?>{
            'url': 'https://example.test/camera',
            'permissionKind': native_types.WebviewPermissionKind.camera.index,
            'isUserInitiated': true,
          });
      await _flushAsyncEvents();
      expect(requests, hasLength(1));
      expect(requests.single.types, <WebViewPermissionResourceType>{
        WebViewPermissionResourceType.camera,
      });

      await requests.single.grant();
      await requests.single.deny();
      expect(await cameraResult, isTrue);

      final Future<Object?> microphoneResult = _invokeWindowsWebViewMethod(
        'permissionRequested',
        <String, Object?>{
          'url': 'https://example.test/microphone',
          'permissionKind': native_types.WebviewPermissionKind.microphone.index,
          'isUserInitiated': true,
        },
      );
      await _flushAsyncEvents();
      expect(requests, hasLength(2));
      expect(requests.last.types, <WebViewPermissionResourceType>{
        WebViewPermissionResourceType.microphone,
      });

      await requests.last.deny();
      await requests.last.grant();
      expect(await microphoneResult, isFalse);
    },
  );

  test(
    'uses the default Windows decision for unsupported permissions',
    () async {
      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      var callbackCalled = false;

      await controller.setOnPlatformPermissionRequest((_) {
        callbackCalled = true;
      });

      final Object? unsupportedResult = await _invokeWindowsWebViewMethod(
        'permissionRequested',
        <String, Object?>{
          'url': 'https://example.test/geolocation',
          'permissionKind':
              native_types.WebviewPermissionKind.geoLocation.index,
          'isUserInitiated': true,
        },
      );
      final Object? invalidResult = await _invokeWindowsWebViewMethod(
        'permissionRequested',
        <String, Object?>{
          'url': 'https://example.test/invalid',
          'permissionKind': 999,
          'isUserInitiated': true,
        },
      );

      expect(callbackCalled, isFalse);
      expect(unsupportedResult, isNull);
      expect(invalidResult, isNull);
    },
  );

  testWidgets('uses safe defaults when application decisions do not complete', (
    WidgetTester tester,
  ) async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = WindowsNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final Completer<void> pendingAlert = Completer<void>();
    final Completer<bool> pendingConfirm = Completer<bool>();
    final Completer<String> pendingPrompt = Completer<String>();

    await controller.setOnJavaScriptAlertDialog((_) => pendingAlert.future);
    await controller.setOnJavaScriptConfirmDialog((_) => pendingConfirm.future);
    await controller.setOnJavaScriptTextInputDialog(
      (_) => pendingPrompt.future,
    );
    await controller.setOnPlatformPermissionRequest((_) {});
    await delegate.setOnHttpAuthRequest((_) {});
    await delegate.setOnSSlAuthError((_) {});
    await controller.setPlatformNavigationDelegate(delegate);

    final Future<Object?> dialogResult = _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'alert',
        'message': 'waiting',
        'url': 'https://example.test/dialog',
      },
    );
    final Future<Object?> confirmResult = _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'confirm',
        'message': 'waiting',
        'url': 'https://example.test/dialog',
      },
    );
    final Future<Object?> promptResult = _invokeWindowsWebViewMethod(
      'javaScriptDialogRequested',
      <String, Object?>{
        'dialogType': 'prompt',
        'message': 'waiting',
        'url': 'https://example.test/dialog',
        'defaultText': 'default',
      },
    );
    final Future<Object?> permissionResult =
        _invokeWindowsWebViewMethod('permissionRequested', <String, Object?>{
          'url': 'https://example.test/camera',
          'permissionKind': native_types.WebviewPermissionKind.camera.index,
          'isUserInitiated': true,
        });
    final Future<Object?> httpAuthResult =
        _invokeWindowsWebViewMethod('httpAuthRequested', <String, Object?>{
          'url': 'https://secure.example.test/private',
          'challenge': 'Basic realm="Restricted Area"',
        });
    final Future<Object?> sslAuthResult = _invokeWindowsWebViewMethod(
      'sslAuthError',
      <String, Object?>{
        'url': 'https://expired.example.test/',
        'errorStatus': 2,
      },
    );

    await tester.pump();
    await tester.pump(const Duration(seconds: 30));

    expect(await dialogResult, isNull);
    expect(await confirmResult, isNull);
    expect(await promptResult, isNull);
    expect(await permissionResult, isFalse);
    expect(await httpAuthResult, <String, Object?>{'action': 'cancel'});
    expect(await sslAuthResult, <String, Object?>{'action': 'cancel'});
  });

  test('uses safe defaults when decision callbacks throw', () async {
    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final delegate = WindowsNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final DebugPrintCallback previousDebugPrint = debugPrint;
    final List<String> messages = <String>[];
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    await controller.setOnJavaScriptAlertDialog((_) {
      throw StateError('alert failure\nsecond line');
    });
    await controller.setOnPlatformPermissionRequest((_) {
      throw StateError('permission failure\nsecond line');
    });
    await delegate.setOnHttpAuthRequest((_) {
      throw StateError('HTTP auth failure\nsecond line');
    });
    await delegate.setOnSSlAuthError((_) {
      throw StateError('SSL auth failure\nsecond line');
    });
    await controller.setPlatformNavigationDelegate(delegate);

    expect(
      await _invokeWindowsWebViewMethod(
        'javaScriptDialogRequested',
        <String, Object?>{
          'dialogType': 'alert',
          'message': 'failing',
          'url': 'https://example.test/dialog',
        },
      ),
      isNull,
    );
    expect(
      await _invokeWindowsWebViewMethod(
        'permissionRequested',
        <String, Object?>{
          'url': 'https://example.test/camera',
          'permissionKind': native_types.WebviewPermissionKind.camera.index,
          'isUserInitiated': true,
        },
      ),
      isFalse,
    );
    expect(
      await _invokeWindowsWebViewMethod('httpAuthRequested', <String, Object?>{
        'url': 'https://secure.example.test/private',
        'challenge': 'Basic realm="Restricted Area"',
      }),
      <String, Object?>{'action': 'cancel'},
    );
    expect(
      await _invokeWindowsWebViewMethod('sslAuthError', <String, Object?>{
        'url': 'https://expired.example.test/',
        'errorStatus': 2,
      }),
      <String, Object?>{'action': 'cancel'},
    );
    expect(messages, hasLength(4));
    expect(messages.every((String message) => !message.contains('\n')), true);
  });

  test(
    'contains callback failures and preserves completed decisions',
    () async {
      final controller = WindowsWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final delegate = WindowsNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      );
      final DebugPrintCallback previousDebugPrint = debugPrint;
      final List<String> messages = <String>[];
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          messages.add(message);
        }
      };
      addTearDown(() {
        debugPrint = previousDebugPrint;
      });

      await controller.setOnJavaScriptAlertDialog((_) {
        throw StateError('alert failure\nsecond line');
      });
      await controller.setOnPlatformPermissionRequest((request) {
        request.grant();
        throw StateError('permission failure after decision\nsecond line');
      });
      await delegate.setOnHttpAuthRequest((HttpAuthRequest request) {
        request.onProceed(
          const WebViewCredential(user: 'user', password: 'password'),
        );
        throw StateError('HTTP auth failure after decision\nsecond line');
      });
      await delegate.setOnSSlAuthError((PlatformSslAuthError error) {
        unawaited(error.proceed());
        throw StateError('SSL auth failure after decision\nsecond line');
      });
      await controller.setPlatformNavigationDelegate(delegate);

      expect(
        await _invokeWindowsWebViewMethod(
          'javaScriptDialogRequested',
          <String, Object?>{
            'dialogType': 'alert',
            'message': 'failing',
            'url': 'https://example.test/dialog',
          },
        ),
        isNull,
      );
      expect(
        await _invokeWindowsWebViewMethod(
          'permissionRequested',
          <String, Object?>{
            'url': 'https://example.test/camera',
            'permissionKind': native_types.WebviewPermissionKind.camera.index,
            'isUserInitiated': true,
          },
        ),
        isTrue,
      );
      expect(
        await _invokeWindowsWebViewMethod(
          'httpAuthRequested',
          <String, Object?>{
            'url': 'https://secure.example.test/private',
            'challenge': 'Basic realm="Restricted Area"',
          },
        ),
        <String, Object?>{
          'action': 'proceed',
          'user': 'user',
          'password': 'password',
        },
      );
      expect(
        await _invokeWindowsWebViewMethod('sslAuthError', <String, Object?>{
          'url': 'https://expired.example.test/',
          'errorStatus': 2,
        }),
        <String, Object?>{'action': 'proceed'},
      );
      expect(messages, hasLength(4));
      expect(
        messages,
        containsAll(<Matcher>[
          contains('JavaScript alert callback failed'),
          contains('permission callback failed'),
          contains('HTTP authentication callback failed'),
          contains('SSL authentication callback failed'),
        ]),
      );
      expect(messages.every((String message) => !message.contains('\n')), true);
    },
  );

  test('applies overscroll mode stylesheet across page loads', () async {
    final addedScripts = <String>[];
    final removedScriptIds = <String>[];
    final executedScripts = <String>[];
    _mockWindowsWebViewCreation(
      onAddScript: (String script) {
        addedScripts.add(script);
        return 'script-${addedScripts.length}';
      },
      onRemoveScript: removedScriptIds.add,
      onExecuteScript: (String script) {
        executedScripts.add(script);
        return 'null';
      },
    );

    final controller = WindowsWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.setOverScrollMode(WebViewOverScrollMode.never);
    expect(addedScripts, hasLength(1));
    expect(addedScripts.single, contains('__flutter_webview_all_overscroll'));
    expect(addedScripts.single, contains('const value = "none"'));
    expect(executedScripts.single, addedScripts.single);

    await controller.setOverScrollMode(WebViewOverScrollMode.ifContentScrolls);
    expect(removedScriptIds, <String>['script-1']);
    expect(addedScripts, hasLength(2));
    expect(addedScripts.last, contains('const value = "contain"'));
    expect(executedScripts.last, addedScripts.last);

    await controller.setOverScrollMode(WebViewOverScrollMode.always);
    expect(removedScriptIds, <String>['script-1', 'script-2']);
    expect(addedScripts, hasLength(2));
    expect(executedScripts.last, contains('const value = ""'));
    expect(executedScripts.last, contains('style.remove()'));
  });
}

void _mockWindowsWebViewCreation({
  int creationFailureCount = 0,
  void Function()? onOpenWebView2DownloadPage,
  void Function(WindowsLoadRequestData request)? onLoadRequest,
  void Function(String url)? onLoadUrl,
  void Function(WindowsVirtualHostMappingData mapping)?
  onSetVirtualHostNameMapping,
  String? Function(String script)? onAddScript,
  void Function(String scriptId)? onRemoveScript,
  String Function(String script)? onExecuteScript,
  void Function(String? userAgent)? onSetUserAgent,
  String? Function()? onGetUserAgent,
  void Function()? onClearLocalStorage,
  void Function(bool enabled)? onSetJavaScriptEnabled,
  void Function(bool enabled)? onSetZoomControlEnabled,
  void Function()? onDisposeWebView,
  void Function({
    required bool alert,
    required bool confirm,
    required bool prompt,
  })?
  onSetJavaScriptDialogCallbacksEnabled,
}) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var remainingCreationFailures = creationFailureCount;
  messenger.setMockMessageHandler(_hostApiChannel('createWebView'), (
    ByteData? message,
  ) async {
    if (remainingCreationFailures > 0) {
      remainingCreationFailures -= 1;
      return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
        'environment_creation_failed',
        'The WebView2 Runtime could not be initialized.',
        null,
      ]);
    }
    return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
      WindowsCreateWebViewResult(textureId: _activeMockTextureId),
    ]);
  });
  messenger.setMockMessageHandler(_hostApiChannel('openWebView2DownloadPage'), (
    ByteData? message,
  ) async {
    onOpenWebView2DownloadPage?.call();
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('setPopupWindowPolicy'), (
    ByteData? message,
  ) async {
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('loadRequest'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    onLoadRequest?.call(args[1]! as WindowsLoadRequestData);
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('loadUrl'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    onLoadUrl?.call(args[1]! as String);
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(
    _hostApiChannel('setVirtualHostNameMapping'),
    (ByteData? message) async {
      final args = _decodePigeonArgs(message);
      onSetVirtualHostNameMapping?.call(
        args[1]! as WindowsVirtualHostMappingData,
      );
      return _encodePigeonSuccess();
    },
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('addScriptToExecuteOnDocumentCreated'),
    (ByteData? message) async {
      final args = _decodePigeonArgs(message);
      final scriptId = onAddScript?.call(args[1]! as String) ?? 'script-id';
      return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
        scriptId,
      ]);
    },
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('removeScriptToExecuteOnDocumentCreated'),
    (ByteData? message) async {
      final args = _decodePigeonArgs(message);
      onRemoveScript?.call(args[1]! as String);
      return _encodePigeonSuccess();
    },
  );
  messenger.setMockMessageHandler(_hostApiChannel('executeScript'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    final result = onExecuteScript?.call(args[1]! as String) ?? 'null';
    return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
      result,
    ]);
  });
  messenger.setMockMessageHandler(_hostApiChannel('setUserAgent'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    onSetUserAgent?.call(args[1] as String?);
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('getUserAgent'), (
    ByteData? message,
  ) async {
    return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
      onGetUserAgent?.call(),
    ]);
  });
  messenger.setMockMessageHandler(_hostApiChannel('clearLocalStorage'), (
    ByteData? message,
  ) async {
    onClearLocalStorage?.call();
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('setJavaScriptEnabled'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    onSetJavaScriptEnabled?.call(args[1]! as bool);
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(_hostApiChannel('setZoomControlEnabled'), (
    ByteData? message,
  ) async {
    final args = _decodePigeonArgs(message);
    onSetZoomControlEnabled?.call(args[1]! as bool);
    return _encodePigeonSuccess();
  });
  messenger.setMockMessageHandler(
    _hostApiChannel('setJavaScriptDialogCallbacksEnabled'),
    (ByteData? message) async {
      final args = _decodePigeonArgs(message);
      onSetJavaScriptDialogCallbacksEnabled?.call(
        alert: args[1]! as bool,
        confirm: args[2]! as bool,
        prompt: args[3]! as bool,
      );
      return _encodePigeonSuccess();
    },
  );
  messenger.setMockMessageHandler(_hostApiChannel('disposeWebView'), (
    ByteData? message,
  ) async {
    onDisposeWebView?.call();
    return _encodePigeonSuccess();
  });

  messenger.setMockMethodCallHandler(
    MethodChannel('$windowsWebViewChannelPrefix/$_activeMockTextureId/events'),
    (MethodCall methodCall) async => null,
  );
}

int _lastMockTextureId = 0;
int _activeMockTextureId = 0;

void _clearWindowsWebViewCreationMock() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMessageHandler(_hostApiChannel('createWebView'), null);
  messenger.setMockMessageHandler(
    _hostApiChannel('openWebView2DownloadPage'),
    null,
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('setPopupWindowPolicy'),
    null,
  );
  messenger.setMockMessageHandler(_hostApiChannel('loadRequest'), null);
  messenger.setMockMessageHandler(_hostApiChannel('loadUrl'), null);
  messenger.setMockMessageHandler(
    _hostApiChannel('setVirtualHostNameMapping'),
    null,
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('addScriptToExecuteOnDocumentCreated'),
    null,
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('removeScriptToExecuteOnDocumentCreated'),
    null,
  );
  messenger.setMockMessageHandler(_hostApiChannel('executeScript'), null);
  messenger.setMockMessageHandler(_hostApiChannel('setUserAgent'), null);
  messenger.setMockMessageHandler(_hostApiChannel('getUserAgent'), null);
  messenger.setMockMessageHandler(_hostApiChannel('clearLocalStorage'), null);
  messenger.setMockMessageHandler(
    _hostApiChannel('setJavaScriptEnabled'),
    null,
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('setZoomControlEnabled'),
    null,
  );
  messenger.setMockMessageHandler(
    _hostApiChannel('setJavaScriptDialogCallbacksEnabled'),
    null,
  );
  messenger.setMockMessageHandler(_hostApiChannel('disposeWebView'), null);
  messenger.setMockMethodCallHandler(
    MethodChannel('$windowsWebViewChannelPrefix/$_activeMockTextureId/events'),
    null,
  );
}

String _hostApiChannel(String method) =>
    'dev.flutter.pigeon.webview_all_windows.WindowsWebViewHostApi.$method';

ByteData? _encodePigeonSuccess() {
  return WindowsWebViewHostApi.pigeonChannelCodec.encodeMessage(<Object?>[
    null,
  ]);
}

List<Object?> _decodePigeonArgs(ByteData? message) {
  return WindowsWebViewHostApi.pigeonChannelCodec.decodeMessage(message!)
      as List<Object?>;
}

Future<Object?> _invokeWindowsWebViewMethod(
  String method,
  Map<String, Object?> arguments,
) async {
  final ByteData? response = await _sendWindowsWebViewMethod(method, arguments);
  return const StandardMethodCodec().decodeEnvelope(response!);
}

Future<ByteData?> _sendWindowsWebViewMethod(
  String method,
  Map<String, Object?> arguments,
) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final completer = Completer<ByteData?>();
  await messenger.handlePlatformMessage(
    '$windowsWebViewChannelPrefix/$_activeMockTextureId',
    const StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments)),
    completer.complete,
  );
  return completer.future;
}

Future<void> _emitWindowsWebViewEvent(Map<String, Object?> event) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final completer = Completer<ByteData?>();
  await messenger.handlePlatformMessage(
    '$windowsWebViewChannelPrefix/$_activeMockTextureId/events',
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    completer.complete,
  );
  await completer.future;
}

Future<void> _flushAsyncEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

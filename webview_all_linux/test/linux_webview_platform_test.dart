import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_linux/src/linux_webview_constants.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockLinuxWebViewCreation);
  tearDown(_clearLinuxWebViewCreationMock);

  test('registerWith sets the Linux WebView platform implementation', () {
    final WebViewPlatform? previousInstance = WebViewPlatform.instance;
    addTearDown(() {
      if (previousInstance != null) {
        WebViewPlatform.instance = previousInstance;
      }
    });

    LinuxWebViewPlatform.registerWith();

    expect(WebViewPlatform.instance, isA<LinuxWebViewPlatform>());
  });

  test('creates Linux platform implementation objects', () {
    final LinuxWebViewPlatform platform = LinuxWebViewPlatform();
    final LinuxWebViewController controller = platform
        .createPlatformWebViewController(
          const PlatformWebViewControllerCreationParams(),
        );

    expect(controller, isA<LinuxWebViewController>());
    expect(
      platform.createPlatformNavigationDelegate(
        const PlatformNavigationDelegateCreationParams(),
      ),
      isA<LinuxNavigationDelegate>(),
    );
    expect(
      platform.createPlatformWebViewWidget(
        PlatformWebViewWidgetCreationParams(controller: controller),
      ),
      isA<LinuxWebViewWidget>(),
    );
    expect(
      platform.createPlatformCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
      isA<LinuxWebViewCookieManager>(),
    );
  });

  test('dispose releases the native WebView exactly once', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);
    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await controller.dispose();
    await controller.dispose();

    expect(
      calls.where((MethodCall call) => call.method == 'dispose'),
      hasLength(1),
    );
    await expectLater(controller.reload(), throwsStateError);
  });

  test('rejects invalid cookies before root channel setCookie', () async {
    final List<MethodCall> rootCalls = <MethodCall>[];
    _mockLinuxWebViewCreation(onRootCall: rootCalls.add);

    final LinuxWebViewCookieManager cookieManager = LinuxWebViewCookieManager(
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

    expect(
      rootCalls.where((MethodCall call) => call.method == 'setCookie'),
      isEmpty,
    );
  });

  test('sets scrollbar visibility through separate platform calls', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    expect(controller.supportsSetScrollBarsEnabled(), isTrue);

    await controller.setVerticalScrollBarEnabled(false);
    await controller.setHorizontalScrollBarEnabled(false);
    await controller.setVerticalScrollBarEnabled(true);

    expect(calls, hasLength(3));
    expect(calls[0].method, 'setVerticalScrollBarEnabled');
    expect(calls[0].arguments, <String, Object?>{'enabled': false});
    expect(calls[1].method, 'setHorizontalScrollBarEnabled');
    expect(calls[1].arguments, <String, Object?>{'enabled': false});
    expect(calls[2].method, 'setVerticalScrollBarEnabled');
    expect(calls[2].arguments, <String, Object?>{'enabled': true});
  });

  test('sets overscroll mode through native platform calls', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.setOverScrollMode(WebViewOverScrollMode.never);
    await controller.setOverScrollMode(WebViewOverScrollMode.ifContentScrolls);
    await controller.setOverScrollMode(WebViewOverScrollMode.always);

    expect(calls, hasLength(3));
    expect(calls[0].method, 'setOverScrollMode');
    expect(calls[0].arguments, <String, Object?>{'mode': 'never'});
    expect(calls[1].method, 'setOverScrollMode');
    expect(calls[1].arguments, <String, Object?>{'mode': 'ifContentScrolls'});
    expect(calls[2].method, 'setOverScrollMode');
    expect(calls[2].arguments, <String, Object?>{'mode': 'always'});
  });

  test('applies Linux-specific WebKit settings from creation params', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const LinuxWebViewControllerCreationParams(
        developerExtrasEnabled: true,
        javascriptCanOpenWindowsAutomatically: true,
        mediaPlaybackRequiresUserGesture: false,
        mediaPlaybackAllowsInline: true,
        pageCacheEnabled: true,
        allowFileAccessFromFileUrls: true,
        allowUniversalAccessFromFileUrls: false,
        zoomTextOnly: true,
        defaultFontSize: 18,
        defaultMonospaceFontSize: 14,
        minimumFontSize: 9,
        zoomFactor: 1.25,
      ),
    );

    await controller.currentUrl();

    expect(calls.first.method, 'applySettings');
    expect(calls.first.arguments, <String, Object?>{
      'developerExtrasEnabled': true,
      'javascriptCanOpenWindowsAutomatically': true,
      'mediaPlaybackRequiresUserGesture': false,
      'mediaPlaybackAllowsInline': true,
      'pageCacheEnabled': true,
      'allowFileAccessFromFileUrls': true,
      'allowUniversalAccessFromFileUrls': false,
      'zoomTextOnly': true,
      'defaultFontSize': 18,
      'defaultMonospaceFontSize': 14,
      'minimumFontSize': 9,
      'zoomFactor': 1.25,
    });
  });

  test('sends Linux-specific WebKit settings through platform calls', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.setDeveloperExtrasEnabled(true);
    await controller.openDevTools();
    await controller.setJavaScriptCanOpenWindowsAutomatically(true);
    await controller.setMediaPlaybackRequiresUserGesture(false);
    await controller.setMediaPlaybackAllowsInline(true);
    await controller.setPageCacheEnabled(true);
    await controller.setAllowFileAccessFromFileUrls(true);
    await controller.setAllowUniversalAccessFromFileUrls(false);
    await controller.setZoomTextOnly(true);
    await controller.setDefaultFontSize(18);
    await controller.setDefaultMonospaceFontSize(14);
    await controller.setMinimumFontSize(9);
    await controller.setZoomFactor(1.25);

    expect(calls.map((MethodCall call) => call.method), <String>[
      'setDeveloperExtrasEnabled',
      'openDevTools',
      'setJavaScriptCanOpenWindowsAutomatically',
      'setMediaPlaybackRequiresUserGesture',
      'setMediaPlaybackAllowsInline',
      'setPageCacheEnabled',
      'setAllowFileAccessFromFileUrls',
      'setAllowUniversalAccessFromFileUrls',
      'setZoomTextOnly',
      'setDefaultFontSize',
      'setDefaultMonospaceFontSize',
      'setMinimumFontSize',
      'setZoomFactor',
    ]);
    expect(calls[0].arguments, <String, Object?>{'enabled': true});
    expect(calls[1].arguments, isNull);
    expect(calls[2].arguments, <String, Object?>{'enabled': true});
    expect(calls[3].arguments, <String, Object?>{'require': false});
    expect(calls[4].arguments, <String, Object?>{'allow': true});
    expect(calls[5].arguments, <String, Object?>{'enabled': true});
    expect(calls[6].arguments, <String, Object?>{'allow': true});
    expect(calls[7].arguments, <String, Object?>{'allow': false});
    expect(calls[8].arguments, <String, Object?>{'enabled': true});
    expect(calls[9].arguments, <String, Object?>{'fontSize': 18});
    expect(calls[10].arguments, <String, Object?>{'fontSize': 14});
    expect(calls[11].arguments, <String, Object?>{'fontSize': 9});
    expect(calls[12].arguments, <String, Object?>{'zoomFactor': 1.25});
  });

  test('loads requests with method headers and body', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final Uint8List body = Uint8List.fromList(<int>[1, 2, 3]);

    await controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.test/form'),
        method: LoadRequestMethod.post,
        headers: const <String, String>{'X-Test': 'true'},
        body: body,
      ),
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'loadRequest');
    expect(calls.single.arguments, <String, Object?>{
      'url': 'https://example.test/form',
      'method': 'post',
      'headers': <String, String>{'X-Test': 'true'},
      'body': body,
    });
  });

  test('loads files with params through the platform loadFile path', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);
    final Directory tempDir = Directory.systemTemp.createTempSync(
      'webview_all_linux_test_',
    );
    addTearDown(() {
      tempDir.deleteSync(recursive: true);
    });
    final File file = File('${tempDir.path}/index.html')
      ..writeAsStringSync('<html></html>');

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.loadFileWithParams(
      LoadFileParams(absoluteFilePath: file.path),
    );

    expect(calls, hasLength(1));
    expect(calls.single.method, 'loadFile');
    expect(calls.single.arguments, <String, Object?>{
      'path': file.absolute.path,
    });
  });

  test('clears local storage through the native WebKit data manager', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.clearLocalStorage();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'clearLocalStorage');
    expect(calls.single.arguments, isNull);
  });

  test('dispatches HTTP response errors from Linux events', () async {
    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final LinuxNavigationDelegate delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final List<HttpResponseError> errors = <HttpResponseError>[];

    await controller.currentUrl();
    await delegate.setOnHttpError(errors.add);
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'httpError',
      'url': 'https://example.test/missing',
      'method': 'POST',
      'requestHeaders': <String, Object?>{'Accept': 'text/plain'},
      'isForMainFrame': true,
      'statusCode': 404,
      'headers': <String, Object?>{'Content-Type': 'text/plain'},
      'mimeType': 'text/plain',
    });

    expect(errors, hasLength(1));
    expect(
      errors.single.request?.uri,
      Uri.parse('https://example.test/missing'),
    );
    expect(errors.single.request, isA<LinuxWebResourceRequest>());
    final LinuxWebResourceRequest request =
        errors.single.request! as LinuxWebResourceRequest;
    expect(request.method, 'POST');
    expect(request.headers, const <String, String>{'Accept': 'text/plain'});
    expect(request.isForMainFrame, isTrue);
    expect(
      errors.single.response?.uri,
      Uri.parse('https://example.test/missing'),
    );
    expect(errors.single.response, isA<LinuxWebResourceResponse>());
    final LinuxWebResourceResponse response =
        errors.single.response! as LinuxWebResourceResponse;
    expect(errors.single.response?.statusCode, 404);
    expect(response.headers, <String, String>{'Content-Type': 'text/plain'});
    expect(response.mimeType, 'text/plain');
  });

  test('dispatches web resource errors from Linux events', () async {
    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final LinuxNavigationDelegate delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final List<WebResourceError> errors = <WebResourceError>[];

    await controller.currentUrl();
    await delegate.setOnWebResourceError(errors.add);
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'webResourceError',
      'errorCode': 7,
      'description': 'Timed out',
      'errorType': 'timeout',
      'isForMainFrame': false,
      'url': 'https://example.test/slow',
    });

    expect(errors, hasLength(1));
    expect(errors.single, isA<LinuxWebResourceError>());
    final LinuxWebResourceError error = errors.single as LinuxWebResourceError;
    expect(error.errorCode, 7);
    expect(error.description, 'Timed out');
    expect(error.errorType, WebResourceErrorType.timeout);
    expect(error.isForMainFrame, isFalse);
    expect(error.url, 'https://example.test/slow');
  });

  test(
    'dispatches console and scroll position events from Linux events',
    () async {
      final List<MethodCall> calls = <MethodCall>[];
      _mockLinuxWebViewCreation(onInstanceCall: calls.add);

      final LinuxWebViewController controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      final List<JavaScriptConsoleMessage> consoleMessages =
          <JavaScriptConsoleMessage>[];
      final List<ScrollPositionChange> scrollChanges = <ScrollPositionChange>[];

      await controller.currentUrl();
      await controller.setOnConsoleMessage(consoleMessages.add);
      await controller.setOnScrollPositionChange(scrollChanges.add);
      await _emitLinuxWebViewEvent(<String, Object?>{
        'type': 'consoleMessage',
        'level': 'warning',
        'message': 'careful',
      });
      await _emitLinuxWebViewEvent(<String, Object?>{
        'type': 'consoleMessage',
        'level': 'debug',
        'message': 'details',
      });
      await _emitLinuxWebViewEvent(<String, Object?>{
        'type': 'scrollPositionChange',
        'x': 12.5,
        'y': 34,
      });
      await _flushAsyncEvents();

      expect(
        calls.where((MethodCall call) => call.method == 'setOnConsoleMessage'),
        hasLength(1),
      );
      expect(
        calls
            .singleWhere(
              (MethodCall call) => call.method == 'setOnConsoleMessage',
            )
            .arguments,
        <String, Object?>{'enabled': true},
      );
      expect(
        calls.where(
          (MethodCall call) => call.method == 'setOnScrollPositionChange',
        ),
        hasLength(1),
      );
      expect(
        calls
            .singleWhere(
              (MethodCall call) => call.method == 'setOnScrollPositionChange',
            )
            .arguments,
        <String, Object?>{'enabled': true},
      );
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

  test('Linux console bridge script safely stringifies non-json values', () {
    final String source = File(
      'linux/src/webview/webview_javascript.cc',
    ).readAsStringSync();

    expect(source, contains('function stringifyArg'));
    expect(source, contains('return json === undefined ? String(arg) : json'));
    expect(source, contains('Array.from(arguments).map(stringifyArg)'));
  });

  test('completes JavaScript dialog requests from Linux events', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final List<JavaScriptAlertDialogRequest> alertRequests =
        <JavaScriptAlertDialogRequest>[];
    final List<JavaScriptConfirmDialogRequest> confirmRequests =
        <JavaScriptConfirmDialogRequest>[];
    final List<JavaScriptTextInputDialogRequest> promptRequests =
        <JavaScriptTextInputDialogRequest>[];

    await controller.currentUrl();
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

    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 21,
      'dialogType': 'alert',
      'message': 'hello alert',
      'url': 'https://example.test/alert',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 22,
      'dialogType': 'confirm',
      'message': 'continue?',
      'url': 'https://example.test/confirm',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 23,
      'dialogType': 'prompt',
      'message': 'name',
      'url': 'https://example.test/prompt',
      'defaultText': 'default value',
    });
    await _flushAsyncEvents();

    expect(alertRequests, hasLength(1));
    expect(alertRequests.single.message, 'hello alert');
    expect(alertRequests.single.url, 'https://example.test/alert');
    expect(confirmRequests, hasLength(1));
    expect(confirmRequests.single.message, 'continue?');
    expect(confirmRequests.single.url, 'https://example.test/confirm');
    expect(promptRequests, hasLength(1));
    expect(promptRequests.single.message, 'name');
    expect(promptRequests.single.url, 'https://example.test/prompt');
    expect(promptRequests.single.defaultText, 'default value');

    final List<MethodCall> dialogCallbackCalls = calls
        .where(
          (MethodCall call) =>
              call.method == 'setJavaScriptDialogCallbacksEnabled',
        )
        .toList();
    expect(dialogCallbackCalls, hasLength(3));
    expect(dialogCallbackCalls[0].arguments, <String, Object?>{
      'alert': true,
      'confirm': false,
      'prompt': false,
    });
    expect(dialogCallbackCalls[1].arguments, <String, Object?>{
      'alert': true,
      'confirm': true,
      'prompt': false,
    });
    expect(dialogCallbackCalls[2].arguments, <String, Object?>{
      'alert': true,
      'confirm': true,
      'prompt': true,
    });

    final List<MethodCall> dialogCalls = calls
        .where((MethodCall call) => call.method == 'completeJavaScriptDialog')
        .toList();
    expect(dialogCalls, hasLength(3));
    expect(dialogCalls[0].arguments, <String, Object?>{
      'requestId': 21,
      'action': 'confirm',
      'text': null,
    });
    expect(dialogCalls[1].arguments, <String, Object?>{
      'requestId': 22,
      'action': 'cancel',
      'text': null,
    });
    expect(dialogCalls[2].arguments, <String, Object?>{
      'requestId': 23,
      'action': 'confirm',
      'text': 'typed value',
    });
  });

  test('uses safe JavaScript dialog defaults without Linux handlers', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 24,
      'dialogType': 'alert',
      'message': 'hello alert',
      'url': 'https://example.test/alert',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 25,
      'dialogType': 'confirm',
      'message': 'continue?',
      'url': 'https://example.test/confirm',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 26,
      'dialogType': 'prompt',
      'message': 'name',
      'url': 'https://example.test/prompt',
      'defaultText': 'default value',
    });
    await _flushAsyncEvents();

    final List<MethodCall> dialogCalls = calls
        .where((MethodCall call) => call.method == 'completeJavaScriptDialog')
        .toList();
    expect(dialogCalls, hasLength(3));
    expect(dialogCalls[0].arguments, <String, Object?>{
      'requestId': 24,
      'action': 'confirm',
      'text': null,
    });
    expect(dialogCalls[1].arguments, <String, Object?>{
      'requestId': 25,
      'action': 'confirm',
      'text': null,
    });
    expect(dialogCalls[2].arguments, <String, Object?>{
      'requestId': 26,
      'action': 'confirm',
      'text': 'default value',
    });
  });

  test('cancels JavaScript dialogs when Linux handlers throw', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await controller.setOnJavaScriptConfirmDialog((
      JavaScriptConfirmDialogRequest request,
    ) async {
      throw StateError('dialog failure');
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 27,
      'dialogType': 'confirm',
      'message': 'continue?',
      'url': 'https://example.test/confirm',
    });
    await _flushAsyncEvents();

    final List<MethodCall> dialogCalls = calls
        .where((MethodCall call) => call.method == 'completeJavaScriptDialog')
        .toList();
    expect(dialogCalls, hasLength(1));
    expect(dialogCalls.single.arguments, <String, Object?>{
      'requestId': 27,
      'action': 'cancel',
      'text': null,
    });
  });

  test('completes HTTP auth requests once from Linux events', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final LinuxNavigationDelegate delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final List<HttpAuthRequest> requests = <HttpAuthRequest>[];

    await controller.currentUrl();
    await delegate.setOnHttpAuthRequest((HttpAuthRequest request) {
      requests.add(request);
      request.onProceed(
        const WebViewCredential(user: 'test-user', password: 'test-password'),
      );
      request.onCancel();
      request.onProceed(
        const WebViewCredential(user: 'other-user', password: 'other-password'),
      );
    });
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'httpAuthRequest',
      'requestId': 12,
      'host': 'secure.example.test',
      'realm': 'Restricted Area',
    });
    await _flushAsyncEvents();

    expect(requests, hasLength(1));
    expect(requests.single.host, 'secure.example.test');
    expect(requests.single.realm, 'Restricted Area');
    final List<MethodCall> authCalls = calls
        .where((MethodCall call) => call.method == 'completeHttpAuthRequest')
        .toList();
    expect(authCalls, hasLength(1));
    expect(authCalls.single.arguments, <String, Object?>{
      'requestId': 12,
      'action': 'proceed',
      'user': 'test-user',
      'password': 'test-password',
    });
  });

  test('cancels HTTP auth requests without a Linux handler', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'httpAuthRequest',
      'requestId': 13,
      'host': 'secure.example.test',
      'realm': 'Restricted Area',
    });
    await _flushAsyncEvents();

    final List<MethodCall> authCalls = calls
        .where((MethodCall call) => call.method == 'completeHttpAuthRequest')
        .toList();
    expect(authCalls, hasLength(1));
    expect(authCalls.single.arguments, <String, Object?>{
      'requestId': 13,
      'action': 'cancel',
    });
  });

  test('completes SSL auth errors once from Linux events', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final LinuxNavigationDelegate delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );
    final List<PlatformSslAuthError> errors = <PlatformSslAuthError>[];

    await controller.currentUrl();
    await delegate.setOnSSlAuthError((PlatformSslAuthError error) {
      errors.add(error);
      unawaited(error.proceed());
      unawaited(error.cancel());
      unawaited(error.proceed());
    });
    await controller.setPlatformNavigationDelegate(delegate);
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'sslAuthError',
      'requestId': 7,
      'url': 'https://expired.example.test/',
      'description':
          'TLS certificate error for expired.example.test. '
          'Certificate has expired.',
    });
    await _flushAsyncEvents();

    expect(errors, hasLength(1));
    expect(errors.single.certificate, isNull);
    expect(errors.single.description, contains('expired.example.test'));
    expect(errors.single.description, contains('Certificate has expired'));
    final List<MethodCall> sslCalls = calls
        .where((MethodCall call) => call.method == 'completeSslAuthError')
        .toList();
    expect(sslCalls, hasLength(1));
    expect(sslCalls.single.arguments, <String, Object?>{
      'requestId': 7,
      'proceed': true,
    });
  });

  test('cancels SSL auth errors without a Linux handler', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'sslAuthError',
      'requestId': 8,
      'url': 'https://expired.example.test/',
      'description': 'TLS certificate error',
    });
    await _flushAsyncEvents();

    final List<MethodCall> sslCalls = calls
        .where((MethodCall call) => call.method == 'completeSslAuthError')
        .toList();
    expect(sslCalls, hasLength(1));
    expect(sslCalls.single.arguments, <String, Object?>{
      'requestId': 8,
      'proceed': false,
    });
  });

  test('dispatches permission requests from Linux events', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final List<PlatformWebViewPermissionRequest> requests =
        <PlatformWebViewPermissionRequest>[];
    int requestCount = 0;

    await controller.currentUrl();
    await controller.setOnPlatformPermissionRequest((
      PlatformWebViewPermissionRequest request,
    ) {
      requests.add(request);
      requestCount += 1;
      if (requestCount == 1) {
        unawaited(request.grant());
        unawaited(request.deny());
        unawaited(request.grant());
      } else {
        unawaited(request.deny());
      }
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'permissionRequest',
      'requestId': 9,
      'types': <String>['camera', 'microphone', 'unknown'],
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'permissionRequest',
      'requestId': 10,
      'types': <String>['microphone'],
    });
    await _flushAsyncEvents();

    expect(requests, hasLength(2));
    expect(requests[0].types, <WebViewPermissionResourceType>{
      WebViewPermissionResourceType.camera,
      WebViewPermissionResourceType.microphone,
    });
    expect(requests[1].types, <WebViewPermissionResourceType>{
      WebViewPermissionResourceType.microphone,
    });
    final List<MethodCall> permissionCalls = calls
        .where((MethodCall call) => call.method == 'completePermissionRequest')
        .toList();
    expect(permissionCalls, hasLength(2));
    expect(permissionCalls[0].arguments, <String, Object?>{
      'requestId': 9,
      'grant': true,
    });
    expect(permissionCalls[1].arguments, <String, Object?>{
      'requestId': 10,
      'grant': false,
    });
  });

  test('denies permission requests without a Linux handler', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);

    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    await controller.currentUrl();
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'permissionRequest',
      'requestId': 11,
      'types': <String>['camera'],
    });
    await _flushAsyncEvents();

    final List<MethodCall> permissionCalls = calls
        .where((MethodCall call) => call.method == 'completePermissionRequest')
        .toList();
    expect(permissionCalls, hasLength(1));
    expect(permissionCalls.single.arguments, <String, Object?>{
      'requestId': 11,
      'grant': false,
    });
  });

  test(
    'denies Linux permission requests without recognized resources',
    () async {
      final List<MethodCall> calls = <MethodCall>[];
      _mockLinuxWebViewCreation(onInstanceCall: calls.add);

      final LinuxWebViewController controller = LinuxWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      var callbackCalled = false;

      await controller.currentUrl();
      await controller.setOnPlatformPermissionRequest((_) {
        callbackCalled = true;
      });
      await _emitLinuxWebViewEvent(<String, Object?>{
        'type': 'permissionRequest',
        'requestId': 12,
        'types': <String>['unknown'],
      });
      await _flushAsyncEvents();

      final List<MethodCall> permissionCalls = calls
          .where(
            (MethodCall call) => call.method == 'completePermissionRequest',
          )
          .toList();
      expect(callbackCalled, isFalse);
      expect(permissionCalls, hasLength(1));
      expect(permissionCalls.single.arguments, <String, Object?>{
        'requestId': 12,
        'grant': false,
      });
    },
  );

  test('uses safe decisions when application callbacks throw', () async {
    final List<MethodCall> calls = <MethodCall>[];
    _mockLinuxWebViewCreation(onInstanceCall: calls.add);
    final LinuxWebViewController controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final LinuxNavigationDelegate delegate = LinuxNavigationDelegate(
      const PlatformNavigationDelegateCreationParams(),
    );

    await controller.currentUrl();
    await delegate.setOnNavigationRequest((NavigationRequest request) {
      throw StateError('navigation callback failed');
    });
    await delegate.setOnHttpAuthRequest((HttpAuthRequest request) {
      throw StateError('authentication callback failed');
    });
    await delegate.setOnSSlAuthError((PlatformSslAuthError error) {
      throw StateError('TLS callback failed');
    });
    await controller.setPlatformNavigationDelegate(delegate);
    await controller.setOnPlatformPermissionRequest((_) {
      throw StateError('permission callback failed');
    });
    await controller.setOnConsoleMessage((_) {
      throw StateError('console callback failed');
    });
    await controller.setOnJavaScriptConfirmDialog((_) {
      throw StateError('dialog callback failed');
    });

    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'navigationRequest',
      'requestId': 31,
      'url': 'https://example.test/navigation',
      'isMainFrame': true,
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'httpAuthRequest',
      'requestId': 32,
      'host': 'secure.example.test',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'sslAuthError',
      'requestId': 33,
      'description': 'TLS certificate error',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'permissionRequest',
      'requestId': 34,
      'types': <String>['camera'],
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'consoleMessage',
      'level': 'error',
      'message': 'test',
    });
    await _emitLinuxWebViewEvent(<String, Object?>{
      'type': 'javaScriptDialog',
      'requestId': 35,
      'dialogType': 'confirm',
      'message': 'Continue?',
      'url': 'https://example.test/dialog',
    });
    await _flushAsyncEvents();

    expect(
      calls
          .singleWhere(
            (MethodCall call) => call.method == 'completeNavigationRequest',
          )
          .arguments,
      <String, Object?>{'requestId': 31, 'allow': false},
    );
    expect(
      calls
          .singleWhere(
            (MethodCall call) => call.method == 'completeHttpAuthRequest',
          )
          .arguments,
      <String, Object?>{'requestId': 32, 'action': 'cancel'},
    );
    expect(
      calls
          .singleWhere(
            (MethodCall call) => call.method == 'completeSslAuthError',
          )
          .arguments,
      <String, Object?>{'requestId': 33, 'proceed': false},
    );
    expect(
      calls
          .singleWhere(
            (MethodCall call) => call.method == 'completePermissionRequest',
          )
          .arguments,
      <String, Object?>{'requestId': 34, 'grant': false},
    );
    expect(
      calls
          .singleWhere(
            (MethodCall call) => call.method == 'completeJavaScriptDialog',
          )
          .arguments,
      <String, Object?>{'requestId': 35, 'action': 'cancel', 'text': null},
    );
  });
}

void _mockLinuxWebViewCreation({
  void Function(MethodCall call)? onRootCall,
  void Function(MethodCall call)? onInstanceCall,
}) {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(linuxWebViewChannelPrefix),
    (MethodCall methodCall) async {
      onRootCall?.call(methodCall);
      if (methodCall.method == 'createWebView') {
        return 1;
      }
      return null;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('$linuxWebViewChannelPrefix/1'),
    (MethodCall methodCall) async {
      onInstanceCall?.call(methodCall);
      return null;
    },
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('$linuxWebViewChannelPrefix/1/events'),
    (MethodCall methodCall) async => null,
  );
}

void _clearLinuxWebViewCreationMock() {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel(linuxWebViewChannelPrefix),
    null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('$linuxWebViewChannelPrefix/1'),
    null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('$linuxWebViewChannelPrefix/1/events'),
    null,
  );
}

Future<void> _emitLinuxWebViewEvent(Map<String, Object?> event) async {
  final TestDefaultBinaryMessenger messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final Completer<ByteData?> completer = Completer<ByteData?>();
  await messenger.handlePlatformMessage(
    '$linuxWebViewChannelPrefix/1/events',
    const StandardMethodCodec().encodeSuccessEnvelope(event),
    completer.complete,
  );
  await completer.future;
}

Future<void> _flushAsyncEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

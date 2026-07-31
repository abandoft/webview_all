import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart' as ohos_webview;
import 'package:webview_all_ohos/src/ohos_webview_proxy.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

// ignore: must_be_immutable
class TestCookieManager extends CookieManager {
  TestCookieManager()
    : super.detached(
        instanceManager: InstanceManager(onWeakReferenceRemoved: (_) {}),
      );

  String cookies = '';
  String? lastGetCookiesUrl;
  String? lastSetCookieUrl;
  String? lastSetCookieValue;

  @override
  Future<String> getCookies(String url) async {
    lastGetCookiesUrl = url;
    return cookies;
  }

  @override
  Future<void> setCookie(String url, String value) async {
    lastSetCookieUrl = url;
    lastSetCookieValue = value;
  }
}

// ignore: must_be_immutable
class TestWebSettings extends ohos_webview.WebSettings {
  TestWebSettings(InstanceManager instanceManager)
    // ignore: invalid_use_of_protected_member
    : super.detached(instanceManager: instanceManager);

  bool? allowFileAccess;
  bool? allowFullScreenRotate;
  bool? builtInZoomControls;
  bool? displayZoomControls;
  bool? domStorageEnabled;
  bool? javaScriptCanOpenWindowsAutomatically;
  bool? javaScriptEnabled;
  bool? loadWithOverviewMode;
  bool? mediaPlaybackRequiresUserGesture;
  bool? supportMultipleWindows;
  bool? supportZoom;
  bool? useWideViewPort;
  int? textZoom;
  String? userAgentString;

  @override
  Future<void> setAllowFileAccess(bool enabled) async {
    allowFileAccess = enabled;
  }

  @override
  Future<void> setAllowFullScreenRotate(bool enabled) async {
    allowFullScreenRotate = enabled;
  }

  @override
  Future<void> setBuiltInZoomControls(bool enabled) async {
    builtInZoomControls = enabled;
  }

  @override
  Future<void> setDisplayZoomControls(bool enabled) async {
    displayZoomControls = enabled;
  }

  @override
  Future<void> setDomStorageEnabled(bool flag) async {
    domStorageEnabled = flag;
  }

  @override
  Future<void> setJavaScriptCanOpenWindowsAutomatically(bool flag) async {
    javaScriptCanOpenWindowsAutomatically = flag;
  }

  @override
  Future<void> setJavaScriptEnabled(bool flag) async {
    javaScriptEnabled = flag;
  }

  @override
  Future<void> setLoadWithOverviewMode(bool overview) async {
    loadWithOverviewMode = overview;
  }

  @override
  Future<void> setMediaPlaybackRequiresUserGesture(bool require) async {
    mediaPlaybackRequiresUserGesture = require;
  }

  @override
  Future<void> setSupportMultipleWindows(bool support) async {
    supportMultipleWindows = support;
  }

  @override
  Future<void> setSupportZoom(bool support) async {
    supportZoom = support;
  }

  @override
  Future<void> setTextZoom(int textZoom) async {
    this.textZoom = textZoom;
  }

  @override
  Future<void> setUseWideViewPort(bool use) async {
    useWideViewPort = use;
  }

  @override
  Future<void> setUserAgentString(String? userAgentString) async {
    this.userAgentString = userAgentString;
  }
}

// ignore: must_be_immutable
class TestWebView extends ohos_webview.WebView {
  TestWebView(this.instanceManager)
    // ignore: invalid_use_of_protected_member
    : super.detached(instanceManager: instanceManager);

  final InstanceManager instanceManager;

  @override
  late final TestWebSettings settings = TestWebSettings(instanceManager);

  String? loadedUrl;
  Map<String, String>? loadedHeaders;
  String? postedUrl;
  Uint8List? postedData;
  String? evaluatedJavaScript;
  String? javaScriptResult;
  ohos_webview.WebChromeClient? webChromeClient;

  @override
  Future<void> loadUrl(String url, Map<String, String> headers) async {
    loadedUrl = url;
    loadedHeaders = headers;
  }

  @override
  Future<void> postUrl(String url, Uint8List data) async {
    postedUrl = url;
    postedData = data;
  }

  @override
  Future<String?> evaluateJavascript(String javascriptString) async {
    evaluatedJavaScript = javascriptString;
    return javaScriptResult;
  }

  @override
  Future<void> setWebChromeClient(ohos_webview.WebChromeClient? client) async {
    webChromeClient = client;
  }
}

// ignore: must_be_immutable
class TestWebViewClient extends ohos_webview.WebViewClient {
  TestWebViewClient(
    InstanceManager instanceManager, {
    void Function(ohos_webview.WebView webView, String url)? onPageStarted,
    void Function(ohos_webview.WebView webView, String url)? onPageFinished,
    void Function(
      ohos_webview.WebView webView,
      ohos_webview.WebResourceRequest request,
      ohos_webview.WebResourceError error,
    )?
    onReceivedRequestError,
    void Function(
      ohos_webview.WebView webView,
      ohos_webview.WebResourceRequest request,
      ohos_webview.WebResourceResponse response,
    )?
    onReceivedHttpError,
    void Function(
      ohos_webview.WebView webView,
      ohos_webview.WebResourceRequest request,
    )?
    requestLoading,
    void Function(ohos_webview.WebView webView, String url)? urlLoading,
    void Function(ohos_webview.WebView webView, String url, bool isReload)?
    doUpdateVisitedHistory,
    void Function(
      ohos_webview.WebView webView,
      ohos_webview.HttpAuthHandler handler,
      String host,
      String realm,
    )?
    onReceivedHttpAuthRequest,
    void Function(
      ohos_webview.WebView webView,
      ohos_webview.SslAuthHandler handler,
      String url,
      int errorCode,
      String description,
    )?
    onReceivedSslAuthError,
  }) : super.detached(
         instanceManager: instanceManager,
         onPageStarted: onPageStarted,
         onPageFinished: onPageFinished,
         onReceivedRequestError: onReceivedRequestError,
         onReceivedHttpError: onReceivedHttpError,
         requestLoading: requestLoading,
         urlLoading: urlLoading,
         doUpdateVisitedHistory: doUpdateVisitedHistory,
         onReceivedHttpAuthRequest: onReceivedHttpAuthRequest,
         onReceivedSslAuthError: onReceivedSslAuthError,
       );

  bool? synchronousReturnValueForShouldOverrideUrlLoading;

  @override
  Future<void> setSynchronousReturnValueForShouldOverrideUrlLoading(
    bool value,
  ) async {
    synchronousReturnValueForShouldOverrideUrlLoading = value;
  }
}

// ignore: must_be_immutable
class TestWebChromeClient extends ohos_webview.WebChromeClient {
  TestWebChromeClient(
    InstanceManager instanceManager, {
    super.onProgressChanged,
    super.onShowFileChooser,
    super.onPermissionRequest,
    super.onGeolocationPermissionsShowPrompt,
    super.onGeolocationPermissionsHidePrompt,
    super.onShowCustomView,
    super.onHideCustomView,
    super.onConsoleMessage,
    super.onJsAlert,
    super.onJsConfirm,
    super.onJsPrompt,
  }) : super.detached(instanceManager: instanceManager);

  bool? synchronousReturnValueForOnJsAlert;
  bool? synchronousReturnValueForOnJsConfirm;
  bool? synchronousReturnValueForOnJsPrompt;
  bool? synchronousReturnValueForOnConsoleMessage;

  @override
  Future<void> setSynchronousReturnValueForOnConsoleMessage(bool value) async {
    synchronousReturnValueForOnConsoleMessage = value;
  }

  @override
  Future<void> setSynchronousReturnValueForOnJsAlert(bool value) async {
    synchronousReturnValueForOnJsAlert = value;
  }

  @override
  Future<void> setSynchronousReturnValueForOnJsConfirm(bool value) async {
    synchronousReturnValueForOnJsConfirm = value;
  }

  @override
  Future<void> setSynchronousReturnValueForOnJsPrompt(bool value) async {
    synchronousReturnValueForOnJsPrompt = value;
  }
}

// ignore: must_be_immutable
class TestPermissionRequest extends ohos_webview.PermissionRequest {
  TestPermissionRequest(
    InstanceManager instanceManager, {
    required List<String> resources,
  }) : super.detached(
         resources: resources,
         binaryMessenger: null,
         instanceManager: instanceManager,
       );

  List<String>? grantedResources;
  bool denied = false;
  int grantCount = 0;
  int denyCount = 0;

  @override
  Future<void> grant(List<String> resources) async {
    grantCount += 1;
    grantedResources = resources;
  }

  @override
  Future<void> deny() async {
    denyCount += 1;
    denied = true;
  }
}

// ignore: must_be_immutable
class TestHttpAuthHandler extends ohos_webview.HttpAuthHandler {
  TestHttpAuthHandler(InstanceManager instanceManager)
    : super(instanceManager: instanceManager);

  bool canceled = false;
  List<WebViewCredential> credentials = <WebViewCredential>[];

  @override
  Future<void> cancel() async {
    canceled = true;
  }

  @override
  Future<void> proceed(String username, String password) async {
    credentials.add(WebViewCredential(user: username, password: password));
  }
}

// ignore: must_be_immutable
class TestSslAuthHandler extends ohos_webview.SslAuthHandler {
  TestSslAuthHandler(InstanceManager instanceManager)
    : super(instanceManager: instanceManager);

  bool canceled = false;
  bool proceeded = false;
  int cancelCount = 0;
  int proceedCount = 0;

  @override
  Future<void> cancel() async {
    cancelCount += 1;
    canceled = true;
  }

  @override
  Future<void> proceed() async {
    proceedCount += 1;
    proceeded = true;
  }
}

void main() {
  test('registerWith sets the OHOS WebView platform implementation', () {
    final WebViewPlatform? previousInstance = WebViewPlatform.instance;
    addTearDown(() {
      if (previousInstance != null) {
        WebViewPlatform.instance = previousInstance;
      }
    });

    OhosWebViewPlatform.registerWith();

    expect(WebViewPlatform.instance, isA<OhosWebViewPlatform>());
  });

  test('applies OHOS-specific settings from creation params', () {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);

    final OhosWebViewController controller = _createTestWebViewController(
      instanceManager: instanceManager,
      testWebView: testWebView,
      isAllowFullScreenRotate: true,
      domStorageEnabled: false,
      javaScriptCanOpenWindowsAutomatically: false,
      supportMultipleWindows: false,
      loadWithOverviewMode: false,
      useWideViewPort: false,
      displayZoomControls: true,
      builtInZoomControls: false,
      allowFileAccess: true,
      mediaPlaybackRequiresUserGesture: true,
      supportZoom: false,
      textZoom: 125,
    );

    expect(controller, isA<OhosWebViewController>());
    expect(testWebView.settings.allowFullScreenRotate, isTrue);
    expect(testWebView.settings.domStorageEnabled, isFalse);
    expect(testWebView.settings.javaScriptCanOpenWindowsAutomatically, isFalse);
    expect(testWebView.settings.supportMultipleWindows, isFalse);
    expect(testWebView.settings.loadWithOverviewMode, isFalse);
    expect(testWebView.settings.useWideViewPort, isFalse);
    expect(testWebView.settings.displayZoomControls, isTrue);
    expect(testWebView.settings.builtInZoomControls, isFalse);
    expect(testWebView.settings.allowFileAccess, isTrue);
    expect(testWebView.settings.mediaPlaybackRequiresUserGesture, isTrue);
    expect(testWebView.settings.supportZoom, isFalse);
    expect(testWebView.settings.textZoom, 125);
  });

  test('sets OHOS-specific WebSettings at runtime', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    final OhosWebViewController controller = _createTestWebViewController(
      instanceManager: instanceManager,
      testWebView: testWebView,
    );

    await controller.setAllowFullScreenRotate(true);
    await controller.setDomStorageEnabled(false);
    await controller.setJavaScriptCanOpenWindowsAutomatically(false);
    await controller.setSupportMultipleWindows(false);
    await controller.setLoadWithOverviewMode(false);
    await controller.setUseWideViewPort(false);
    await controller.setDisplayZoomControls(true);
    await controller.setBuiltInZoomControls(false);
    await controller.setAllowFileAccess(true);
    await controller.setMediaPlaybackRequiresUserGesture(true);
    await controller.setSupportZoom(false);
    await controller.setTextZoom(125);

    expect(testWebView.settings.allowFullScreenRotate, isTrue);
    expect(testWebView.settings.domStorageEnabled, isFalse);
    expect(testWebView.settings.javaScriptCanOpenWindowsAutomatically, isFalse);
    expect(testWebView.settings.supportMultipleWindows, isFalse);
    expect(testWebView.settings.loadWithOverviewMode, isFalse);
    expect(testWebView.settings.useWideViewPort, isFalse);
    expect(testWebView.settings.displayZoomControls, isTrue);
    expect(testWebView.settings.builtInZoomControls, isFalse);
    expect(testWebView.settings.allowFileAccess, isTrue);
    expect(testWebView.settings.mediaPlaybackRequiresUserGesture, isTrue);
    expect(testWebView.settings.supportZoom, isFalse);
    expect(testWebView.settings.textZoom, 125);
  });

  test('cookie manager encodes cookies before setting them', () async {
    final TestCookieManager testCookieManager = TestCookieManager();
    final OhosWebViewCookieManager cookieManager = OhosWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
      cookieManager: testCookieManager,
    );

    await cookieManager.setCookie(
      const WebViewCookie(
        name: 'session_id',
        value: 'abc=123',
        domain: 'https://example.com',
      ),
    );

    expect(testCookieManager.lastSetCookieUrl, 'https://example.com');
    expect(
      testCookieManager.lastSetCookieValue,
      'session_id=abc%3D123; path=/',
    );
  });

  test('cookie manager rejects invalid cookies before native calls', () async {
    final TestCookieManager testCookieManager = TestCookieManager();
    final OhosWebViewCookieManager cookieManager = OhosWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
      cookieManager: testCookieManager,
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

    expect(testCookieManager.lastSetCookieUrl, isNull);
    expect(testCookieManager.lastSetCookieValue, isNull);
  });

  test('cookie manager parses fetched cookies', () async {
    final TestCookieManager testCookieManager = TestCookieManager()
      ..cookies = 'session=abc123; token=a=b; malformed';
    final OhosWebViewCookieManager cookieManager = OhosWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
      cookieManager: testCookieManager,
    );
    final Uri url = Uri.parse('https://example.com/path');

    final List<WebViewCookie> cookies = await cookieManager.getCookies(url);

    expect(testCookieManager.lastGetCookiesUrl, url.toString());
    expect(cookies, hasLength(2));
    expect(cookies[0].name, 'session');
    expect(cookies[0].value, 'abc123');
    expect(cookies[0].domain, url.host);
    expect(cookies[0].path, '/');
    expect(cookies[1].name, 'token');
    expect(cookies[1].value, 'a=b');
  });

  test(
    'navigation delegate reloads approved main-frame requests with headers',
    () async {
      final InstanceManager instanceManager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      late TestWebViewClient webViewClient;
      final OhosNavigationDelegate delegate = _createTestNavigationDelegate(
        instanceManager: instanceManager,
        onCreateWebViewClient: (TestWebViewClient client) {
          webViewClient = client;
        },
      );
      final List<NavigationRequest> navigationRequests = <NavigationRequest>[];
      final List<LoadRequestParams> loadRequests = <LoadRequestParams>[];

      await delegate.setOnLoadRequest((LoadRequestParams params) async {
        loadRequests.add(params);
      });
      await delegate.setOnNavigationRequest((NavigationRequest request) async {
        navigationRequests.add(request);
        return NavigationDecision.navigate;
      });

      webViewClient.requestLoading!(
        ohos_webview.WebView.detached(instanceManager: instanceManager),
        ohos_webview.WebResourceRequest(
          url: 'https://example.com/allowed',
          isForMainFrame: true,
          isRedirect: false,
          hasGesture: true,
          method: 'GET',
          requestHeaders: const <String, String>{'X-Test': 'yes'},
        ),
      );
      await _flushAsyncEvents();

      expect(
        webViewClient.synchronousReturnValueForShouldOverrideUrlLoading,
        isTrue,
      );
      expect(navigationRequests, hasLength(1));
      expect(navigationRequests.single.url, 'https://example.com/allowed');
      expect(navigationRequests.single.isMainFrame, isTrue);
      expect(loadRequests, hasLength(1));
      expect(loadRequests.single.uri, Uri.parse('https://example.com/allowed'));
      expect(loadRequests.single.headers, const <String, String>{
        'X-Test': 'yes',
      });
    },
  );

  test(
    'navigation delegate does not promote prevented or sub-frame requests',
    () async {
      final InstanceManager instanceManager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      late TestWebViewClient webViewClient;
      final OhosNavigationDelegate delegate = _createTestNavigationDelegate(
        instanceManager: instanceManager,
        onCreateWebViewClient: (TestWebViewClient client) {
          webViewClient = client;
        },
      );
      final List<NavigationRequest> navigationRequests = <NavigationRequest>[];
      final List<LoadRequestParams> loadRequests = <LoadRequestParams>[];

      await delegate.setOnLoadRequest((LoadRequestParams params) async {
        loadRequests.add(params);
      });
      await delegate.setOnNavigationRequest((NavigationRequest request) {
        navigationRequests.add(request);
        if (request.url.contains('blocked')) {
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      });

      webViewClient.requestLoading!(
        ohos_webview.WebView.detached(instanceManager: instanceManager),
        ohos_webview.WebResourceRequest(
          url: 'https://example.com/blocked',
          isForMainFrame: true,
          isRedirect: false,
          hasGesture: false,
          method: 'GET',
          requestHeaders: const <String, String>{},
        ),
      );
      webViewClient.requestLoading!(
        ohos_webview.WebView.detached(instanceManager: instanceManager),
        ohos_webview.WebResourceRequest(
          url: 'https://third-party.example/frame',
          isForMainFrame: false,
          isRedirect: false,
          hasGesture: false,
          method: 'GET',
          requestHeaders: const <String, String>{},
        ),
      );
      await _flushAsyncEvents();

      expect(navigationRequests, hasLength(2));
      expect(navigationRequests[0].isMainFrame, isTrue);
      expect(navigationRequests[1].isMainFrame, isFalse);
      expect(loadRequests, isEmpty);
    },
  );

  test('navigation delegate forwards web resource errors', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    late TestWebViewClient webViewClient;
    final OhosNavigationDelegate delegate = _createTestNavigationDelegate(
      instanceManager: instanceManager,
      onCreateWebViewClient: (TestWebViewClient client) {
        webViewClient = client;
      },
    );
    final List<OhosWebResourceError> errors = <OhosWebResourceError>[];

    await delegate.setOnWebResourceError((error) {
      errors.add(error as OhosWebResourceError);
    });
    webViewClient.onReceivedRequestError!(
      ohos_webview.WebView.detached(instanceManager: instanceManager),
      ohos_webview.WebResourceRequest(
        url: 'https://example.com/slow',
        isForMainFrame: false,
        isRedirect: false,
        hasGesture: false,
        method: 'GET',
        requestHeaders: const <String, String>{},
      ),
      ohos_webview.WebResourceError(
        errorCode: ohos_webview.WebViewClient.errorTimeout,
        description: 'Timed out',
      ),
    );

    expect(errors, hasLength(1));
    final OhosWebResourceError error = errors.single;
    expect(error.errorCode, ohos_webview.WebViewClient.errorTimeout);
    expect(error.description, 'Timed out');
    expect(error.errorType, WebResourceErrorType.timeout);
    expect(error.isForMainFrame, isFalse);
    expect(error.url, 'https://example.com/slow');
    // ignore: deprecated_member_use_from_same_package
    expect(error.failingUrl, 'https://example.com/slow');
  });

  test('navigation delegate completes HTTP auth requests once', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    late TestWebViewClient webViewClient;
    final OhosNavigationDelegate delegate = _createTestNavigationDelegate(
      instanceManager: instanceManager,
      onCreateWebViewClient: (TestWebViewClient client) {
        webViewClient = client;
      },
    );
    final List<HttpAuthRequest> requests = <HttpAuthRequest>[];
    final TestHttpAuthHandler httpAuthHandler = TestHttpAuthHandler(
      instanceManager,
    );

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

    webViewClient.onReceivedHttpAuthRequest!(
      ohos_webview.WebView.detached(instanceManager: instanceManager),
      httpAuthHandler,
      'secure.example.test',
      'Restricted Area',
    );
    await _flushAsyncEvents();

    expect(requests, hasLength(1));
    expect(requests.single.host, 'secure.example.test');
    expect(requests.single.realm, 'Restricted Area');
    expect(httpAuthHandler.credentials, hasLength(1));
    expect(httpAuthHandler.credentials.single.user, 'test-user');
    expect(httpAuthHandler.credentials.single.password, 'test-password');
    expect(httpAuthHandler.canceled, isFalse);
  });

  test('navigation delegate cancels HTTP auth without a handler', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    late TestWebViewClient webViewClient;
    _createTestNavigationDelegate(
      instanceManager: instanceManager,
      onCreateWebViewClient: (TestWebViewClient client) {
        webViewClient = client;
      },
    );
    final TestHttpAuthHandler httpAuthHandler = TestHttpAuthHandler(
      instanceManager,
    );

    webViewClient.onReceivedHttpAuthRequest!(
      ohos_webview.WebView.detached(instanceManager: instanceManager),
      httpAuthHandler,
      'secure.example.test',
      'Restricted Area',
    );
    await _flushAsyncEvents();

    expect(httpAuthHandler.credentials, isEmpty);
    expect(httpAuthHandler.canceled, isTrue);
  });

  test('loads files with params through the native WebView', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) => testWebView,
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                return ohos_webview.WebChromeClient.detached(
                  instanceManager: instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
              },
        ),
      ),
    );

    await controller.loadFileWithParams(
      const LoadFileParams(absoluteFilePath: '/tmp/index.html'),
    );

    expect(testWebView.settings.allowFileAccess, isTrue);
    expect(testWebView.loadedUrl, Uri.file('/tmp/index.html').toString());
    expect(testWebView.loadedHeaders, isEmpty);
    expect(testWebView.webChromeClient, isNotNull);
  });

  test('loads OHOS requests with supported method data', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) => testWebView,
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                return ohos_webview.WebChromeClient.detached(
                  instanceManager: instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
              },
        ),
      ),
    );
    final Uint8List body = Uint8List.fromList(<int>[1, 2, 3]);

    await controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.test/page'),
        headers: const <String, String>{'Accept': 'text/html'},
      ),
    );
    expect(testWebView.loadedUrl, 'https://example.test/page');
    expect(testWebView.loadedHeaders, const <String, String>{
      'Accept': 'text/html',
    });

    await controller.loadRequest(
      LoadRequestParams(
        uri: Uri.parse('https://example.test/form'),
        method: LoadRequestMethod.post,
        body: body,
      ),
    );
    expect(testWebView.postedUrl, 'https://example.test/form');
    expect(testWebView.postedData, orderedEquals(<int>[1, 2, 3]));

    await expectLater(
      () => controller.loadRequest(
        LoadRequestParams(
          uri: Uri.parse('https://example.test/form-with-headers'),
          method: LoadRequestMethod.post,
          headers: const <String, String>{'X-Test': 'yes'},
          body: body,
        ),
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('runs and parses OHOS JavaScript results', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) => testWebView,
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                return ohos_webview.WebChromeClient.detached(
                  instanceManager: instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
              },
        ),
      ),
    );

    await controller.runJavaScript('window.value = 7');
    expect(testWebView.evaluatedJavaScript, 'window.value = 7');

    testWebView.javaScriptResult = 'true';
    expect(await controller.runJavaScriptReturningResult('flag'), isTrue);
    testWebView.javaScriptResult = '42';
    expect(await controller.runJavaScriptReturningResult('count'), 42);
    testWebView.javaScriptResult = '"hello"';
    expect(await controller.runJavaScriptReturningResult('message'), 'hello');
    testWebView.javaScriptResult = '{"message":"ok","count":2,"values":[1,2]}';
    expect(
      await controller.runJavaScriptReturningResult('object'),
      <String, Object>{
        'message': 'ok',
        'count': 2,
        'values': <Object>[1, 2],
      },
    );
    testWebView.javaScriptResult = 'raw string';
    expect(
      await controller.runJavaScriptReturningResult('legacyString'),
      'raw string',
    );

    testWebView.javaScriptResult = 'null';
    await expectLater(
      () => controller.runJavaScriptReturningResult('nullResult'),
      throwsA(isA<ArgumentError>()),
    );
    testWebView.javaScriptResult = null;
    await expectLater(
      () => controller.runJavaScriptReturningResult('undefinedResult'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('dispatches OHOS JavaScript dialog callbacks', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    late TestWebChromeClient webChromeClient;
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) => testWebView,
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                webChromeClient = TestWebChromeClient(
                  instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
                return webChromeClient;
              },
        ),
      ),
    );
    final List<JavaScriptAlertDialogRequest> alertRequests =
        <JavaScriptAlertDialogRequest>[];
    final List<JavaScriptConfirmDialogRequest> confirmRequests =
        <JavaScriptConfirmDialogRequest>[];
    final List<JavaScriptTextInputDialogRequest> promptRequests =
        <JavaScriptTextInputDialogRequest>[];

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

    await webChromeClient.onJsAlert!(
      'https://example.test/alert',
      'hello alert',
    );
    final bool confirmed = await webChromeClient.onJsConfirm!(
      'https://example.test/confirm',
      'continue?',
    );
    final String promptValue = await webChromeClient.onJsPrompt!(
      'https://example.test/prompt',
      'name',
      'default value',
    );

    expect(webChromeClient.synchronousReturnValueForOnJsAlert, isTrue);
    expect(webChromeClient.synchronousReturnValueForOnJsConfirm, isTrue);
    expect(webChromeClient.synchronousReturnValueForOnJsPrompt, isTrue);
    expect(alertRequests, hasLength(1));
    expect(alertRequests.single.message, 'hello alert');
    expect(alertRequests.single.url, 'https://example.test/alert');
    expect(confirmRequests, hasLength(1));
    expect(confirmRequests.single.message, 'continue?');
    expect(confirmRequests.single.url, 'https://example.test/confirm');
    expect(confirmed, isFalse);
    expect(promptRequests, hasLength(1));
    expect(promptRequests.single.message, 'name');
    expect(promptRequests.single.url, 'https://example.test/prompt');
    expect(promptRequests.single.defaultText, 'default value');
    expect(promptValue, 'typed value');
  });

  test('dispatches OHOS console messages', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    late TestWebChromeClient webChromeClient;
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) => testWebView,
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                webChromeClient = TestWebChromeClient(
                  instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
                return webChromeClient;
              },
        ),
      ),
    );
    final List<JavaScriptConsoleMessage> messages =
        <JavaScriptConsoleMessage>[];

    await controller.setOnConsoleMessage(messages.add);
    for (final (ohos_webview.ConsoleMessageLevel level, String message)
        in <(ohos_webview.ConsoleMessageLevel, String)>[
          (ohos_webview.ConsoleMessageLevel.tip, 'tip'),
          (ohos_webview.ConsoleMessageLevel.debug, 'debug'),
          (ohos_webview.ConsoleMessageLevel.warning, 'warning'),
          (ohos_webview.ConsoleMessageLevel.error, 'error'),
          (ohos_webview.ConsoleMessageLevel.log, 'log'),
        ]) {
      webChromeClient.onConsoleMessage!(
        webChromeClient,
        ohos_webview.ConsoleMessage(
          lineNumber: 1,
          message: message,
          level: level,
          sourceId: 'https://example.test/',
        ),
      );
    }

    expect(webChromeClient.synchronousReturnValueForOnConsoleMessage, isTrue);
    expect(
      messages.map((JavaScriptConsoleMessage message) => message.level),
      <JavaScriptLogLevel>[
        JavaScriptLogLevel.debug,
        JavaScriptLogLevel.debug,
        JavaScriptLogLevel.warning,
        JavaScriptLogLevel.error,
        JavaScriptLogLevel.log,
      ],
    );
    expect(
      messages.map((JavaScriptConsoleMessage message) => message.message),
      <String>['tip', 'debug', 'warning', 'error', 'log'],
    );
  });

  test('dispatches OHOS scroll position changes', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    final TestWebView testWebView = TestWebView(instanceManager);
    late void Function(int left, int top, int oldLeft, int oldTop)
    capturedOnScrollChanged;
    final OhosWebViewController controller = OhosWebViewController(
      OhosWebViewControllerCreationParams(
        ohosWebStorage:
            // ignore: invalid_use_of_protected_member
            ohos_webview.WebStorage.detached(instanceManager: instanceManager),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebView: ({onScrollChanged}) {
            capturedOnScrollChanged = onScrollChanged!;
            return testWebView;
          },
          createOhosWebChromeClient:
              ({
                onProgressChanged,
                onShowFileChooser,
                onPermissionRequest,
                onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt,
                onConsoleMessage,
                onShowCustomView,
                onHideCustomView,
                onJsAlert,
                onJsConfirm,
                onJsPrompt,
              }) {
                return TestWebChromeClient(
                  instanceManager,
                  onProgressChanged: onProgressChanged,
                  onShowFileChooser: onShowFileChooser,
                  onPermissionRequest: onPermissionRequest,
                  onGeolocationPermissionsShowPrompt:
                      onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt:
                      onGeolocationPermissionsHidePrompt,
                  onConsoleMessage: onConsoleMessage,
                  onShowCustomView: onShowCustomView,
                  onHideCustomView: onHideCustomView,
                  onJsAlert: onJsAlert,
                  onJsConfirm: onJsConfirm,
                  onJsPrompt: onJsPrompt,
                );
              },
        ),
      ),
    );
    final List<ScrollPositionChange> scrollChanges = <ScrollPositionChange>[];

    await controller.setOnScrollPositionChange(scrollChanges.add);
    capturedOnScrollChanged(12, 34, 1, 2);
    await controller.setOnScrollPositionChange(null);
    capturedOnScrollChanged(56, 78, 12, 34);

    expect(scrollChanges, hasLength(1));
    expect(scrollChanges.single.x, 12);
    expect(scrollChanges.single.y, 34);
  });

  test(
    'dispatches OHOS permission requests and grants mapped resources',
    () async {
      final InstanceManager instanceManager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      final TestWebView testWebView = TestWebView(instanceManager);
      late ohos_webview.WebChromeClient webChromeClient;
      final OhosWebViewController controller = OhosWebViewController(
        OhosWebViewControllerCreationParams(
          ohosWebStorage:
              // ignore: invalid_use_of_protected_member
              ohos_webview.WebStorage.detached(
                instanceManager: instanceManager,
              ),
          ohosWebViewProxy: OhosWebViewProxy(
            createOhosWebView: ({onScrollChanged}) => testWebView,
            createOhosWebChromeClient:
                ({
                  onProgressChanged,
                  onShowFileChooser,
                  onPermissionRequest,
                  onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt,
                  onConsoleMessage,
                  onShowCustomView,
                  onHideCustomView,
                  onJsAlert,
                  onJsConfirm,
                  onJsPrompt,
                }) {
                  webChromeClient = ohos_webview.WebChromeClient.detached(
                    instanceManager: instanceManager,
                    onProgressChanged: onProgressChanged,
                    onShowFileChooser: onShowFileChooser,
                    onPermissionRequest: onPermissionRequest,
                    onGeolocationPermissionsShowPrompt:
                        onGeolocationPermissionsShowPrompt,
                    onGeolocationPermissionsHidePrompt:
                        onGeolocationPermissionsHidePrompt,
                    onConsoleMessage: onConsoleMessage,
                    onShowCustomView: onShowCustomView,
                    onHideCustomView: onHideCustomView,
                    onJsAlert: onJsAlert,
                    onJsConfirm: onJsConfirm,
                    onJsPrompt: onJsPrompt,
                  );
                  return webChromeClient;
                },
          ),
        ),
      );
      final List<PlatformWebViewPermissionRequest> requests =
          <PlatformWebViewPermissionRequest>[];
      await controller.setOnPlatformPermissionRequest(requests.add);
      final TestPermissionRequest nativeRequest = TestPermissionRequest(
        instanceManager,
        resources: const <String>[
          ohos_webview.PermissionRequest.videoCapture,
          ohos_webview.PermissionRequest.audioCapture,
          ohos_webview.PermissionRequest.midiSysex,
          ohos_webview.PermissionRequest.protectedMediaId,
        ],
      );

      webChromeClient.onPermissionRequest!(webChromeClient, nativeRequest);
      await requests.single.grant();
      await requests.single.deny();
      await requests.single.grant();

      expect(
        requests.single.types,
        unorderedEquals(<WebViewPermissionResourceType>[
          WebViewPermissionResourceType.camera,
          WebViewPermissionResourceType.microphone,
          OhosWebViewPermissionResourceType.midiSysex,
          OhosWebViewPermissionResourceType.protectedMediaId,
        ]),
      );
      expect(
        nativeRequest.grantedResources,
        unorderedEquals(<String>[
          ohos_webview.PermissionRequest.videoCapture,
          ohos_webview.PermissionRequest.audioCapture,
          ohos_webview.PermissionRequest.midiSysex,
          ohos_webview.PermissionRequest.protectedMediaId,
        ]),
      );
      expect(nativeRequest.denied, isFalse);
      expect(nativeRequest.grantCount, 1);
      expect(nativeRequest.denyCount, 0);
    },
  );

  test(
    'denies OHOS permission requests without recognized resources',
    () async {
      final InstanceManager instanceManager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      final TestWebView testWebView = TestWebView(instanceManager);
      late ohos_webview.WebChromeClient webChromeClient;
      final OhosWebViewController controller = OhosWebViewController(
        OhosWebViewControllerCreationParams(
          ohosWebStorage:
              // ignore: invalid_use_of_protected_member
              ohos_webview.WebStorage.detached(
                instanceManager: instanceManager,
              ),
          ohosWebViewProxy: OhosWebViewProxy(
            createOhosWebView: ({onScrollChanged}) => testWebView,
            createOhosWebChromeClient:
                ({
                  onProgressChanged,
                  onShowFileChooser,
                  onPermissionRequest,
                  onGeolocationPermissionsShowPrompt,
                  onGeolocationPermissionsHidePrompt,
                  onConsoleMessage,
                  onShowCustomView,
                  onHideCustomView,
                  onJsAlert,
                  onJsConfirm,
                  onJsPrompt,
                }) {
                  webChromeClient = ohos_webview.WebChromeClient.detached(
                    instanceManager: instanceManager,
                    onProgressChanged: onProgressChanged,
                    onShowFileChooser: onShowFileChooser,
                    onPermissionRequest: onPermissionRequest,
                    onGeolocationPermissionsShowPrompt:
                        onGeolocationPermissionsShowPrompt,
                    onGeolocationPermissionsHidePrompt:
                        onGeolocationPermissionsHidePrompt,
                    onConsoleMessage: onConsoleMessage,
                    onShowCustomView: onShowCustomView,
                    onHideCustomView: onHideCustomView,
                    onJsAlert: onJsAlert,
                    onJsConfirm: onJsConfirm,
                    onJsPrompt: onJsPrompt,
                  );
                  return webChromeClient;
                },
          ),
        ),
      );
      bool callbackCalled = false;
      await controller.setOnPlatformPermissionRequest((_) {
        callbackCalled = true;
      });
      final TestPermissionRequest nativeRequest = TestPermissionRequest(
        instanceManager,
        resources: const <String>['TYPE_UNKNOWN_RESOURCE'],
      );

      webChromeClient.onPermissionRequest!(webChromeClient, nativeRequest);

      expect(callbackCalled, isFalse);
      expect(nativeRequest.denied, isTrue);
      expect(nativeRequest.denyCount, 1);
      expect(nativeRequest.grantedResources, isNull);
    },
  );

  test('navigation delegate forwards HTTP response errors', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    late ohos_webview.WebViewClient webViewClient;
    final OhosNavigationDelegate delegate = OhosNavigationDelegate(
      OhosNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
        const PlatformNavigationDelegateCreationParams(),
        ohosWebViewProxy: OhosWebViewProxy(
          createOhosWebViewClient:
              ({
                onPageStarted,
                onPageFinished,
                onReceivedRequestError,
                onReceivedHttpError,
                onReceivedError,
                requestLoading,
                urlLoading,
                doUpdateVisitedHistory,
                onReceivedHttpAuthRequest,
                onReceivedSslAuthError,
              }) {
                webViewClient = ohos_webview.WebViewClient.detached(
                  instanceManager: instanceManager,
                  onPageStarted: onPageStarted,
                  onPageFinished: onPageFinished,
                  onReceivedRequestError: onReceivedRequestError,
                  onReceivedHttpError: onReceivedHttpError,
                  // ignore: deprecated_member_use_from_same_package
                  onReceivedError: onReceivedError,
                  requestLoading: requestLoading,
                  urlLoading: urlLoading,
                  doUpdateVisitedHistory: doUpdateVisitedHistory,
                  onReceivedHttpAuthRequest: onReceivedHttpAuthRequest,
                  onReceivedSslAuthError: onReceivedSslAuthError,
                );
                return webViewClient;
              },
          createDownloadListener: ({required onDownloadStart}) {
            return ohos_webview.DownloadListener.detached(
              instanceManager: instanceManager,
              onDownloadStart: onDownloadStart,
            );
          },
        ),
      ),
    );

    HttpResponseError? receivedError;
    await delegate.setOnHttpError((HttpResponseError error) {
      receivedError = error;
    });

    webViewClient.onReceivedHttpError!(
      ohos_webview.WebView.detached(instanceManager: instanceManager),
      ohos_webview.WebResourceRequest(
        url: 'https://example.com/missing',
        isForMainFrame: true,
        isRedirect: false,
        hasGesture: false,
        method: 'GET',
        requestHeaders: const <String, String>{'Accept': 'text/html'},
      ),
      ohos_webview.WebResourceResponse(
        statusCode: 404,
        responseHeaders: const <String, String>{'X-Test': 'yes'},
        reasonPhrase: 'Not Found',
        mimeType: 'text/html',
      ),
    );

    expect(receivedError, isNotNull);
    expect(
      receivedError!.request!.uri,
      Uri.parse('https://example.com/missing'),
    );
    expect(receivedError!.request, isA<OhosWebResourceRequest>());
    final OhosWebResourceRequest request =
        receivedError!.request! as OhosWebResourceRequest;
    expect(request.isForMainFrame, isTrue);
    expect(request.isRedirect, isFalse);
    expect(request.hasGesture, isFalse);
    expect(request.method, 'GET');
    expect(request.headers, const <String, String>{'Accept': 'text/html'});
    expect(receivedError!.response!.statusCode, 404);
    expect(receivedError!.response!.headers, containsPair('X-Test', 'yes'));
    expect(receivedError!.response, isA<OhosWebResourceResponse>());
    final OhosWebResourceResponse response =
        receivedError!.response! as OhosWebResourceResponse;
    expect(response.reasonPhrase, 'Not Found');
    expect(response.mimeType, 'text/html');
  });

  test(
    'navigation delegate completes SSL auth errors once without fake certificate',
    () async {
      final InstanceManager instanceManager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      late ohos_webview.WebViewClient webViewClient;
      final OhosNavigationDelegate delegate = OhosNavigationDelegate(
        OhosNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
          const PlatformNavigationDelegateCreationParams(),
          ohosWebViewProxy: OhosWebViewProxy(
            createOhosWebViewClient:
                ({
                  onPageStarted,
                  onPageFinished,
                  onReceivedRequestError,
                  onReceivedHttpError,
                  onReceivedError,
                  requestLoading,
                  urlLoading,
                  doUpdateVisitedHistory,
                  onReceivedHttpAuthRequest,
                  onReceivedSslAuthError,
                }) {
                  webViewClient = ohos_webview.WebViewClient.detached(
                    instanceManager: instanceManager,
                    onPageStarted: onPageStarted,
                    onPageFinished: onPageFinished,
                    onReceivedRequestError: onReceivedRequestError,
                    onReceivedHttpError: onReceivedHttpError,
                    // ignore: deprecated_member_use_from_same_package
                    onReceivedError: onReceivedError,
                    requestLoading: requestLoading,
                    urlLoading: urlLoading,
                    doUpdateVisitedHistory: doUpdateVisitedHistory,
                    onReceivedHttpAuthRequest: onReceivedHttpAuthRequest,
                    onReceivedSslAuthError: onReceivedSslAuthError,
                  );
                  return webViewClient;
                },
            createDownloadListener: ({required onDownloadStart}) {
              return ohos_webview.DownloadListener.detached(
                instanceManager: instanceManager,
                onDownloadStart: onDownloadStart,
              );
            },
          ),
        ),
      );
      final List<PlatformSslAuthError> errors = <PlatformSslAuthError>[];
      await delegate.setOnSSlAuthError(errors.add);
      final TestSslAuthHandler sslAuthHandler = TestSslAuthHandler(
        instanceManager,
      );

      webViewClient.onReceivedSslAuthError!(
        ohos_webview.WebView.detached(instanceManager: instanceManager),
        sslAuthHandler,
        'https://expired.example.test/',
        ohos_webview.WebViewClient.errorFailedSslHandshake,
        '',
      );

      expect(errors, hasLength(1));
      expect(errors.single.certificate, isNull);
      expect(
        errors.single.description,
        'SSL certificate error for https://expired.example.test/.',
      );
      expect(errors.single, isA<OhosPlatformSslAuthError>());
      final OhosPlatformSslAuthError error =
          errors.single as OhosPlatformSslAuthError;
      expect(error.url, 'https://expired.example.test/');
      expect(
        error.errorCode,
        ohos_webview.WebViewClient.errorFailedSslHandshake,
      );

      await error.proceed();
      await error.cancel();
      await error.proceed();
      expect(sslAuthHandler.proceeded, isTrue);
      expect(sslAuthHandler.canceled, isFalse);
      expect(sslAuthHandler.proceedCount, 1);
      expect(sslAuthHandler.cancelCount, 0);
    },
  );

  test('navigation delegate cancels SSL auth without a handler', () async {
    final InstanceManager instanceManager = InstanceManager(
      onWeakReferenceRemoved: (_) {},
    );
    late TestWebViewClient webViewClient;
    _createTestNavigationDelegate(
      instanceManager: instanceManager,
      onCreateWebViewClient: (TestWebViewClient client) {
        webViewClient = client;
      },
    );
    final TestSslAuthHandler sslAuthHandler = TestSslAuthHandler(
      instanceManager,
    );

    webViewClient.onReceivedSslAuthError!(
      ohos_webview.WebView.detached(instanceManager: instanceManager),
      sslAuthHandler,
      'https://expired.example.test/',
      ohos_webview.WebViewClient.errorFailedSslHandshake,
      'Certificate has expired.',
    );
    await _flushAsyncEvents();

    expect(sslAuthHandler.proceedCount, 0);
    expect(sslAuthHandler.cancelCount, 1);
    expect(sslAuthHandler.canceled, isTrue);
  });
}

OhosWebViewController _createTestWebViewController({
  required InstanceManager instanceManager,
  required TestWebView testWebView,
  bool? isAllowFullScreenRotate = false,
  bool domStorageEnabled = true,
  bool javaScriptCanOpenWindowsAutomatically = true,
  bool supportMultipleWindows = true,
  bool loadWithOverviewMode = true,
  bool useWideViewPort = true,
  bool displayZoomControls = false,
  bool builtInZoomControls = true,
  bool? allowFileAccess,
  bool? mediaPlaybackRequiresUserGesture,
  bool? supportZoom,
  int? textZoom,
}) {
  return OhosWebViewController(
    OhosWebViewControllerCreationParams(
      isAllowFullScreenRotate: isAllowFullScreenRotate,
      domStorageEnabled: domStorageEnabled,
      javaScriptCanOpenWindowsAutomatically:
          javaScriptCanOpenWindowsAutomatically,
      supportMultipleWindows: supportMultipleWindows,
      loadWithOverviewMode: loadWithOverviewMode,
      useWideViewPort: useWideViewPort,
      displayZoomControls: displayZoomControls,
      builtInZoomControls: builtInZoomControls,
      allowFileAccess: allowFileAccess,
      mediaPlaybackRequiresUserGesture: mediaPlaybackRequiresUserGesture,
      supportZoom: supportZoom,
      textZoom: textZoom,
      ohosWebStorage:
          // ignore: invalid_use_of_protected_member
          ohos_webview.WebStorage.detached(instanceManager: instanceManager),
      ohosWebViewProxy: OhosWebViewProxy(
        createOhosWebView: ({onScrollChanged}) => testWebView,
        createOhosWebChromeClient:
            ({
              onProgressChanged,
              onShowFileChooser,
              onPermissionRequest,
              onGeolocationPermissionsShowPrompt,
              onGeolocationPermissionsHidePrompt,
              onConsoleMessage,
              onShowCustomView,
              onHideCustomView,
              onJsAlert,
              onJsConfirm,
              onJsPrompt,
            }) {
              return ohos_webview.WebChromeClient.detached(
                instanceManager: instanceManager,
                onProgressChanged: onProgressChanged,
                onShowFileChooser: onShowFileChooser,
                onPermissionRequest: onPermissionRequest,
                onGeolocationPermissionsShowPrompt:
                    onGeolocationPermissionsShowPrompt,
                onGeolocationPermissionsHidePrompt:
                    onGeolocationPermissionsHidePrompt,
                onConsoleMessage: onConsoleMessage,
                onShowCustomView: onShowCustomView,
                onHideCustomView: onHideCustomView,
                onJsAlert: onJsAlert,
                onJsConfirm: onJsConfirm,
                onJsPrompt: onJsPrompt,
              );
            },
      ),
    ),
  );
}

OhosNavigationDelegate _createTestNavigationDelegate({
  required InstanceManager instanceManager,
  required void Function(TestWebViewClient client) onCreateWebViewClient,
}) {
  return OhosNavigationDelegate(
    OhosNavigationDelegateCreationParams.fromPlatformNavigationDelegateCreationParams(
      const PlatformNavigationDelegateCreationParams(),
      ohosWebViewProxy: OhosWebViewProxy(
        createOhosWebViewClient:
            ({
              onPageStarted,
              onPageFinished,
              onReceivedRequestError,
              onReceivedHttpError,
              onReceivedError,
              requestLoading,
              urlLoading,
              doUpdateVisitedHistory,
              onReceivedHttpAuthRequest,
              onReceivedSslAuthError,
            }) {
              final TestWebViewClient client = TestWebViewClient(
                instanceManager,
                onPageStarted: onPageStarted,
                onPageFinished: onPageFinished,
                onReceivedRequestError: onReceivedRequestError,
                onReceivedHttpError: onReceivedHttpError,
                requestLoading: requestLoading,
                urlLoading: urlLoading,
                doUpdateVisitedHistory: doUpdateVisitedHistory,
                onReceivedHttpAuthRequest: onReceivedHttpAuthRequest,
                onReceivedSslAuthError: onReceivedSslAuthError,
              );
              onCreateWebViewClient(client);
              return client;
            },
        createDownloadListener: ({required onDownloadStart}) {
          return ohos_webview.DownloadListener.detached(
            instanceManager: instanceManager,
            onDownloadStart: onDownloadStart,
          );
        },
      ),
    ),
  );
}

Future<void> _flushAsyncEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

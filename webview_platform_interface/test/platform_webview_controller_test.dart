// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'platform_navigation_delegate_test.dart';
import 'webview_platform_test.mocks.dart';

@GenerateMocks(<Type>[PlatformNavigationDelegate])
void main() {
  setUp(() {
    WebViewPlatform.instance = MockWebViewPlatformWithMixin();
  });

  test('Cannot be implemented with `implements`', () {
    when(
      (WebViewPlatform.instance! as MockWebViewPlatform)
          .createPlatformWebViewController(any),
    ).thenReturn(ImplementsPlatformWebViewController());

    expect(() {
      PlatformWebViewController(
        const PlatformWebViewControllerCreationParams(),
      );
      // In versions of `package:plugin_platform_interface` prior to fixing
      // https://github.com/flutter/flutter/issues/109339, an attempt to
      // implement a platform interface using `implements` would sometimes throw
      // a `NoSuchMethodError` and other times throw an `AssertionError`.  After
      // the issue is fixed, an `AssertionError` will always be thrown.  For the
      // purpose of this test, we don't really care what exception is thrown, so
      // just allow any exception.
    }, throwsA(anything));
  });

  test('Can be extended', () {
    const params = PlatformWebViewControllerCreationParams();
    when(
      (WebViewPlatform.instance! as MockWebViewPlatform)
          .createPlatformWebViewController(any),
    ).thenReturn(ExtendsPlatformWebViewController(params));

    expect(PlatformWebViewController(params), isNotNull);
  });

  test('builds user scripts with a consistent private scope', () {
    final UserScriptSourcePlatformWebViewController controller =
        UserScriptSourcePlatformWebViewController(
          const PlatformWebViewControllerCreationParams(),
        );
    const WebViewUserScript script = WebViewUserScript(
      source: 'globalThis.provider = {};',
    );

    final String nativeFiltered = controller.buildSource(
      script,
      platformHandlesMainFrameOnly: true,
    );
    expect(nativeFiltered, contains('(function() {'));
    expect(nativeFiltered, contains('globalThis.provider = {};'));
    expect(nativeFiltered, isNot(contains('globalThis.top !== globalThis')));

    final String sourceFiltered = controller.buildSource(
      script,
      platformHandlesMainFrameOnly: false,
    );
    expect(sourceFiltered, contains('globalThis.top !== globalThis'));
    expect(sourceFiltered, contains('globalThis.provider = {};'));
    expect(sourceFiltered, contains('}).call(globalThis);'));
  });

  test('Can be mocked with `implements`', () {
    when(
      (WebViewPlatform.instance! as MockWebViewPlatform)
          .createPlatformWebViewController(any),
    ).thenReturn(MockWebViewControllerDelegate());

    expect(
      PlatformWebViewController(
        const PlatformWebViewControllerCreationParams(),
      ),
      isNotNull,
    );
  });

  test(
    'Default implementation of loadFile should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.loadFile(''), throwsUnimplementedError);
    },
  );

  test('loadFileWithParams redirects to loadFile with correct path', () async {
    final controller = LoadFileSpyPlatformWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );

    const testPath = 'file:///test/index.html';
    const params = LoadFileParams(absoluteFilePath: testPath);

    await controller.loadFileWithParams(params);

    expect(controller.loadFilePath, equals(testPath));
  });

  test(
    'Default implementation of loadFlutterAsset should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.loadFlutterAsset(''), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of loadHtmlString should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.loadHtmlString(''), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of loadRequest should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.loadRequest(MockLoadRequestParamsDelegate()),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of currentUrl should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.currentUrl(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of canGoBack should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.canGoBack(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of canGoForward should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.canGoForward(), throwsUnimplementedError);
    },
  );

  test('Default implementation of goBack should throw unimplemented error', () {
    final PlatformWebViewController controller =
        ExtendsPlatformWebViewController(
          const PlatformWebViewControllerCreationParams(),
        );

    expect(() => controller.goBack(), throwsUnimplementedError);
  });

  test(
    'Default implementation of goForward should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.goForward(), throwsUnimplementedError);
    },
  );

  test('Default implementation of reload should throw unimplemented error', () {
    final PlatformWebViewController controller =
        ExtendsPlatformWebViewController(
          const PlatformWebViewControllerCreationParams(),
        );

    expect(() => controller.reload(), throwsUnimplementedError);
  });

  test(
    'Default implementation of clearCache should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.clearCache(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of clearLocalStorage should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.clearLocalStorage(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of the setNavigationCallback should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () =>
            controller.setPlatformNavigationDelegate(MockNavigationDelegate()),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of runJavaScript should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.runJavaScript('javaScript'),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of runJavaScriptReturningResult should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.runJavaScriptReturningResult('javaScript'),
        throwsUnimplementedError,
      );
    },
  );

  test('New JavaScript defaults fail safely for older implementations', () {
    final PlatformWebViewController controller =
        ExtendsPlatformWebViewController(
          const PlatformWebViewControllerCreationParams(),
        );

    expect(
      () => controller.callAsyncJavaScript(
        JavaScriptInvocationParams(functionBody: 'return 1;'),
      ),
      throwsUnsupportedError,
    );
    expect(
      controller.isUserScriptInjectionSupported(
        WebViewUserScriptInjectionTime.documentStart,
      ),
      completion(isFalse),
    );
    expect(controller.isOffscreenWebViewSupported(), completion(isFalse));
    expect(() => controller.closeOffscreenWebView(), throwsUnsupportedError);
    expect(controller.removeUserScript('missing'), completes);
    expect(controller.removeAllUserScripts(), completes);
  });

  test(
    'Default implementation of addJavaScriptChannel should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.addJavaScriptChannel(
          JavaScriptChannelParams(name: 'test', onMessageReceived: (_) {}),
        ),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of removeJavaScriptChannel should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.removeJavaScriptChannel('test'),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of getTitle should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.getTitle(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of scrollTo should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.scrollTo(0, 0), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of scrollBy should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.scrollBy(0, 0), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of setVerticalScrollBarEnabled should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setVerticalScrollBarEnabled(false),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setHorizontalScrollBarEnabled should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setHorizontalScrollBarEnabled(false),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of supportsSetScrollBarsEnabled returns false',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(controller.supportsSetScrollBarsEnabled(), isFalse);
    },
  );

  test(
    'Default implementation of getScrollPosition should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.getScrollPosition(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of enableZoom should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.enableZoom(true), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of setBackgroundColor should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setBackgroundColor(Colors.blue),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setJavaScriptMode should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setJavaScriptMode(JavaScriptMode.disabled),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setUserAgent should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.setUserAgent(null), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of setOnPermissionRequest should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOnPlatformPermissionRequest((_) {}),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of getUserAgent should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(() => controller.getUserAgent(), throwsUnimplementedError);
    },
  );

  test(
    'Default implementation of setOnConsoleMessage should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOnConsoleMessage(
          (JavaScriptConsoleMessage message) {},
        ),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setOnJavaScriptAlertDialog should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOnJavaScriptAlertDialog((_) async {}),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setOnJavaScriptConfirmDialog should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOnJavaScriptConfirmDialog((_) async {
          return false;
        }),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setOnJavaScriptTextInputDialog should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOnJavaScriptTextInputDialog((_) async {
          return '';
        }),
        throwsUnimplementedError,
      );
    },
  );

  test(
    'Default implementation of setOverScrollMode should throw unimplemented error',
    () {
      final PlatformWebViewController controller =
          ExtendsPlatformWebViewController(
            const PlatformWebViewControllerCreationParams(),
          );

      expect(
        () => controller.setOverScrollMode(WebViewOverScrollMode.always),
        throwsUnimplementedError,
      );
    },
  );
}

class MockWebViewPlatformWithMixin extends MockWebViewPlatform
    with
        // ignore: prefer_mixin
        MockPlatformInterfaceMixin {}

class ImplementsPlatformWebViewController implements PlatformWebViewController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockWebViewControllerDelegate extends Mock
    with
        // ignore: prefer_mixin
        MockPlatformInterfaceMixin
    implements PlatformWebViewController {}

class ExtendsPlatformWebViewController extends PlatformWebViewController {
  ExtendsPlatformWebViewController(super.params) : super.implementation();
}

class LoadFileSpyPlatformWebViewController extends PlatformWebViewController {
  LoadFileSpyPlatformWebViewController(super.params) : super.implementation();

  String? loadFilePath;

  @override
  Future<void> loadFile(String absoluteFilePath) async {
    loadFilePath = absoluteFilePath;
  }
}

class UserScriptSourcePlatformWebViewController
    extends PlatformWebViewController {
  UserScriptSourcePlatformWebViewController(super.params)
    : super.implementation();

  String buildSource(
    WebViewUserScript script, {
    required bool platformHandlesMainFrameOnly,
  }) {
    return buildUserScriptSource(
      script,
      platformHandlesMainFrameOnly: platformHandlesMainFrameOnly,
    );
  }
}

// ignore: must_be_immutable
class MockLoadRequestParamsDelegate extends Mock
    with
        //ignore: prefer_mixin
        MockPlatformInterfaceMixin
    implements LoadRequestParams {}

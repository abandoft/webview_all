// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:webview_all_android/src/android_webkit.g.dart'
    as android_webview;
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'android_webview_cookie_manager_test.mocks.dart';

@GenerateMocks(<Type>[android_webview.CookieManager, AndroidWebViewController])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cookie deletion preserves host/domain identity and secure prefixes',
    () async {
      final native = MockCookieManager();
      when(native.setCookie(any, any)).thenAnswer((_) async {});
      final manager = AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
        cookieManager: native,
      );
      await manager.deleteCookie(
        name: 'host',
        domain: 'example.test',
        path: '/account',
      );
      await manager.deleteCookie(
        name: 'domain',
        domain: '.example.test',
        path: '/account',
      );
      await manager.deleteCookie(
        name: '__Host-Http-auth',
        domain: 'example.test',
      );
      final headers = verify(
        native.setCookie('https://example.test/account', captureAny),
      ).captured.cast<String>();
      expect(headers[0], isNot(contains('domain=')));
      expect(headers[1], contains('domain=.example.test'));
      final prefixed =
          verify(
                native.setCookie('https://example.test/', captureAny),
              ).captured.single
              as String;
      expect(prefixed, contains('; Secure'));
      expect(prefixed, contains('; HttpOnly'));
      expect(prefixed, isNot(contains('domain=')));
      await manager.setCookie(
        const WebViewCookie(
          name: '__Host-auth',
          value: 'value',
          domain: 'example.test',
          isSecure: true,
        ),
      );
      final created =
          verify(
                native.setCookie('https://example.test/', captureAny),
              ).captured.single
              as String;
      expect(created, contains('; Secure'));
      expect(created, isNot(contains('domain=')));
    },
  );

  test('native Max-Age cannot overflow DateTime or wrap into the past', () async {
    final native = MockCookieManager();
    when(native.supportsCookieInfo()).thenAnswer((_) async => true);
    when(native.getCookieInfo(any)).thenAnswer(
      (_) async => [
        'future=value; Domain=example.test; Path=/; Max-Age=9223372036854775807',
        'expired=value; Domain=example.test; Path=/; Max-Age=-9223372036854775808',
      ],
    );
    final manager = AndroidWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
      cookieManager: native,
    );
    final values = await manager.getCookies(Uri.parse('https://example.test/'));
    expect(values[0].expires!.millisecondsSinceEpoch, 8640000000000000);
    expect(values[1].expires!.millisecondsSinceEpoch, 0);
    expect(values.every((v) => v.isSession == false), isTrue);
  });

  test('provider metadata preserves cookie identities, flags and dates', () async {
    final native = MockCookieManager();
    when(native.supportsCookieInfo()).thenAnswer((_) async => true);
    final url = Uri.parse('https://example.test/account/page');
    when(native.getCookieInfo(url.toString())).thenAnswer(
      (_) async => [
        'session=a=b; Path=/account; Domain=.example.test; Secure; HttpOnly; SameSite=Lax',
        'session=second; Path=/; Domain=example.test; Expires=Wed, 21 Oct 2037 07:28:00 GMT; SameSite=Strict',
        'encoded=a%3Bb%3Dc; Path=/',
      ],
    );
    final manager = AndroidWebViewCookieManager(
      const PlatformWebViewCookieManagerCreationParams(),
      cookieManager: native,
    );
    final cookies = await manager.getCookies(url);
    expect(cookies.map((c) => c.name), ['session', 'session', 'encoded']);
    expect(cookies[0].value, 'a=b');
    expect(cookies[0].path, '/account');
    expect(cookies[0].domain, '.example.test');
    expect(cookies[0].isSecure, true);
    expect(cookies[0].isHttpOnly, true);
    expect(cookies[0].sameSite, WebViewCookieSameSite.lax);
    expect(cookies[0].isSession, true);
    expect(cookies[1].expires, DateTime.utc(2037, 10, 21, 7, 28));
    expect(cookies[1].isSession, false);
    expect(cookies[2].value, 'a;b=c');
    expect(
      (await manager.getCapabilities()).readableAttributes,
      contains(WebViewCookieAttribute.httpOnly),
    );
    verifyNever(native.getCookies(any));
  });

  test(
    'metadata failure falls back without dropping existing cookies',
    () async {
      final native = MockCookieManager();
      when(native.supportsCookieInfo()).thenAnswer((_) async => true);
      when(
        native.getCookieInfo(any),
      ).thenThrow(StateError('Unavailable provider'));
      when(native.getCookies(any)).thenAnswer((_) async => 'name=value');
      final manager = AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
        cookieManager: native,
      );
      final cookies = await manager.getCookies(
        Uri.parse('https://example.test/'),
      );
      expect(cookies.single.value, 'value');
      expect(cookies.single.isHttpOnly, isNull);
    },
  );

  test('clearCookies should call android_webview.clearCookies', () async {
    final android_webview.CookieManager mockCookieManager = MockCookieManager();

    when(
      mockCookieManager.removeAllCookies(),
    ).thenAnswer((_) => Future<bool>.value(true));

    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final bool hasClearedCookies = await AndroidWebViewCookieManager(
      params,
      cookieManager: mockCookieManager,
    ).clearCookies();

    expect(hasClearedCookies, true);
    verify(mockCookieManager.removeAllCookies());
  });

  test('setCookie should throw ArgumentError for cookie with invalid path', () {
    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final androidCookieManager = AndroidWebViewCookieManager(
      params,
      cookieManager: MockCookieManager(),
    );

    expect(
      () => androidCookieManager.setCookie(
        const WebViewCookie(
          name: 'foo',
          value: 'bar',
          domain: 'flutter.dev',
          path: 'invalid;path',
        ),
      ),
      throwsA(const TypeMatcher<ArgumentError>()),
    );
  });

  test(
    'setCookie should call android_webview.setCookie with properly formatted cookie value',
    () {
      final android_webview.CookieManager mockCookieManager =
          MockCookieManager();
      final params =
          AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
            const PlatformWebViewCookieManagerCreationParams(),
          );

      AndroidWebViewCookieManager(
        params,
        cookieManager: mockCookieManager,
      ).setCookie(
        const WebViewCookie(name: 'foo&', value: 'bar@', domain: 'flutter.dev'),
      );

      verify(
        mockCookieManager.setCookie(
          'https://flutter.dev/',
          'foo%26=bar%40; path=/; domain=flutter.dev',
        ),
      );
    },
  );

  test('setAcceptThirdPartyCookies', () async {
    final mockController = MockAndroidWebViewController();

    final webView = android_webview.WebView.pigeon_detached();

    final int webViewIdentifier = android_webview.PigeonInstanceManager.instance
        .addDartCreatedInstance(webView);

    when(mockController.webViewIdentifier).thenReturn(webViewIdentifier);

    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final mockCookieManager = MockCookieManager();

    await AndroidWebViewCookieManager(
      params,
      cookieManager: mockCookieManager,
    ).setAcceptThirdPartyCookies(mockController, false);

    verify(mockCookieManager.setAcceptThirdPartyCookies(webView, false));
  });

  test('getCookies should return list of WebViewCookie for a domain', () async {
    final mockCookieManager = MockCookieManager();

    // Mock the return value of getCookies
    when(
      mockCookieManager.getCookies('https://flutter.dev'),
    ).thenAnswer((_) => Future<String>.value('foo=bar; hello=world'));

    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final cookieManager = AndroidWebViewCookieManager(
      params,
      cookieManager: mockCookieManager,
    );

    final List<WebViewCookie> cookies = await cookieManager.getCookies(
      Uri.parse('https://flutter.dev'),
    );

    expect(cookies.length, 2);

    expect(cookies[0].name, 'foo');
    expect(cookies[0].value, 'bar');
    expect(cookies[0].domain, 'flutter.dev');
    expect(cookies[0].path, '/');

    expect(cookies[1].name, 'hello');
    expect(cookies[1].value, 'world');
    expect(cookies[1].domain, 'flutter.dev');
    expect(cookies[1].path, '/');

    verify(mockCookieManager.getCookies('https://flutter.dev')).called(1);
  });

  test('getCookies should return empty list if no cookies exist', () async {
    final mockCookieManager = MockCookieManager();

    when(
      mockCookieManager.getCookies('https://flutter.dev'),
    ).thenAnswer((_) => Future<String>.value(''));

    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final cookieManager = AndroidWebViewCookieManager(
      params,
      cookieManager: mockCookieManager,
    );

    final List<WebViewCookie> cookies = await cookieManager.getCookies(
      Uri.parse('https://flutter.dev'),
    );

    expect(cookies, isEmpty);
    verify(mockCookieManager.getCookies('https://flutter.dev')).called(1);
  });

  test('getCookies should handle single cookie correctly', () async {
    final mockCookieManager = MockCookieManager();

    when(
      mockCookieManager.getCookies('https://flutter.dev'),
    ).thenAnswer((_) => Future<String>.value('sessionId=abc123'));

    final params =
        AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
          const PlatformWebViewCookieManagerCreationParams(),
        );

    final cookieManager = AndroidWebViewCookieManager(
      params,
      cookieManager: mockCookieManager,
    );

    final List<WebViewCookie> cookies = await cookieManager.getCookies(
      Uri.parse('https://flutter.dev'),
    );

    expect(cookies.length, 1);
    expect(cookies[0].name, 'sessionId');
    expect(cookies[0].value, 'abc123');
    expect(cookies[0].domain, 'flutter.dev');

    verify(mockCookieManager.getCookies('https://flutter.dev')).called(1);
  });

  test('getCookies preserves equals signs and decodes components', () async {
    final MockCookieManager mockCookieManager = MockCookieManager();
    when(mockCookieManager.getCookies('https://flutter.dev')).thenAnswer(
      (_) => Future<String>.value(
        'token=abc=def; encoded%26name=a%20b%3Dc%3Bd; malformed=%E0%A4%A',
      ),
    );
    final AndroidWebViewCookieManager
    cookieManager = AndroidWebViewCookieManager(
      AndroidWebViewCookieManagerCreationParams.fromPlatformWebViewCookieManagerCreationParams(
        const PlatformWebViewCookieManagerCreationParams(),
      ),
      cookieManager: mockCookieManager,
    );

    final List<WebViewCookie> cookies = await cookieManager.getCookies(
      Uri.parse('https://flutter.dev'),
    );

    expect(cookies, hasLength(3));
    expect(cookies[0].value, 'abc=def');
    expect(cookies[1].name, 'encoded&name');
    expect(cookies[1].value, 'a b=c;d');
    expect(cookies[2].value, '%E0%A4%A');
  });
}

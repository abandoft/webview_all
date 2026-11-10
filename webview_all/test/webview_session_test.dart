import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  late List<String> messages;
  setUp(() {
    platform = _Platform();
    WebViewPlatform.instance = platform;
    messages = [];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) => messages.add(message ?? '');
    addTearDown(() => debugPrint = previous);
  });

  test(
    'unsupported modes report a reason without creating a WebView',
    () async {
      platform.modes = {WebViewSessionMode.shared};
      expect(await WebViewSession.create(), isNull);
      expect(platform.controllers, isEmpty);
      expect(messages.join(), contains('No WebView was created'));
    },
  );

  test(
    'capability query failure is reported without interrupting the app',
    () async {
      platform.queryError = true;
      expect(await WebViewSession.create(), isNull);
      expect(platform.controllers, isEmpty);
      expect(messages.join(), contains('Cannot query'));
    },
  );

  test('each session receives its own controller and managers', () async {
    final a = (await WebViewSession.create(
      mode: WebViewSessionMode.isolatedIncognito,
    ))!;
    final b = (await WebViewSession.create(
      mode: WebViewSessionMode.isolatedIncognito,
    ))!;
    expect(
      platform.controllers.map((c) => c.params.sessionMode),
      everyElement(WebViewSessionMode.isolatedIncognito),
    );
    expect(platform.controllers.every((c) => c.prepared), isTrue);
    const cookie = WebViewCookie(
      name: 'account',
      value: 'a',
      domain: 'example.test',
    );
    await a.cookieManager.setCookie(cookie);
    expect(
      await a.cookieManager.getCookies(
        domain: Uri.parse('https://example.test'),
      ),
      [cookie],
    );
    expect(
      await b.cookieManager.getCookies(
        domain: Uri.parse('https://example.test'),
      ),
      isEmpty,
    );
    await a.dataManager.clearAllWebsiteData();
    expect(platform.controllers[0].data.clears, 1);
    expect(platform.controllers[1].data.clears, 0);
    await a.close();
    await b.close();
  });

  test(
    'session cookie deletion stays scoped and creation preserves media policy',
    () async {
      final a = (await WebViewSession.create(
        mode: WebViewSessionMode.isolatedIncognito,
        mediaPlaybackPolicy: WebViewMediaPlaybackPolicy.allowWithoutUserGesture,
      ))!;
      final b = (await WebViewSession.create(
        mode: WebViewSessionMode.isolatedIncognito,
      ))!;
      expect(
        a.controller.platform.params.mediaPlaybackPolicy,
        WebViewMediaPlaybackPolicy.allowWithoutUserGesture,
      );
      final cookies = a.cookieManager;
      expect((await cookies.getCapabilities()).deleteByIdentity, isTrue);
      const cookie = WebViewCookie(
        name: 'session',
        value: 'v',
        domain: 'example.test',
      );
      await cookies.setCookie(cookie);
      await b.cookieManager.setCookie(cookie);
      expect(
        await cookies.deleteCookie(name: cookie.name, domain: cookie.domain),
        isTrue,
      );
      expect(
        await cookies.getCookies(domain: Uri.parse('https://example.test/')),
        isEmpty,
      );
      expect(
        await b.cookieManager.getCookies(
          domain: Uri.parse('https://example.test/'),
        ),
        [cookie],
      );
      await a.close();
      expect(() => cookies.getCapabilities(), throwsStateError);
      expect(
        () => cookies.deleteCookie(name: cookie.name, domain: cookie.domain),
        throwsStateError,
      );
      await b.close();
    },
  );

  test(
    'close is idempotent and cached managers cannot act after close',
    () async {
      final session = (await WebViewSession.create())!;
      final cookies = session.cookieManager;
      final data = session.dataManager;
      final first = session.close();
      expect(session.isClosed, isTrue);
      expect(session.close(), same(first));
      await first;
      expect(platform.controllers.single.closes, 1);
      expect(() => session.controller, throwsStateError);
      expect(() => cookies.clearCookies(), throwsStateError);
      expect(() => data.clearAllWebsiteData(), throwsStateError);
      expect(() => data.getCapabilities(), throwsStateError);
      expect(
        () => data.clearWebsiteData(dataTypes: {WebViewDataType.cookies}),
        throwsStateError,
      );
    },
  );

  test(
    'closing from a native disposal callback returns the same close future',
    () async {
      final session = (await WebViewSession.create())!;
      Future<void>? reentrant;
      platform.controllers.single.onClose = () {
        reentrant = session.close();
      };
      final close = session.close();
      await close;
      expect(reentrant, same(close));
      expect(platform.controllers.single.closes, 1);
    },
  );

  test('a failed native creation closes the allocated controller', () async {
    platform.failPreparation = true;
    expect(await WebViewSession.create(), isNull);
    expect(platform.controllers.single.closes, 1);
    expect(messages.join(), contains('creation failed'));
  });

  test(
    'limited incognito is reported and does not request an isolated store',
    () async {
      platform.modes = {
        WebViewSessionMode.shared,
        WebViewSessionMode.incognito,
      };
      platform.incognitoSupport = WebViewIncognitoSupport.limited;
      final session = (await WebViewSession.create())!;
      expect(session.mode, WebViewSessionMode.incognito);
      expect(
        session.capabilities.incognitoSupport,
        WebViewIncognitoSupport.limited,
      );
      expect(messages.join(), contains('Limited incognito handling'));
      await session.close();
    },
  );

  test('explicit shared mode is preserved', () async {
    final session = (await WebViewSession.create(
      mode: WebViewSessionMode.shared,
    ))!;
    expect(
      session.controller.platform.params.sessionMode,
      WebViewSessionMode.shared,
    );
    await session.close();
  });

  test(
    'profile keeps its native owner until the last session closes',
    () async {
      final profile = (await WebViewProfile.create(
        mode: WebViewSessionMode.isolatedIncognito,
      ))!;
      final a = (await profile.createSession())!,
          b = (await profile.createSession())!;
      final anchor = platform.controllers.first;
      await a.cookieManager.setCookie(
        const WebViewCookie(
          name: 'account',
          value: 'one',
          domain: 'example.test',
        ),
      );
      expect(
        (await b.cookieManager.getCookies(
          domain: Uri.parse('https://example.test'),
        )).single.value,
        'one',
      );
      await a.close();
      expect(anchor.closes, 0);
      await profile.close();
      expect(anchor.closes, 0);
      expect(await profile.createSession(), isNull);
      expect(
        (await b.cookieManager.getCookies(
          domain: Uri.parse('https://example.test'),
        )).single.value,
        'one',
      );
      await b.close();
      await profile.whenReleased;
      expect(anchor.closes, 1);
      await profile.close();
      await a.close();
      await b.close();
      expect(platform.controllers.every((c) => c.closes == 1), isTrue);
    },
  );

  test(
    'invalid or unsupported named profiles never create a fallback store',
    () async {
      expect(await WebViewProfile.create(name: '../account'), isNull);
      platform.namedProfiles = false;
      expect(await WebViewProfile.create(name: 'account'), isNull);
      expect(platform.controllers, isEmpty);
      platform.namedProfiles = true;
      final profile = (await WebViewProfile.create(
        name: 'account',
        customSchemes: ['appfixture'],
      ))!;
      expect(platform.controllers.single.params.profileName, 'account');
      expect(platform.controllers.single.params.customSchemes, ['appfixture']);
      await profile.close();
    },
  );

  test(
    'closing a profile during creation releases the late child and its owner',
    () async {
      final profile = (await WebViewProfile.create())!;
      platform.relatedGate = Completer<void>();
      final child = profile.createSession();
      await profile.close();
      expect(platform.controllers.single.closes, 0);
      platform.relatedGate!.complete();
      expect(await child, isNull);
      await profile.whenReleased;
      expect(platform.controllers.length, 2);
      expect(platform.controllers.every((c) => c.closes == 1), isTrue);
    },
  );

  test(
    'failed profile child preparation releases the reservation exactly once',
    () async {
      final profile = (await WebViewProfile.create())!;
      platform.failPreparation = true;
      expect(await profile.createSession(), isNull);
      await profile.close();
      await profile.whenReleased;
      expect(platform.controllers.every((c) => c.closes == 1), isTrue);
    },
  );

  test('public title callback reaches the platform delegate', () async {
    final titles = <String>[];
    final delegate = NavigationDelegate(onTitleChange: titles.add);
    (delegate.platform as _Navigation).title!('Changed');
    (delegate.platform as _Navigation).title!('');
    expect(titles, ['Changed', '']);
  });
}

class _Platform extends WebViewPlatform {
  Set<WebViewSessionMode> modes = WebViewSessionMode.values.toSet();
  WebViewIncognitoSupport incognitoSupport =
      WebViewIncognitoSupport.nativeStore;
  bool failPreparation = false;
  bool queryError = false;
  bool namedProfiles = true;
  Completer<void>? relatedGate;
  final controllers = <_Controller>[];
  @override
  Set<WebViewSessionMode> get supportedSessionModes => modes;
  @override
  Future<WebViewSessionCapabilities> getSessionCapabilities() async {
    if (queryError) throw StateError('runtime missing');
    return WebViewSessionCapabilities(
      supportedModes: modes,
      incognitoSupport: incognitoSupport,
      canClose: true,
      scopedCookies: true,
      scopedWebsiteData: true,
      namedProfiles: namedProfiles,
      relatedControllers: true,
    );
  }

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params, failPreparation);
    controllers.add(controller);
    controller.relatedFactory = () async {
      await relatedGate?.future;
      final child = createPlatformWebViewController(params) as _Controller;
      child.cookies = controller.cookies;
      child.data = controller.data;
      return child;
    };
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => _Navigation(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.fail) : super.implementation();
  final bool fail;
  var cookies = _Cookies();
  var data = _Data();
  Future<PlatformWebViewController?> Function()? relatedFactory;
  @override
  Future<PlatformWebViewController?> createRelatedController() =>
      relatedFactory!();
  bool prepared = false;
  int closes = 0;
  void Function()? onClose;
  @override
  Future<void> prepareSession() async {
    if (fail) throw StateError('native creation failed');
    prepared = true;
  }

  @override
  Future<void> closeWebViewSession() async {
    closes++;
    onClose?.call();
  }

  @override
  PlatformWebViewCookieManager createSessionCookieManager() => cookies;
  @override
  PlatformWebViewDataManager createSessionDataManager() => data;
}

class _Cookies extends PlatformWebViewCookieManager {
  _Cookies()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
  final values = <WebViewCookie>[];
  @override
  Future<WebViewCookieCapabilities> getCapabilities() async =>
      const WebViewCookieCapabilities(deleteByIdentity: true);

  @override
  Future<bool> deleteCookie({
    required String name,
    required String domain,
    String path = '/',
  }) async {
    values.removeWhere(
      (cookie) =>
          cookie.name == name && cookie.domain == domain && cookie.path == path,
    );
    return true;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) async {
    values.add(cookie);
  }

  @override
  Future<List<WebViewCookie>> getCookies(Uri url) async => values;
  @override
  Future<bool> clearCookies() async {
    final had = values.isNotEmpty;
    values.clear();
    return had;
  }
}

class _Data extends PlatformWebViewDataManager {
  _Data()
    : super.implementation(const PlatformWebViewDataManagerCreationParams());
  int clears = 0;
  @override
  Future<WebViewDataClearingResult> clearAllWebsiteData() async {
    clears++;
    return WebViewDataClearingResult(
      clearedDataTypes: WebViewDataType.values.toSet(),
    );
  }
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  TitleChangeCallback? title;
  @override
  Future<void> setOnTitleChange(TitleChangeCallback callback) async {
    title = callback;
  }
}

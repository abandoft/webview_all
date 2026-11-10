import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

class _Controller extends PlatformWebViewController {
  _Controller()
    : super.implementation(const PlatformWebViewControllerCreationParams());
  Future<Uint8List?> capture(Future<Uint8List?> Function() operation) =>
      capturePageData('test capture', operation);
}

class _Cookies extends PlatformWebViewCookieManager {
  _Cookies()
    : super.implementation(const PlatformWebViewCookieManagerCreationParams());
}

class _LifecycleController extends _Controller {
  var exitCalls = 0;
  @override
  Future<void> setFullscreenDelegate(WebViewFullscreenDelegate? delegate) =>
      updateFullscreenDelegate(delegate);
  @override
  Future<bool> exitFullscreen() async {
    exitCalls++;
    return true;
  }

  Future<void> enter() => notifyFullscreenEntered();
  Future<void> leave() => notifyFullscreenExited();
  @override
  Future<void> setOnProcessFailed(
    FutureOr<void> Function(WebViewProcessFailure)? callback,
  ) async => updateProcessFailureCallback(callback);
  Future<void> fail(WebViewProcessFailure failure) =>
      notifyProcessFailed(failure);
  void closeEvents() => disposeBrowserLifecycleCallbacks();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'fullscreen replacement releases the old presentation exactly once',
    () async {
      final controller = _LifecycleController();
      var entered = 0;
      var exited = 0;
      late WebViewFullscreenRequest first;
      final old = WebViewFullscreenDelegate(
        onEnter: (request) {
          entered++;
          first = request;
        },
        onExit: () {
          exited++;
        },
      );
      await controller.setFullscreenDelegate(old);
      await controller.enter();
      await controller.enter();
      expect(entered, 1);
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(onEnter: (_) {}, onExit: () {}),
      );
      expect(controller.exitCalls, 1);
      expect(exited, 1);
      await controller.leave();
      expect(exited, 1);
      await first.exit();
      expect(controller.exitCalls, 1);
    },
  );

  test(
    'failed fullscreen handlers and renderer notifications never escape',
    () async {
      final controller = _LifecycleController();
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(
          onEnter: (_) async => throw StateError('enter fixture'),
          onExit: () async => throw StateError('exit fixture'),
        ),
      );
      await controller.enter();
      expect(controller.exitCalls, 1);
      await controller.setOnProcessFailed(
        (_) async => throw StateError('process fixture'),
      );
      await controller.fail(
        const WebViewProcessFailure(
          kind: WebViewProcessFailureKind.rendererExited,
          recovery: WebViewProcessRecovery.reload,
        ),
      );
      await controller.leave();
    },
  );

  test(
    'pending app exit callbacks do not block delegate replacement or disposal',
    () async {
      final controller = _LifecycleController();
      final held = Completer<void>();
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(onEnter: (_) {}, onExit: () => held.future),
      );
      await controller.enter();
      await controller.setFullscreenDelegate(null);
      expect(controller.exitCalls, 1);
      var entered = 0;
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(
          onEnter: (_) {
            entered++;
          },
          onExit: () => held.future,
        ),
      );
      await controller.enter();
      controller.closeEvents();
      await controller.enter();
      expect(entered, 1);
      held.complete();
    },
  );

  test(
    'an auxiliary process failure does not close a working fullscreen view',
    () async {
      final controller = _LifecycleController();
      var exited = 0;
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(
          onEnter: (_) {},
          onExit: () {
            exited++;
          },
        ),
      );
      await controller.enter();
      await controller.fail(
        const WebViewProcessFailure(
          kind: WebViewProcessFailureKind.other,
          recovery: WebViewProcessRecovery.none,
          nativeCode: 6,
        ),
      );
      expect(exited, 0);
      await controller.leave();
      expect(exited, 1);
    },
  );

  test(
    'unsupported browser operations complete without blocking the app',
    () async {
      final controller = _Controller();
      final caps = await controller.getBrowserCapabilities();
      expect(caps.stopLoading, isFalse);
      expect(caps.findText, isFalse);
      expect(caps.fileSelector, isFalse);
      expect(caps.popupWindowPolicies, isEmpty);
      expect(caps.viewportScreenshot, isFalse);
      expect(caps.pdfExport, isFalse);
      expect(await controller.takeScreenshot(), isNull);
      expect(await controller.createPdf(), isNull);
      expect(caps.newWindowDelegate, isFalse);
      expect(caps.windowCloseRequests, isFalse);
      await controller.setNewWindowDelegate((_) {});
      await controller.setOnWindowCloseRequested(() {});
      expect(caps.fullscreenEvents, isFalse);
      expect(caps.processFailureEvents, isFalse);
      await controller.setFullscreenDelegate(
        WebViewFullscreenDelegate(onEnter: (_) {}, onExit: () {}),
      );
      expect(await controller.exitFullscreen(), isFalse);
      await controller.setOnProcessFailed((_) {});
      await controller.stopLoading();
      expect(await controller.getNavigationHistory(), isNull);
      expect(await controller.goToHistoryIndex(0), isFalse);
      expect(await controller.findText('needle'), isNull);
      await controller.clearFindMatches();
      await controller.setPopupPolicy(WebViewPopupWindowPolicy.deny);
      await controller.setFileSelector((_) async => []);
      await controller.setMediaPlaybackRequiresUserGesture(false);
      expect((await _Cookies().getCapabilities()).readableAttributes, isEmpty);
      expect(
        await _Cookies().deleteCookie(name: 'n', domain: 'example.test'),
        isFalse,
      );
    },
  );

  test(
    'capture operations are serialized and recover after native failures',
    () async {
      final controller = _Controller();
      final held = Completer<Uint8List?>();
      final events = <int>[];
      final first = controller.capture(() {
        events.add(1);
        return held.future;
      });
      final second = controller.capture(() async {
        events.add(2);
        throw StateError('capture unavailable');
      });
      final third = controller.capture(() async {
        events.add(3);
        return Uint8List.fromList([1, 2]);
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, [1]);
      held.complete(Uint8List.fromList([3]));
      expect(await first, [3]);
      expect(await second, isNull);
      expect(await third, [1, 2]);
      expect(events, [1, 2, 3]);
    },
  );

  test(
    'disposal cancels active and queued captures without starting more',
    () async {
      final controller = _LifecycleController();
      final held = Completer<Uint8List?>();
      var starts = 0;
      final active = controller.capture(() {
        starts++;
        return held.future;
      });
      final queued = controller.capture(() async {
        starts++;
        return Uint8List(1);
      });
      await Future<void>.delayed(Duration.zero);
      controller.closeEvents();
      expect(await active.timeout(const Duration(seconds: 1)), isNull);
      expect(await queued.timeout(const Duration(seconds: 1)), isNull);
      expect(
        await controller.capture(() async {
          starts++;
          return Uint8List(1);
        }),
        isNull,
      );
      expect(starts, 1);
      // A late engine failure must be observed even after the caller was released.
      held.completeError(StateError('disposed native capture'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'renderer recovery cancels old captures and permits a fresh capture',
    () async {
      final controller = _LifecycleController();
      final held = Completer<Uint8List?>();
      var staleStarts = 0;
      final active = controller.capture(() => held.future);
      final queued = controller.capture(() async {
        staleStarts++;
        return Uint8List(1);
      });
      await Future<void>.delayed(Duration.zero);
      await controller.fail(
        const WebViewProcessFailure(
          kind: WebViewProcessFailureKind.rendererExited,
          recovery: WebViewProcessRecovery.reload,
        ),
      );
      expect(await active.timeout(const Duration(seconds: 1)), isNull);
      expect(await queued.timeout(const Duration(seconds: 1)), isNull);
      expect(staleStarts, 0);
      expect(await controller.capture(() async => Uint8List.fromList([9])), [
        9,
      ]);
      held.complete(Uint8List.fromList([1]));
    },
  );

  test('history snapshots are immutable and reject invalid indices', () {
    final input = [const WebViewHistoryItem(url: 'https://example.test/')];
    final history = WebViewNavigationHistory(items: input, currentIndex: 0);
    input.clear();
    expect(history.items, hasLength(1));
    expect(() => history.items.clear(), throwsUnsupportedError);
    expect(
      () => WebViewNavigationHistory(items: history.items),
      throwsArgumentError,
    );
    expect(
      () => WebViewNavigationHistory(currentIndex: 0),
      throwsArgumentError,
    );
    expect(WebViewNavigationHistory.fromMap({}).currentIndex, -1);
  });

  test('missing match counts stay unknown', () {
    final result = WebViewFindResult.fromMap({'matchFound': true});
    expect(result.matchFound, isTrue);
    expect(result.matchCount, isNull);
    expect(result.activeMatchIndex, isNull);
  });

  test('picker failures cancel and single-file requests stay single', () async {
    final params = WebViewFileSelectorParams();
    expect(params.isCaptureEnabled, isNull);
    expect(
      await invokeWebViewFileSelector(
        (_) async => ['', '/one', '/two'],
        params,
      ),
      ['/one'],
    );
    expect(
      await invokeWebViewFileSelector(
        (_) async => throw StateError('picker failed'),
        params,
      ),
      isEmpty,
    );
  });

  test('generic media policy survives platform parameter conversion', () {
    const source = PlatformWebViewControllerCreationParams(
      mediaPlaybackPolicy: WebViewMediaPlaybackPolicy.allowWithoutUserGesture,
    );
    const copy =
        PlatformWebViewControllerCreationParams.fromPlatformWebViewControllerCreationParams(
          source,
        );
    expect(
      copy.mediaPlaybackPolicy,
      WebViewMediaPlaybackPolicy.allowWithoutUserGesture,
    );
    expect(
      const PlatformWebViewControllerCreationParams().mediaPlaybackPolicy,
      isNull,
    );
  });

  test('cookie values are encoded without injecting header attributes', () {
    const cookie = WebViewCookie(
      name: 'session',
      value: 'v; Secure\r\nnext',
      domain: 'example.test',
    );
    expect(
      cookie.toSetCookieHeader(),
      'session=v%3B%20Secure%0D%0Anext; path=/; domain=example.test',
    );
  });

  test('cookie attributes serialize with a UTC expiry and explicit security', () {
    final cookie = WebViewCookie(
      name: 'session',
      value: 'a=b&c',
      domain: '.example.test',
      path: '/login',
      expires: DateTime.parse('2030-01-02T11:04:05+08:00'),
      isSecure: true,
      isHttpOnly: true,
      sameSite: WebViewCookieSameSite.none,
    );
    expect(
      cookie.toSetCookieHeader(),
      'session=a%3Db%26c; path=/login; domain=.example.test; expires=Wed, 02 Jan 2030 03:04:05 GMT; Secure; HttpOnly; SameSite=none',
    );
    expect(cookie.url.toString(), 'https://example.test/login');
  });

  test('false security flags and unknown metadata are preserved', () {
    const cookie = WebViewCookie(
      name: 'n',
      value: 'v',
      domain: 'example.test',
      isSecure: false,
      isHttpOnly: false,
    );
    expect(cookie.toSetCookieHeader(), 'n=v; path=/; domain=example.test');
    expect(cookie.expires, isNull);
    expect(cookie.isSession, isNull);
  });

  test(
    'cookie attributes cannot inject another attribute or downgrade SameSite=None',
    () {
      for (final cookie in [
        const WebViewCookie(
          name: 'a',
          value: 'v',
          domain: 'example.test; Secure',
        ),
        const WebViewCookie(
          name: 'a',
          value: 'v',
          domain: 'example.test',
          path: '/; HttpOnly',
        ),
        const WebViewCookie(
          name: 'a',
          value: 'v',
          domain: 'example.test',
          sameSite: WebViewCookieSameSite.none,
        ),
      ]) {
        expect(cookie.validate, throwsArgumentError);
      }
    },
  );
}

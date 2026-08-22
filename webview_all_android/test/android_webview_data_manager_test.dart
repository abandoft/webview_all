import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_android/src/android_webkit.g.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  test(
    'uses the complete AndroidX website-data operation when available',
    () async {
      final _FakeWebStorage storage = _FakeWebStorage(modernSupported: true);
      final _FakeCookieManager cookies = _FakeCookieManager();
      final _FakeWebView webView = _FakeWebView();
      final AndroidWebViewDataManager manager = AndroidWebViewDataManager(
        const PlatformWebViewDataManagerCreationParams(),
        webStorage: storage,
        cookieManager: cookies,
        webViewFactory: () => webView,
      );

      final WebViewDataClearingResult result = await manager
          .clearAllWebsiteData();

      expect(result.isComplete, isTrue);
      expect(storage.modernCalls, 1);
      expect(storage.legacyCalls, 0);
      expect(cookies.calls, 0);
      expect(webView.clearCalls, 0);
      expect(webView.destroyCalls, 0);
    },
  );

  test('reports the exact legacy Android capability boundary', () async {
    final _FakeWebStorage storage = _FakeWebStorage(modernSupported: false);
    final _FakeCookieManager cookies = _FakeCookieManager();
    final _FakeWebView webView = _FakeWebView();
    final AndroidWebViewDataManager manager = AndroidWebViewDataManager(
      const PlatformWebViewDataManagerCreationParams(),
      webStorage: storage,
      cookieManager: cookies,
      webViewFactory: () => webView,
    );

    final WebViewDataClearingResult result = await manager
        .clearAllWebsiteData();

    expect(result.clearedDataTypes, <WebViewDataType>{
      WebViewDataType.cookies,
      WebViewDataType.cache,
      WebViewDataType.localStorage,
      WebViewDataType.webSql,
    });
    expect(result.unsupportedDataTypes, <WebViewDataType>{
      WebViewDataType.sessionStorage,
      WebViewDataType.indexedDb,
      WebViewDataType.cacheStorage,
      WebViewDataType.serviceWorkers,
    });
    expect(result.failures, isEmpty);
    expect(storage.legacyCalls, 1);
    expect(cookies.calls, 1);
    expect(webView.clearCalls, 1);
    expect(webView.destroyCalls, 1);
  });

  test(
    'reports native failures instead of claiming successful clearing',
    () async {
      final AndroidWebViewDataManager manager = AndroidWebViewDataManager(
        const PlatformWebViewDataManagerCreationParams(),
        webStorage: _FakeWebStorage(modernFailure: StateError('first\nline')),
        cookieManager: _FakeCookieManager(),
        webViewFactory: _FakeWebView.new,
      );

      final WebViewDataClearingResult result = await manager
          .clearAllWebsiteData();

      expect(result.clearedDataTypes, isEmpty);
      expect(result.unsupportedDataTypes, isEmpty);
      expect(result.failures.keys, containsAll(WebViewDataType.values));
      expect(result.failures.values, everyElement(isNot(contains('\n'))));
    },
  );
}

// Mutable counters make native call assertions explicit.
// ignore: must_be_immutable
class _FakeWebStorage extends WebStorage {
  _FakeWebStorage({this.modernSupported = false, this.modernFailure})
    : super.pigeon_detached();

  final bool modernSupported;
  final Object? modernFailure;
  int modernCalls = 0;
  int legacyCalls = 0;

  @override
  Future<bool> deleteBrowsingData() async {
    modernCalls += 1;
    if (modernFailure case final Object error) {
      throw error;
    }
    return modernSupported;
  }

  @override
  Future<void> deleteAllData() async {
    legacyCalls += 1;
  }
}

// Mutable counters make native call assertions explicit.
// ignore: must_be_immutable
class _FakeCookieManager extends CookieManager {
  _FakeCookieManager() : super.pigeon_detached();

  int calls = 0;

  @override
  Future<bool> removeAllCookies() async {
    calls += 1;
    return true;
  }
}

// Mutable counters make native call assertions explicit.
// ignore: must_be_immutable
class _FakeWebView extends WebView {
  _FakeWebView() : super.pigeon_detached();

  int clearCalls = 0;
  int destroyCalls = 0;

  @override
  Future<void> clearCache(bool includeDiskFiles) async {
    expect(includeDiskFiles, isTrue);
    clearCalls += 1;
  }

  @override
  Future<void> destroy() async {
    destroyCalls += 1;
  }
}

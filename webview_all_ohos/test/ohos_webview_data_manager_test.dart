import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';
import 'package:webview_all_ohos/src/ohos_website_data_store.dart';
import 'package:webview_all_ohos/src/ohos_webview_data_manager.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

// ignore: must_be_immutable
class _Cookies extends CookieManager {
  _Cookies()
    : super.detached(
        instanceManager: InstanceManager(onWeakReferenceRemoved: (_) {}),
      );

  Object? failure;
  bool hadCookies = true;
  int calls = 0;

  @override
  Future<bool> removeAllCookies() async {
    calls++;
    if (failure case final Object error) {
      throw error;
    }
    return hadCookies;
  }
}

// ignore: must_be_immutable
class _Storage extends WebStorage {
  _Storage()
    : super.detached(
        instanceManager: InstanceManager(onWeakReferenceRemoved: (_) {}),
      );

  Object? failure;
  int calls = 0;

  @override
  Future<void> deleteAllData() async {
    calls++;
    if (failure case final Object error) {
      throw error;
    }
  }
}

class _DataStore extends OhosWebsiteDataStore {
  Object? failure;
  bool? lastIncludeDiskFiles;

  @override
  Future<void> clearAllCache({required bool includeDiskFiles}) async {
    lastIncludeDiskFiles = includeDiskFiles;
    if (failure case final Object error) {
      throw error;
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  OhosWebViewDataManager createManager(
    _Cookies cookies,
    _Storage storage,
    _DataStore dataStore,
  ) {
    return OhosWebViewDataManager(
      const PlatformWebViewDataManagerCreationParams(),
      cookieManager: cookies,
      webStorage: storage,
      websiteDataStore: dataStore,
    );
  }

  test('clears global HTTP cache without a WebView instance', () async {
    const MethodChannel channel = MethodChannel(
      'com.abandoft.webview_all_ohos/host_api',
    );
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await OhosWebsiteDataStore().clearAllCache(includeDiskFiles: true);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'WebView.clearAllCache');
    expect(calls.single.arguments, <String, Object?>{'includeDiskFiles': true});
  });

  test('reports exactly the categories covered by native stores', () async {
    final _Cookies cookies = _Cookies()..hadCookies = false;
    final _Storage storage = _Storage();
    final _DataStore dataStore = _DataStore();

    final WebViewDataClearingResult result = await createManager(
      cookies,
      storage,
      dataStore,
    ).clearAllWebsiteData();

    expect(cookies.calls, 1);
    expect(storage.calls, 1);
    expect(dataStore.lastIncludeDiskFiles, isTrue);
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
    expect(result.isComplete, isFalse);
  });

  test('cache failures preserve other clearing results', () async {
    final _Cookies cookies = _Cookies();
    final _Storage storage = _Storage();
    final _DataStore dataStore = _DataStore()
      ..failure = PlatformException(
        code: 'cache',
        message: 'native cache\nfailed\r\nretry',
      );

    final WebViewDataClearingResult result = await createManager(
      cookies,
      storage,
      dataStore,
    ).clearAllWebsiteData();

    expect(result.clearedDataTypes, <WebViewDataType>{
      WebViewDataType.cookies,
      WebViewDataType.localStorage,
      WebViewDataType.webSql,
    });
    expect(result.failures.keys, <WebViewDataType>[WebViewDataType.cache]);
    expect(
      result.failures[WebViewDataType.cache],
      contains('native cache failed retry'),
    );
    expect(result.failures[WebViewDataType.cache], isNot(contains('\n')));
    expect(result.failures[WebViewDataType.cache], isNot(contains('\r')));
    expect(
      result.unsupportedDataTypes,
      contains(WebViewDataType.sessionStorage),
    );
  });

  test(
    'cookie and storage failures still attempt global cache clearing',
    () async {
      final _Cookies cookies = _Cookies()
        ..failure = StateError('cookies failed');
      final _Storage storage = _Storage()
        ..failure = StateError('storage failed');
      final _DataStore dataStore = _DataStore();

      final WebViewDataClearingResult result = await createManager(
        cookies,
        storage,
        dataStore,
      ).clearAllWebsiteData();

      expect(dataStore.lastIncludeDiskFiles, isTrue);
      expect(result.clearedDataTypes, <WebViewDataType>{WebViewDataType.cache});
      expect(result.failures.keys.toSet(), <WebViewDataType>{
        WebViewDataType.cookies,
        WebViewDataType.localStorage,
        WebViewDataType.webSql,
      });
      expect(
        result.unsupportedDataTypes,
        contains(WebViewDataType.sessionStorage),
      );
    },
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_wkwebview/src/common/web_kit.g.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  test('clears every mapped WKWebsiteDataStore category', () async {
    final _FakeWebsiteDataStore dataStore = _FakeWebsiteDataStore();
    final WebKitWebViewDataManager manager = WebKitWebViewDataManager(
      WebKitWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
        const PlatformWebViewDataManagerCreationParams(),
        websiteDataStore: dataStore,
      ),
    );

    final WebViewDataClearingResult result = await manager
        .clearAllWebsiteData();

    expect(result.isComplete, isTrue);
    expect(dataStore.modificationTime, 0);
    expect(dataStore.dataTypes, <WebsiteDataType>{
      WebsiteDataType.cookies,
      WebsiteDataType.memoryCache,
      WebsiteDataType.diskCache,
      WebsiteDataType.offlineWebApplicationCache,
      WebsiteDataType.localStorage,
      WebsiteDataType.sessionStorage,
      WebsiteDataType.webSQLDatabases,
      WebsiteDataType.indexedDBDatabases,
      WebsiteDataType.fetchCache,
      WebsiteDataType.serviceWorkerRegistrations,
    });
  });

  test('reports a data-store failure for every requested category', () async {
    final _FakeWebsiteDataStore dataStore = _FakeWebsiteDataStore(
      failure: StateError('first\nline'),
    );
    final WebKitWebViewDataManager manager = WebKitWebViewDataManager(
      WebKitWebViewDataManagerCreationParams.fromPlatformWebViewDataManagerCreationParams(
        const PlatformWebViewDataManagerCreationParams(),
        websiteDataStore: dataStore,
      ),
    );

    final WebViewDataClearingResult result = await manager
        .clearAllWebsiteData();

    expect(result.clearedDataTypes, isEmpty);
    expect(result.unsupportedDataTypes, isEmpty);
    expect(result.failures.keys, containsAll(WebViewDataType.values));
    expect(result.failures.values, everyElement(isNot(contains('\n'))));
  });
}

// Mutable fields make native call assertions explicit.
// ignore: must_be_immutable
class _FakeWebsiteDataStore extends WKWebsiteDataStore {
  _FakeWebsiteDataStore({this.failure}) : super.pigeon_detached();

  final Object? failure;
  Set<WebsiteDataType>? dataTypes;
  double? modificationTime;

  @override
  Future<bool> removeDataOfTypes(
    List<WebsiteDataType> dataTypes,
    double modificationTimeInSecondsSinceEpoch,
  ) async {
    this.dataTypes = dataTypes.toSet();
    modificationTime = modificationTimeInSecondsSinceEpoch;
    if (failure case final Object error) {
      throw error;
    }
    return true;
  }
}

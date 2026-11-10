import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'webview_platform_test.mocks.dart';

void main() {
  setUp(() {
    WebViewPlatform.instance = MockWebViewPlatformWithMixin();
  });

  test('factory returns a verified platform data manager', () {
    const PlatformWebViewDataManagerCreationParams params =
        PlatformWebViewDataManagerCreationParams();
    final _TestPlatformWebViewDataManager manager =
        _TestPlatformWebViewDataManager(params);
    when(
      (WebViewPlatform.instance! as MockWebViewPlatform)
          .createPlatformWebViewDataManager(params),
    ).thenReturn(manager);

    expect(PlatformWebViewDataManager(params), same(manager));
  });

  test('default clearing result reports all categories unsupported', () async {
    final _TestPlatformWebViewDataManager manager =
        _TestPlatformWebViewDataManager(
          const PlatformWebViewDataManagerCreationParams(),
        );

    final WebViewDataClearingResult result = await manager
        .clearAllWebsiteData();

    expect(result.clearedDataTypes, isEmpty);
    expect(result.unsupportedDataTypes, WebViewDataType.values.toSet());
    expect(result.isComplete, isFalse);
  });

  test('selective clearing classifies only requested categories', () async {
    final manager = _TestPlatformWebViewDataManager(
      const PlatformWebViewDataManagerCreationParams(),
    );
    final result = await manager.clearWebsiteData(
      dataTypes: {WebViewDataType.cookies},
    );
    expect(result.requestedDataTypes, {WebViewDataType.cookies});
    expect(result.unsupportedDataTypes, {WebViewDataType.cookies});
    expect((await manager.clearWebsiteData(dataTypes: {})).isComplete, isTrue);
    expect(
      () => WebViewDataClearingResult(
        requestedDataTypes: {WebViewDataType.cookies},
        clearedDataTypes: {WebViewDataType.cookies, WebViewDataType.cache},
      ),
      throwsArgumentError,
    );
    expect(
      () => WebViewDataClearingResult(
        requestedDataTypes: {WebViewDataType.cookies},
      ),
      throwsArgumentError,
    );
    final complete = WebViewDataClearingResult(
      requestedDataTypes: {WebViewDataType.cookies},
      clearedDataTypes: {WebViewDataType.cookies},
    );
    expect(complete.isComplete, isTrue);
    expect(() => complete.requestedDataTypes.clear(), throwsUnsupportedError);
  });

  test('atomic clearing groups never expand the requested scope', () {
    final group = {WebViewDataType.localStorage, WebViewDataType.indexedDb};
    final caps = WebViewDataCapabilities(
      clearingGroups: [
        {WebViewDataType.cookies},
        group,
      ],
    );
    group.clear();
    expect(
      caps.clearableTypes({
        WebViewDataType.cookies,
        WebViewDataType.localStorage,
      }),
      {WebViewDataType.cookies},
    );
    expect(caps.canClear({WebViewDataType.localStorage}), isFalse);
    expect(
      caps.canClear({WebViewDataType.localStorage, WebViewDataType.indexedDb}),
      isTrue,
    );
    expect(() => caps.clearingGroups.last.clear(), throwsUnsupportedError);
  });
}

class _TestPlatformWebViewDataManager extends PlatformWebViewDataManager {
  _TestPlatformWebViewDataManager(super.params) : super.implementation();
}

class MockWebViewPlatformWithMixin extends MockWebViewPlatform
    with MockPlatformInterfaceMixin {}

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
}

class _TestPlatformWebViewDataManager extends PlatformWebViewDataManager {
  _TestPlatformWebViewDataManager(super.params) : super.implementation();
}

class MockWebViewPlatformWithMixin extends MockWebViewPlatform
    with MockPlatformInterfaceMixin {}

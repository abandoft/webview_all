import 'package:flutter/services.dart';

/// Global ArkWeb data operations that do not require an attached WebView.
class OhosWebsiteDataStore {
  OhosWebsiteDataStore({BinaryMessenger? binaryMessenger})
    : _channel = MethodChannel(
        'com.abandoft.webview_all_ohos/host_api',
        const StandardMethodCodec(),
        binaryMessenger,
      );

  final MethodChannel _channel;

  Future<void> clearAllCache({required bool includeDiskFiles}) {
    return _channel.invokeMethod<void>(
      'WebView.clearAllCache',
      <String, Object?>{'includeDiskFiles': includeDiskFiles},
    );
  }
}

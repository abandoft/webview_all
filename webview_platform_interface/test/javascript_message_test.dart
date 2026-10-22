import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  test('a message names no sender unless the platform reports one', () {
    const message = JavaScriptMessage(message: 'hi');
    expect(message.sourceUrl, isNull);
    expect(message.isMainFrame, isNull);
  });

  test('a message carries the sending document a platform reports', () {
    const message = JavaScriptMessage(
      message: 'hi',
      sourceUrl: 'https://a.example/page',
      isMainFrame: true,
    );
    expect(message.sourceUrl, 'https://a.example/page');
    expect(message.isMainFrame, isTrue);
  });
}

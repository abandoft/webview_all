import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  test('a message names no sender unless the platform reports one', () {
    const message = JavaScriptMessage(message: 'hi');
    expect(message.sourceUrl, isNull);
    expect(message.sourceOrigin, isNull);
    expect(message.isMainFrame, isNull);
  });

  test('a message carries the sending document a platform reports', () {
    const message = JavaScriptMessage(
      message: 'hi',
      sourceUrl: 'https://a.example/page',
      sourceOrigin: 'https://a.example',
      isMainFrame: true,
    );
    expect(message.sourceUrl, 'https://a.example/page');
    expect(message.sourceOrigin, 'https://a.example');
    expect(message.isMainFrame, isTrue);
  });

  test('an opaque security origin differs from an unknown origin', () {
    const message = JavaScriptMessage(message: 'hi', sourceOrigin: 'null');
    expect(message.sourceOrigin, 'null');
    expect(message.sourceUrl, isNull);
    expect(message.isMainFrame, isNull);
  });
}

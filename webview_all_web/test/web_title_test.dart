import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:webview_all_web/webview_all_web.dart';

void main() {
  for (final sandbox in ['allow-scripts allow-same-origin', 'allow-scripts']) {
    test(
      'title delegates can be replaced before mounting ($sandbox)',
      () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: sandbox,
        );
        final controller = WebWebViewController(params);
        addTearDown(controller.closeWebViewSession);
        await controller.loadHtmlString('<title>Mounted title</title>');

        final first = <String>[];
        final initial = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        await initial.setOnTitleChange(first.add);
        await controller
            .setPlatformNavigationDelegate(initial)
            .timeout(const Duration(seconds: 1));

        final second = <String>[];
        final replacement = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        await replacement.setOnTitleChange(second.add);
        await controller
            .setPlatformNavigationDelegate(replacement)
            .timeout(const Duration(seconds: 1));
        expect(first, isEmpty);
        expect(second, isEmpty);

        web.document.body!.append(params.iFrame);
        await _until(() => second.contains('Mounted title'));
        expect(first, isEmpty);
      },
    );

    test(
      'late title delegates receive an empty current title ($sandbox)',
      () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: sandbox,
        );
        final controller = WebWebViewController(params);
        addTearDown(controller.closeWebViewSession);
        web.document.body!.append(params.iFrame);
        final loaded = params.iFrame.onLoad.first;
        await controller.loadHtmlString('<!doctype html><body>No title</body>');
        await loaded;
        // Complete the isolated handshake before registering the late delegate.
        await controller.getTitle();

        final titles = <String>[];
        final delegate = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        await delegate.setOnTitleChange(titles.add);
        await controller.setPlatformNavigationDelegate(delegate);
        await _until(() => titles.contains(''));
      },
    );

    test(
      'title observers survive rewrites, delegate replacement and close ($sandbox)',
      () async {
        final params = WebWebViewControllerCreationParams(
          iFrameSandbox: sandbox,
        );
        final controller = WebWebViewController(params);
        addTearDown(() async {
          params.iFrame.remove();
          await controller.closeWebViewSession();
        });
        web.document.body!.append(params.iFrame);
        final loaded = params.iFrame.onLoad.first;
        await controller.loadHtmlString(
          '<!doctype html><title>Initial title</title>',
        );
        await loaded;
        final first = <String>[];
        final delegate = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        await delegate.setOnTitleChange(first.add);
        await controller.setPlatformNavigationDelegate(delegate);
        await _until(() => first.contains('Initial title'));
        await controller.runJavaScript("document.title='Changed';");
        await _until(() => first.contains('Changed'));
        await controller.runJavaScript("document.title='';");
        await _until(() => first.contains(''));
        await controller.runJavaScript(
          "document.open();document.write('<title>Rewritten</title>');document.close();",
        );
        await _until(() => first.contains('Rewritten'));
        final second = <String>[];
        final replacement = WebNavigationDelegate(
          const WebNavigationDelegateCreationParams(),
        );
        await replacement.setOnTitleChange(second.add);
        await controller.setPlatformNavigationDelegate(replacement);
        await _until(() => second.contains('Rewritten'));
        final count = first.length;
        await controller.runJavaScript("document.title='Replacement';");
        await _until(() => second.contains('Replacement'));
        expect(first.length, count);

        web.window.postMessage(
          {'type': 'webview_all_title', 'title': 'Forged'}.jsify(),
          '*'.toJS,
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(second, isNot(contains('Forged')));
        params.iFrame.remove();
        await controller.closeWebViewSession();
        await controller.closeWebViewSession();
        expect(params.iFrame.isConnected, isFalse);
      },
    );
  }
}

Future<void> _until(bool Function() predicate) async {
  for (var i = 0; i < 100 && !predicate(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(predicate(), isTrue);
}

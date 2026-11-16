import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:platform_example/form_request_script.dart';
import 'package:webview_all/webview_all.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('form script preserves XHR transport and encodes Chinese titles', (
    tester,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    server.listen((request) async {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(
          '''<!doctype html><meta charset="utf-8"><title>ready</title>
<script>
globalThis.firstFormRequest = new Promise(resolve => {
  const xhr = new XMLHttpRequest();
  xhr.open('POST', '/submit');
  xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
  xhr.onload = () => resolve(JSON.parse(xhr.responseText));
  xhr.onerror = () => resolve({error: 'Initial XHR failed'});
  xhr.send('title=--&note=first');
});
</script>''',
        );
      } else {
        if (request.uri.path == '/submit' || request.uri.path == '/untouched') {
          requests++;
        }
        final body = await utf8.decoder.bind(request).join();
        final type = request.headers.contentType?.mimeType;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'path': request.uri.path,
            'body': body,
            'type': type,
            'form': type == 'application/x-www-form-urlencoded'
                ? Uri.splitQueryString(body)
                : null,
            'header': request.headers.value('x-fixture'),
          }),
        );
      }
      await request.response.close();
    });
    final session = (await WebViewSession.create(
      mode: WebViewSessionMode.shared,
    ))!;
    final view = session.controller;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await server.close(force: true);
    });
    if (!await view.isUserScriptInjectionSupported(
      WebViewUserScriptInjectionTime.documentStart,
    )) {
      markTestSkipped(
        'Native document-start scripts are unavailable; the form example is not installed.',
      );
      return;
    }
    await view.setJavaScriptMode(JavaScriptMode.unrestricted);
    Completer<Map<String, dynamic>>? pending;
    await view.addJavaScriptChannel(
      'FormResults',
      onMessageReceived: (message) {
        if (pending case final value? when !value.isCompleted) {
          value.complete(jsonDecode(message.message) as Map<String, dynamic>);
        }
      },
    );
    final origin = Uri.parse('http://127.0.0.1:${server.port}');
    const title = '中文标题 & = + / % 🐈';
    WebViewUserScript script(String value, {Uri? pageOrigin}) =>
        formRequestFieldsScript(
          pageOrigin: pageOrigin ?? origin,
          endpoint: origin.resolve('/submit'),
          fields: {'title': value, '__proto__': '表单字段 + &'},
        );
    await view.addUserScript(script(title));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: WebViewWidget(controller: view),
      ),
    );
    await tester.pumpAndSettle();
    final loaded = Completer<void>();
    await view.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await view.loadRequest(origin);
    await loaded.future.timeout(const Duration(seconds: 25));
    Future<Map<String, dynamic>> run(String body) async {
      pending = Completer<Map<String, dynamic>>();
      await view.runJavaScript('''
void (async () => {
  try { $body }
  catch (error) { FormResults.postMessage(JSON.stringify({error: String(error)})); }
})();
''');
      final result = await pending!.future.timeout(const Duration(seconds: 30));
      expect(result, isNot(contains('error')));
      return result;
    }

    final batch = await run('''
      const early = await globalThis.firstFormRequest;
      if (early.error) throw new Error(early.error);
      globalThis.requestForm = (url, body, type, existing) => new Promise((resolve, reject) => {
        const xhr = existing || new XMLHttpRequest();
        xhr.open('POST', url);
        xhr.setRequestHeader('X-Fixture', 'retained');
        if (type) xhr.setRequestHeader('Content-Type', type);
        xhr.onload = () => resolve(JSON.parse(xhr.responseText));
        xhr.onerror = () => reject(new Error('XHR failed'));
        xhr.send(body);
      });
      const encoded = new URLSearchParams({title: '--', note: '保留 & +'}).toString();
      const text = await requestForm('/submit?source=note', encoded, 'application/x-www-form-urlencoded; charset=UTF-8');
      const params = await requestForm('/submit', new URLSearchParams({title: '--'}));
      const urlObject = await requestForm(new URL('/submit', location.href), new URLSearchParams({title: '--'}));
      const untouched = await requestForm('/untouched', encoded, 'application/x-www-form-urlencoded');
      const json = await requestForm('/submit', '{"title":"--"}', 'application/json');
      const form = new FormData(); form.set('title', '--');
      const multipart = await requestForm('/submit', form);
      const xhr = new XMLHttpRequest();
      const reusedTarget = await requestForm('/submit', encoded, 'application/x-www-form-urlencoded', xhr);
      const reusedOther = await requestForm('/untouched', encoded, 'application/x-www-form-urlencoded', xhr);
      const sync = new XMLHttpRequest();
      sync.open('POST', '/submit', false);
      sync.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
      sync.send(encoded);
      FormResults.postMessage(JSON.stringify({early, text, params, urlObject, untouched, json, multipart,
        reusedTarget, reusedOther, sync: JSON.parse(sync.responseText)}));
''');
    for (final key in [
      'early',
      'text',
      'params',
      'urlObject',
      'reusedTarget',
      'sync',
    ]) {
      expect((batch[key] as Map)['form']['title'], title);
      expect((batch[key] as Map)['form']['__proto__'], '表单字段 + &');
    }
    expect((batch['text'] as Map)['form']['note'], '保留 & +');
    expect((batch['text'] as Map)['header'], 'retained');
    for (final key in ['untouched', 'reusedOther']) {
      expect((batch[key] as Map)['form']['title'], '--');
    }
    expect((batch['json'] as Map)['body'], '{"title":"--"}');
    expect((batch['multipart'] as Map)['type'], 'multipart/form-data');
    expect((batch['multipart'] as Map)['body'], isNot(contains('中文标题')));
    // A rule for an unrelated page must not change the existing configuration.
    await view.runJavaScript(
      script(
        'wrong origin',
        pageOrigin: Uri.parse('https://example.com'),
      ).source,
    );
    await view.runJavaScript(script('更新后的标题 + &').source);
    final updated = await run('''
      const value = await requestForm('/submit', 'title=--', 'application/x-www-form-urlencoded');
      FormResults.postMessage(JSON.stringify(value));
''');
    expect((updated['form'] as Map)['title'], '更新后的标题 + &');
    await view.runJavaScript(
      formRequestFieldsScript(
        pageOrigin: origin,
        endpoint: origin.resolve('/submit'),
        fields: const {},
      ).source,
    );
    const originalBody = 'title=--&note=%e4%b8%ad%20%e6%96%87&dup=1&dup=2';
    final disabled = await run('''
      const value = await requestForm('/submit', ${jsonEncode(originalBody)}, 'application/x-www-form-urlencoded');
      FormResults.postMessage(JSON.stringify(value));
''');
    expect(disabled['body'], originalBody);
    expect(requests, 12);
  });
}

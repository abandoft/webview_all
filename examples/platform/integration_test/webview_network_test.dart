import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';

Future<void> _until(WidgetTester tester, Future<bool> Function() check) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (DateTime.now().isBefore(deadline)) {
    try {
      if (await check()) return;
    } catch (_) {}
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('The native network operation did not complete.');
}

Future<String> _read(WebViewController view, String name) async {
  final result = (await view.runJavaScriptReturningResult(
    'String(window.$name)',
  )).toString();
  return result.startsWith('"') ? jsonDecode(result) as String : result;
}

Future<String> _fetch(
  WidgetTester tester,
  WebViewController view,
  String expression,
) async {
  await view.runJavaScript(
    'window.fixtureResult="pending"; ($expression).then(v=>window.fixtureResult=String(v)).catch(e=>window.fixtureResult="error:"+e)',
  );
  await _until(
    tester,
    () async => await _read(view, 'fixtureResult') != 'pending',
  );
  return _read(view, 'fixtureResult');
}

WebViewResourceResponse _text(String value, {String mime = 'text/plain'}) =>
    WebViewResourceResponse.bytes(
      Uint8List.fromList(utf8.encode(value)),
      mimeType: mime,
      headers: {'access-control-allow-origin': '*', 'x-provider': 'dart'},
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native content rules, request decisions and custom scheme lifetimes', (
    tester,
  ) async {
    // Declarations precede capability queries and the first native environment.
    await WebViewSession.getCapabilities();
    final view = WebViewController.fromPlatformCreationParams(
      const PlatformWebViewControllerCreationParams(
        customSchemes: ['appfixture'],
      ),
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final hits = <String, int>{};
    WebViewCookieManager? cookies;
    addTearDown(() async {
      try {
        await WebViewCookieManager().deleteCookie(
          name: 'network_fixture',
          domain: '127.0.0.1',
        );
      } catch (_) {}
      await tester.pumpWidget(const SizedBox.shrink());
      await view.platform.closeWebViewSession();
      await server.close(force: true);
    });
    unawaited(
      server.forEach((request) async {
        hits.update(request.uri.path, (v) => v + 1, ifAbsent: () => 1);
        request.response.headers.set('cache-control', 'no-store');
        if (request.uri.path == '/page') {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<!doctype html><html><head><title>Network fixture</title></head><body>Network fixture</body></html>',
          );
        } else if (request.uri.path == '/blocked-script.js') {
          request.response.headers.contentType = ContentType(
            'application',
            'javascript',
          );
          request.response.write('window.ruleSignal="executed";');
        } else {
          final body = await utf8.decoder.bind(request).join();
          final cookie = request.cookies
              .where((v) => v.name == 'network_fixture')
              .map((v) => v.value)
              .join();
          request.response.write(
            '${request.method}:$body:${request.headers.value('x-fixture') ?? ''}:$cookie',
          );
        }
        await request.response.close();
      }),
    );
    final base = 'http://127.0.0.1:${server.port}';
    await view.setJavaScriptMode(JavaScriptMode.unrestricted);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WebViewWidget(controller: view)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await view.loadRequest(Uri.parse('$base/page'));
    await _until(
      tester,
      () async => await view.getTitle() == 'Network fixture',
    );
    final caps = await view.getNetworkCapabilities();
    debugPrint(
      'Network capabilities: rules=${caps.contentRules}, HTTP=${caps.httpInterception}, schemes=${caps.customSchemes}, streaming=${caps.streamingResponses}',
    );
    if (caps.contentRules) {
      final types =
          caps.resourceTypes.contains(WebViewNetworkResourceType.script)
          ? {WebViewNetworkResourceType.script}
          : <WebViewNetworkResourceType>{};
      final block = WebViewContentRule(
        urlPattern: '$base/blocked-script.js*',
        resourceTypes: types,
      );
      debugPrint("Installing native content rules");
      expect(await view.setContentRules([block]), isTrue);
      debugPrint("Native content rules installed");
      Future<String> script(String query) async {
        await view.runJavaScript(
          'window.ruleSignal="pending";var s=document.createElement("script");s.src=${jsonEncode('$base/blocked-script.js?$query')};s.onerror=()=>window.ruleSignal="blocked";document.body.append(s);',
        );
        await _until(
          tester,
          () async => await _read(view, 'ruleSignal') != 'pending',
        );
        return _read(view, 'ruleSignal');
      }

      expect(await script('blocked'), 'blocked');
      expect(hits['/blocked-script.js'] ?? 0, 0);
      expect(
        await view.setContentRules([
          block,
          WebViewContentRule(
            urlPattern: '$base/blocked-script.js?allow',
            action: WebViewContentRuleAction.allow,
            resourceTypes: types,
          ),
        ]),
        isTrue,
      );
      expect(await script('allow'), 'executed');
      expect(await script('still-blocked'), 'blocked');
      expect(await view.setContentRules([]), isTrue);
      expect(await script('cleared'), 'executed');
    }
    debugPrint("Content rule tests completed");
    if (caps.httpInterception) {
      cookies = WebViewCookieManager.fromPlatform(
        view.platform.createSessionCookieManager(),
      );
      await cookies.setCookie(
        const WebViewCookie(
          name: 'network_fixture',
          value: 'fixture',
          domain: '127.0.0.1',
        ),
      );
      var calls = 0;
      expect(
        await view.setRequestDelegate(
          WebViewRequestDelegate(
            urlPatterns: ['$base/network/*'],
            onRequest: (request) {
              calls++;
              if (request.uri.path.endsWith('/allow')) {
                expectSync(request.method, 'POST');
                expectSync(request.headers['x-fixture'], 'yes');
                if (request.bodyAvailable) {
                  expectSync(utf8.decode(request.body!), 'payload');
                }
                return const WebViewRequestDecision.allow();
              }
              if (request.uri.path.endsWith('/respond')) {
                return WebViewRequestDecision.respond(_text('from Dart'));
              }
              return const WebViewRequestDecision.block();
            },
          ),
        ),
        isTrue,
      );
      expect(
        await _fetch(
          tester,
          view,
          'fetch("$base/network/allow",{method:"POST",body:"payload",headers:{"x-fixture":"yes"},credentials:"include"}).then(r=>r.text())',
        ),
        'POST:payload:yes:fixture',
      );
      expect(hits['/network/allow'], 1);
      expect(
        await _fetch(
          tester,
          view,
          'fetch("$base/network/respond").then(async r=>r.status+":"+await r.text()+":"+r.headers.get("x-provider"))',
        ),
        '200:from Dart:dart',
      );
      expect(hits['/network/respond'] ?? 0, 0);
      expect(
        await _fetch(
          tester,
          view,
          'fetch("$base/network/block").then(r=>r.status)',
        ),
        '403',
      );
      expect(hits['/network/block'] ?? 0, 0);
      expect(calls, 3);
      final pending = Completer<WebViewRequestDecision>();
      var started = false;
      await view.setRequestDelegate(
        WebViewRequestDelegate(
          urlPatterns: ['$base/network/*'],
          onRequest: (_) {
            started = true;
            return pending.future;
          },
        ),
      );
      await view.runJavaScript(
        'window.pendingStatus="pending";fetch("$base/network/pending").then(r=>window.pendingStatus=String(r.status)).catch(()=>window.pendingStatus="failed")',
      );
      await _until(tester, () async => started);
      expect(await view.setRequestDelegate(null), isTrue);
      await _until(
        tester,
        () async => await _read(view, 'pendingStatus') != 'pending',
      );
      pending.complete(const WebViewRequestDecision.allow());
      await tester.pump(const Duration(milliseconds: 300));
      expect(hits['/network/pending'] ?? 0, 0);
    }
    debugPrint("HTTP delegate tests completed");
    if (caps.customSchemes) {
      var customCalls = 0;
      expect(
        await view.setCustomSchemeDelegate(
          WebViewResourceDelegate(
            onRequest: (request) {
              customCalls++;
              if (request.uri.path == '/index.html') {
                return _text(
                  '<!doctype html><html><head><title>Custom fixture</title></head><body>Custom fixture</body></html>',
                  mime: 'text/html',
                );
              }
              if (request.uri.path == '/echo') {
                return _text(
                  request.bodyAvailable
                      ? 'available:${utf8.decode(request.body!)}'
                      : 'unavailable',
                );
              }
              return _text('custom response');
            },
          ),
        ),
        isTrue,
      );
      debugPrint('Custom delegate configured');
      await view.loadRequest(Uri.parse('appfixture://assets/index.html'));
      debugPrint('Custom navigation requested');
      await _until(
        tester,
        () async => await view.getTitle() == 'Custom fixture',
      );
      debugPrint('Custom document loaded');
      if (caps.customSchemeFetch) {
        expect(
          await _fetch(
            tester,
            view,
            'fetch("appfixture://assets/data").then(r=>r.text())',
          ),
          'custom response',
        );
        final post = await _fetch(
          tester,
          view,
          'fetch("appfixture://assets/echo",{method:"POST",body:"custom payload"}).then(r=>r.text())',
        );
        expect(post, anyOf('available:custom payload', 'unavailable'));
        debugPrint('Custom request body result: $post');
      } else {
        final callsBefore = customCalls;
        expect(
          await _fetch(
            tester,
            view,
            'fetch("appfixture://assets/data").then(r=>r.text())',
          ),
          startsWith('error:'),
        );
        expect(
          customCalls,
          callsBefore,
          reason:
              'Chromium rejects unsupported fetch schemes before the native handler.',
        );
      }
      await view.setResourceDelegate(
        WebViewResourceDelegate(onRequest: (_) => _text('owned resource')),
      );
      final resource = view.getResourceUri('/owned')!;
      expect(
        await _fetch(
          tester,
          view,
          'fetch(${jsonEncode(resource.toString())}).then(r=>r.text())',
        ),
        'owned resource',
      );
      final before = customCalls;
      expect(await view.setCustomSchemeDelegate(null), isTrue);
      final removed = await _fetch(
        tester,
        view,
        'fetch("appfixture://assets/removed").then(r=>String(r.status))',
      );
      expect(
        removed.startsWith('error:') || (int.tryParse(removed) ?? 0) >= 400,
        isTrue,
      );
      expect(customCalls, before);
      expect(
        await _fetch(
          tester,
          view,
          'fetch(${jsonEncode(resource.toString())}).then(r=>r.text())',
        ),
        'owned resource',
      );
      if (caps.streamingResponses && caps.customSchemeFetch) {
        final stream = StreamController<List<int>>();
        var cancelled = 0;
        stream.onCancel = () {
          cancelled++;
        };
        await view.setCustomSchemeDelegate(
          WebViewResourceDelegate(
            onRequest: (_) {
              scheduleMicrotask(
                () => stream.add(utf8.encode('streamed'.padRight(65536, 'x'))),
              );
              return WebViewResourceResponse.stream(
                stream.stream,
                mimeType: 'text/plain',
                headers: {'access-control-allow-origin': '*'},
              );
            },
          ),
        );
        await view.runJavaScript(
          'window.streamResult="pending";fetch("appfixture://assets/stream").then(r=>r.body.getReader().read()).then(v=>window.streamResult=new TextDecoder().decode(v.value)).catch(e=>window.streamResult="error:"+e)',
        );
        await _until(
          tester,
          () async => await _read(view, 'streamResult') != 'pending',
        );
        expect(await _read(view, 'streamResult'), startsWith('streamed'));
        await tester.pumpWidget(const SizedBox.shrink());
        await view.platform.closeWebViewSession();
        await _until(tester, () async => cancelled == 1);
        await stream.close();
      }
    }
  });
}

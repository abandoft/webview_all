import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/channels/api_implementations.dart';
import 'package:webview_all_ohos/src/channels/callback_dispatcher.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart' as native;
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const host = MethodChannel('com.abandoft.webview_all_ohos/host_api');
  const callback = 'com.abandoft.webview_all_ohos/callback_api';
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, (call) async {
          calls.add(call);
          if (call.method == 'CookieManager.getCookies') return 'private=value';
          if (call.method == 'CookieManager.removeAllCookies') return true;
          return null;
        });
  });
  tearDown(() {
    const MethodChannel(callback).setMethodCallHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(host, null);
  });

  test(
    'private data operations select private stores and leave global cache untouched',
    () async {
      final cookies = OhosWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
        incognito: true,
      );
      await cookies.setCookie(
        const WebViewCookie(
          name: 'private',
          value: 'value',
          domain: 'https://example.test',
        ),
      );
      expect(
        (await cookies.getCookies(
          Uri.parse('https://example.test'),
        )).single.value,
        'value',
      );
      expect(await cookies.clearCookies(), isTrue);
      final data = OhosWebViewDataManager(
        const PlatformWebViewDataManagerCreationParams(),
        incognito: true,
      );
      final result = await data.clearAllWebsiteData();
      expect(result.failures, isEmpty);
      expect(result.unsupportedDataTypes, contains(WebViewDataType.cache));
      final mutations = calls.where(
        (call) =>
            call.method.startsWith('CookieManager.') &&
                call.method != 'CookieManager.attachInstance' ||
            call.method == 'WebStorage.deleteAllData',
      );
      for (final call in mutations) {
        expect(
          (call.arguments as Map)['incognito'],
          isTrue,
          reason: call.method,
        );
      }
      expect(
        calls.any((call) => call.method == 'WebView.clearAllCache'),
        isFalse,
      );
    },
  );

  test(
    'title channel dispatch preserves copies and ignores a released view',
    () async {
      final instances = InstanceManager(onWeakReferenceRemoved: (_) {});
      final titles = <String>[];
      // ignore: invalid_use_of_protected_member
      final view = native.WebView.detached(instanceManager: instances);
      // ignore: invalid_use_of_protected_member
      final chrome = native.WebChromeClient.detached(
        instanceManager: instances,
        onReceivedTitle: (_, title) => titles.add(title),
      );
      instances.addHostCreatedInstance(view, 31);
      instances.addHostCreatedInstance(chrome.copy(), 32);
      OhosWebViewCallbackDispatcher().setUp(
        OhosWebViewFlutterApis(
          webChromeClientFlutterApi: WebChromeClientFlutterApiImpl(
            instanceManager: instances,
          ),
        ),
      );
      Future<void> send(String title) async {
        final reply = Completer<ByteData?>();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              callback,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('WebChromeClient.onReceivedTitle', {
                  'instanceId': 32,
                  'webViewInstanceId': 31,
                  'title': title,
                }),
              ),
              reply.complete,
            );
        final envelope = await reply.future;
        if (envelope != null) {
          const StandardMethodCodec().decodeEnvelope(envelope);
        }
      }

      await send('Changed');
      await send('');
      expect(titles, ['Changed', '']);
      instances.remove(31);
      await send('Late');
      expect(titles, ['Changed', '']);
    },
  );
}

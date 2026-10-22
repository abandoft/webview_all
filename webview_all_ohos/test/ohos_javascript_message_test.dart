import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/channels/api_implementations.dart';
import 'package:webview_all_ohos/src/channels/callback_dispatcher.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart' as native;
import 'package:webview_all_ohos/src/ohos_webview_proxy.dart';
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

const String _callbackChannel = 'com.abandoft.webview_all_ohos/callback_api';
const int _channelIdentifier = 65536;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InstanceManager instanceManager;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.abandoft.webview_all_ohos/host_api'),
          (_) async => null,
        );
    instanceManager = InstanceManager(onWeakReferenceRemoved: (_) {});
    OhosWebViewCallbackDispatcher().setUp(
      OhosWebViewFlutterApis(
        javaScriptChannelFlutterApi: JavaScriptChannelFlutterApiImpl(
          instanceManager: instanceManager,
        ),
      ),
    );
  });

  tearDown(() {
    const MethodChannel(_callbackChannel).setMethodCallHandler(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.abandoft.webview_all_ohos/host_api'),
          null,
        );
  });

  void createChannel(void Function(JavaScriptMessage) onMessageReceived) {
    OhosJavaScriptChannelParams(
      name: 'Bridge',
      onMessageReceived: onMessageReceived,
      webViewProxy: OhosWebViewProxy(
        createJavaScriptChannel:
            (channelName, {required postMessage, postMessageWithSource}) {
              // ignore: invalid_use_of_protected_member
              final channel = native.JavaScriptChannel.detached(
                channelName,
                postMessage: postMessage,
                postMessageWithSource: postMessageWithSource,
                instanceManager: instanceManager,
              );
              instanceManager.addHostCreatedInstance(
                channel,
                _channelIdentifier,
              );
              return channel;
            },
      ),
    );
  }

  test(
    'native calling URLs are forwarded without inferring frame or origin',
    () async {
      final messages = <JavaScriptMessage>[];
      createChannel(messages.add);
      final payload = jsonEncode(<String, Object?>{
        'sourceUrl': 'https://forged.example/',
        'sourceOrigin': 'https://forged.example',
        'isMainFrame': true,
      });
      const sources = <String>[
        'https://example.com/top',
        'https://example.com/frame',
        'https://different.example/child',
        'about:srcdoc',
        'blob:https://example.com/opaque-document-id',
      ];

      for (final source in sources) {
        await _postMessage(<String, Object?>{
          'instanceId': _channelIdentifier,
          'message': payload,
          'sourceUrl': source,
          'sourceOrigin': 'https://forged.example',
          'isMainFrame': true,
          'url': 'https://current.example/after-navigation',
        });
      }

      expect(messages.map((message) => message.sourceUrl), sources);
      expect(messages.every((message) => message.message == payload), isTrue);
      expect(messages.every((message) => message.isMainFrame == null), isTrue);
      expect(messages.every((message) => message.sourceOrigin == null), isTrue);
    },
  );

  test('missing or malformed sender metadata remains unknown', () async {
    final messages = <JavaScriptMessage>[];
    createChannel(messages.add);
    for (final Object? source in <Object?>[null, '', 42, true]) {
      await _postMessage(<String, Object?>{
        'instanceId': _channelIdentifier,
        'message': 'hi',
        if (source != null) 'sourceUrl': source,
        'url': 'https://current.example/page',
        'sourceOrigin': 'https://forged.example',
        'isMainFrame': true,
      });
    }

    expect(messages, hasLength(4));
    for (final message in messages) {
      expect(message.message, 'hi');
      expect(message.sourceUrl, isNull);
      expect(message.isMainFrame, isNull);
      expect(message.sourceOrigin, isNull);
    }
  });

  test(
    'legacy native callbacks continue receiving each message once',
    () async {
      final messages = <String>[];
      // ignore: invalid_use_of_protected_member
      final channel = native.JavaScriptChannel.detached(
        'Legacy',
        postMessage: messages.add,
        instanceManager: instanceManager,
      );
      instanceManager.addHostCreatedInstance(channel, _channelIdentifier);

      await _postMessage(<String, Object?>{
        'instanceId': _channelIdentifier,
        'message': 'hello',
        'sourceUrl': 'https://example.com/sender',
      });

      expect(messages, <String>['hello']);
    },
  );

  test('copies preserve the sender-aware native callback', () async {
    final messages = <(String, String?)>[];
    var legacyCalls = 0;
    // ignore: invalid_use_of_protected_member
    final channel = native.JavaScriptChannel.detached(
      'Bridge',
      postMessage: (_) => legacyCalls++,
      postMessageWithSource: (message, source) =>
          messages.add((message, source)),
      instanceManager: instanceManager,
    );
    final copy = channel.copy();
    instanceManager.addHostCreatedInstance(copy, _channelIdentifier);

    await _postMessage(<String, Object?>{
      'instanceId': _channelIdentifier,
      'message': 'copied',
      'sourceUrl': 'https://example.com/sender',
    });

    expect(messages, <(String, String?)>[
      ('copied', 'https://example.com/sender'),
    ]);
    expect(legacyCalls, 0);
  });
}

Future<void> _postMessage(Map<String, Object?> arguments) async {
  final response = Completer<ByteData?>();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _callbackChannel,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('JavaScriptChannel.postMessage', arguments),
        ),
        response.complete,
      );
  final ByteData? data = await response.future;
  if (data != null) {
    const StandardMethodCodec().decodeEnvelope(data);
  }
}

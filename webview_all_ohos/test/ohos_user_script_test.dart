import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/channels/api_implementations.dart';
import 'package:webview_all_ohos/src/core/instance_manager.dart';
import 'package:webview_all_ohos/src/ohos_webview_native.dart' as native;
import 'package:webview_all_ohos/webview_all_ohos.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

const MethodChannel _host = MethodChannel(
  'com.abandoft.webview_all_ohos/host_api',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;
  late List<List<String>> snapshots;
  Future<void> Function(List<String>)? update;

  setUp(() {
    calls = <MethodCall>[];
    snapshots = <List<String>>[];
    update = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_host, (MethodCall call) async {
          calls.add(call);
          if (call.method == 'WebView.setDocumentStartScripts') {
            final Map<Object?, Object?> arguments =
                call.arguments as Map<Object?, Object?>;
            expect(arguments['instanceId'], isA<int>());
            final List<String> sources =
                (arguments['scripts']! as List<Object?>).cast<String>();
            snapshots.add(sources);
            await update?.call(sources);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_host, null);
  });

  OhosWebViewController createController() =>
      OhosWebViewController(OhosWebViewControllerCreationParams());

  test(
    'supports document-start registration before a widget is attached',
    () async {
      final OhosWebViewController controller = createController();
      expect(
        await controller.isUserScriptInjectionSupported(
          WebViewUserScriptInjectionTime.documentStart,
        ),
        isTrue,
      );
      final String id = await controller.addUserScript(
        const WebViewUserScript(source: 'globalThis.first = true;'),
      );
      expect(id, isNotEmpty);
      expect(snapshots.single.single, contains('globalThis.first = true;'));
      expect(
        snapshots.single.single,
        contains('globalThis.top !== globalThis'),
      );
      expect(
        calls.where(
          (MethodCall call) => <String>{
            'WebView.evaluateJavascript',
            'WebView.reload',
            'WebView.loadUrl',
          }.contains(call.method),
        ),
        isEmpty,
      );
    },
  );

  test(
    'preserves registration order and duplicate scripts as distinct entries',
    () async {
      final OhosWebViewController controller = createController();
      const WebViewUserScript script = WebViewUserScript(
        source: 'globalThis.order.push("entry");',
        forMainFrameOnly: false,
      );
      final String first = await controller.addUserScript(script);
      final String second = await controller.addUserScript(script);
      expect(first, isNot(second));
      expect(snapshots.last, hasLength(2));
      final List<String> full = snapshots.last;
      expect(full[0], isNot(full[1]));
      expect(full[0], snapshots.first.single);
      expect(
        full.every(
          (String source) => !source.contains('globalThis.top !== globalThis'),
        ),
        isTrue,
      );

      await controller.removeUserScript(first);
      expect(snapshots.last, <String>[full[1]]);
      await controller.removeAllUserScripts();
      expect(snapshots.last, isEmpty);
      final int count = snapshots.length;
      await controller.removeUserScript(second);
      await controller.removeUserScript('unknown');
      await controller.removeAllUserScripts();
      expect(snapshots, hasLength(count));
    },
  );

  test(
    'serializes concurrent updates until the native snapshot is acknowledged',
    () async {
      final OhosWebViewController controller = createController();
      final Completer<void> firstApplied = Completer<void>();
      update = (_) =>
          snapshots.length == 1 ? firstApplied.future : Future<void>.value();
      final Future<String> first = controller.addUserScript(
        const WebViewUserScript(source: 'globalThis.first = true;'),
      );
      final Future<String> second = controller.addUserScript(
        const WebViewUserScript(source: 'globalThis.second = true;'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, hasLength(1));
      firstApplied.complete();
      await Future.wait<String>(<Future<String>>[first, second]);
      expect(snapshots.last, hasLength(2));
      expect(snapshots.last[0], contains('globalThis.first = true;'));
      expect(snapshots.last[1], contains('globalThis.second = true;'));
    },
  );

  test(
    'failed updates preserve registered state and allow subsequent updates',
    () async {
      final OhosWebViewController controller = createController();
      final String kept = await controller.addUserScript(
        const WebViewUserScript(source: 'globalThis.kept = true;'),
      );
      final List<String> previous = snapshots.last;
      update = (_) => Future<void>.error(PlatformException(code: 'disposed'));
      await expectLater(
        controller.addUserScript(
          const WebViewUserScript(source: 'globalThis.failed = true;'),
        ),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        controller.removeUserScript(kept),
        throwsA(isA<PlatformException>()),
      );
      update = null;
      await controller.addUserScript(
        const WebViewUserScript(source: 'globalThis.next = true;'),
      );
      expect(snapshots.last, hasLength(2));
      expect(snapshots.last.first, previous.single);
      expect(snapshots.last.last, contains('globalThis.next = true;'));
      await controller.removeUserScript(kept);
      expect(snapshots.last, hasLength(1));
    },
  );

  test(
    'released native instances fail before sending a script update',
    () async {
      final InstanceManager manager = InstanceManager(
        onWeakReferenceRemoved: (_) {},
      );
      // ignore: invalid_use_of_protected_member
      final native.WebView view = native.WebView.detached(
        instanceManager: manager,
      );
      manager.addDartCreatedInstance(view);
      manager.removeWeakReference(view);
      expect(
        () => WebViewHostApiImpl(
          instanceManager: manager,
        ).setDocumentStartScriptsFromInstance(view, <String>[]),
        throwsStateError,
      );
      expect(snapshots, isEmpty);
    },
  );
}

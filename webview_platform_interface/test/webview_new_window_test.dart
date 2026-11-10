import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  test(
    'factory is cached across concurrent calls and mapped wrappers',
    () async {
      final pending = Completer<int>();
      var creates = 0;
      final request = WebViewNewWindowRequest<int>(
        onCreateController: () {
          creates++;
          return pending.future;
        },
        onAttach: (_) async => true,
        onReject: () async {},
      );
      final mapped = request.map<String>(
        int.parse,
        fromPlatform: (value) => '$value',
      );
      final first = mapped.createController();
      final second = mapped.createController();
      final direct = request.createController();
      await Future<void>.delayed(Duration.zero);
      expect(creates, 1);
      pending.complete(42);
      expect(await first, '42');
      expect(await second, '42');
      expect(await direct, 42);
      expect(await mapped.attach((await first)!), isTrue);
    },
  );

  test(
    'expiry prevents new creation but preserves ownership of an in-flight child',
    () async {
      final pending = Completer<int>();
      final request = WebViewNewWindowRequest<int>(
        onCreateController: () => pending.future,
        onAttach: (_) async => true,
        onReject: () async {},
      );
      final creation = request.createController();
      await request.reject();
      pending.complete(7);
      expect(await creation, 7);
      expect(await request.attach(7), isFalse);
      final expired = WebViewNewWindowRequest<int>(
        onCreateController: () async => throw StateError('must not create'),
        onAttach: (_) async => true,
        onReject: () async {},
      );
      await expired.reject();
      expect(await expired.createController(), isNull);
    },
  );
  test(
    'a mapped request attaches exactly once and preserves metadata',
    () async {
      final children = <int>[];
      var rejected = 0;
      final request = WebViewNewWindowRequest<int>(
        url: Uri.parse('https://example.test/child'),
        isUserGesture: true,
        onAttach: (value) async {
          children.add(value);
          return true;
        },
        onReject: () async {
          rejected++;
        },
      );
      final mapped = request.map<String>(int.parse);
      expect(mapped.url, request.url);
      expect(mapped.isUserGesture, isTrue);
      expect(await mapped.attach('42'), isTrue);
      expect(await mapped.attach('43'), isFalse);
      await request.reject();
      expect(children, [42]);
      expect(rejected, 0);
    },
  );

  test('abandoned and failed delegates release native deferrals', () async {
    for (final fail in [false, true]) {
      var rejected = 0;
      final request = WebViewNewWindowRequest<int>(
        onAttach: (_) async => throw StateError('attachment failed'),
        onReject: () async {
          rejected++;
        },
      );
      await dispatchWebViewNewWindowRequest<int>((_) {
        if (fail) throw StateError('delegate failed');
      }, request);
      expect(rejected, 1);
      expect(await request.attach(1), isFalse);
    }
  });

  test(
    'attachment failure returns false and rejects without throwing',
    () async {
      var rejected = 0;
      final request = WebViewNewWindowRequest<int>(
        onAttach: (_) async => throw StateError('incompatible profile'),
        onReject: () async {
          rejected++;
        },
      );
      expect(await request.attach(1), isFalse);
      expect(rejected, 1);
      await request.reject();
      expect(rejected, 1);
    },
  );

  testWidgets('a timed out delegate cannot attach a child later', (
    tester,
  ) async {
    var rejected = 0;
    var attached = 0;
    final held = Completer<void>();
    final request = WebViewNewWindowRequest<int>(
      onAttach: (_) async {
        attached++;
        return true;
      },
      onReject: () async {
        rejected++;
      },
    );
    final done = dispatchWebViewNewWindowRequest<int>(
      (_) => held.future,
      request,
    );
    await tester.pump(const Duration(seconds: 21));
    await done;
    expect(rejected, 1);
    expect(await request.attach(1), isFalse);
    held.complete();
    expect(attached, 0);
  });
}

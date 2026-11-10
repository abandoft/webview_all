import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('profile-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  var deleteCalls = 0;
  var status = 'pending';
  var supported = true;
  var rows = <Object?>[];
  var deletionError = false;
  setUp(() {
    deleteCalls = 0;
    status = 'pending';
    supported = true;
    rows = [];
    deletionError = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'profileManagementCapabilities':
          return {'listing': supported, 'deletion': supported};
        case 'listProfiles':
          return rows;
        case 'requestProfileDeletion':
          deleteCalls++;
          if (deletionError) throw PlatformException(code: 'transport_failed');
          return {'status': status};
        default:
          throw MissingPluginException();
      }
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  PlatformWebViewProfileManager manager() =>
      PlatformWebViewProfileManager.channel(channel.name);

  test(
    'unsupported management retains the app and makes no deletion request',
    () async {
      expect(await PlatformWebViewProfileManager().listProfiles(), isNull);
      expect(
        (await PlatformWebViewProfileManager().requestDeletion('a')).status,
        WebViewProfileDeletionStatus.unsupported,
      );
      supported = false;
      expect(await manager().listProfiles(), isNull);
      expect(
        (await manager().requestDeletion('a')).status,
        WebViewProfileDeletionStatus.unsupported,
      );
      expect(deleteCalls, 0);
    },
  );
  test(
    'invalid names never reach deletion or expand filesystem scope',
    () async {
      for (final name in [
        '',
        '.',
        '..',
        '../a',
        'a/b',
        'a\\b',
        'a b',
        '中文',
        'a' * 65,
      ]) {
        expect(
          (await manager().requestDeletion(name)).status,
          WebViewProfileDeletionStatus.failed,
        );
      }
      expect(deleteCalls, 0);
    },
  );
  test(
    'enumeration is sorted, immutable and preserves pending native state',
    () async {
      rows = [
        {'name': 'z'},
        {'name': 'a', 'deletionPending': true},
      ];
      final result = (await manager().listProfiles())!;
      expect(result.map((v) => v.name), ['a', 'z']);
      expect(result.first.deletionPending, isTrue);
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );
  test('malformed native entries are not exposed as owned profiles', () async {
    rows = [
      {'name': '../default'},
    ];
    expect(await manager().listProfiles(), isNull);
  });
  test(
    'every native outcome stays distinct and only deleted means complete',
    () async {
      for (final value in WebViewProfileDeletionStatus.values) {
        status = value.name;
        final result = await manager().requestDeletion('account_1');
        expect(result.status, value);
        expect(result.isDeleted, value == WebViewProfileDeletionStatus.deleted);
      }
      status = 'future_native_state';
      expect(
        (await manager().requestDeletion('a')).status,
        WebViewProfileDeletionStatus.unknown,
      );
    },
  );
  test(
    'transport failure does not claim that a submitted deletion had no effect',
    () async {
      deletionError = true;
      expect(
        (await manager().requestDeletion('a')).status,
        WebViewProfileDeletionStatus.unknown,
      );
      expect(deleteCalls, 1);
    },
  );
}

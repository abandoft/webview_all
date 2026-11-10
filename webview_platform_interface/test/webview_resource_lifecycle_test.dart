import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'helpers/garbage_collection.dart';

class _Owner {
  final bridge = WebViewResourceBridge(
    scheme: 'https',
    configure: (_, _, _) async {},
  );
  int calls = 0;

  Future<void> enable() => bridge.update(
    WebViewResourceDelegate(
      onRequest: (_) {
        calls++;
        return null;
      },
    ),
  );
}

@pragma('vm:never-inline')
Future<WeakReference<_Owner>> createOwner() async {
  final owner = _Owner();
  await owner.enable();
  return WeakReference<_Owner>(owner);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resource callbacks do not retain their released owner', () async {
    final weak = await createOwner();
    if (!await forceGarbageCollection()) {
      markTestSkipped('Run with --enable-vmservice to verify collection.');
      return;
    }
    expect(weak.target, isNull);
  });
}

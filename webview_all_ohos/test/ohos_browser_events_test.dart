import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_ohos/src/channels/browser_events.dart';

void main() {
  test(
    'native lifecycle callbacks ignore released views and contain application errors',
    () async {
      final owner = Object();
      var calls = 0;
      OhosBrowserEvents.observe(123, owner, (event) async {
        calls++;
        expect(event['type'], 'processFailed');
        throw StateError('Application callback fixture');
      });
      await OhosBrowserEvents.dispatch(123, {'type': 'processFailed'});
      expect(calls, 1);
      OhosBrowserEvents.remove(123);
      await OhosBrowserEvents.dispatch(123, {'type': 'processFailed'});
      expect(calls, 1);
    },
  );
}

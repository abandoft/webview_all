import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  WebViewDownloadRequest request(Set<WebViewDownloadAction> actions) =>
      WebViewDownloadRequest(
        id: '1',
        url: 'https://example.test/file',
        supportedActions: actions,
      );

  test(
    'unsupported actions are rejected instead of silently falling back',
    () async {
      final delegate = WebViewDownloadDelegate(
        onDownloadRequest: (_) =>
            const WebViewDownloadDecision.saveToFile('/tmp/file'),
      );
      await expectLater(
        delegate.decide(request({WebViewDownloadAction.cancel})),
        throwsUnsupportedError,
      );
    },
  );

  testWidgets('unanswered decisions time out', (tester) async {
    final pending = Completer<WebViewDownloadDecision>();
    final delegate = WebViewDownloadDelegate(
      onDownloadRequest: (_) => pending.future,
    );
    final check = expectLater(
      delegate.decide(request({WebViewDownloadAction.cancel})),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 31));
    await check;
  });

  testWidgets(
    'cancellation ends the wait and consumes a late callback failure',
    (tester) async {
      final pending = Completer<WebViewDownloadDecision>();
      final cancelled = Completer<void>();
      final delegate = WebViewDownloadDelegate(
        onDownloadRequest: (_) => pending.future,
      );
      final check = expectLater(
        delegate.decide(
          request({WebViewDownloadAction.cancel}),
          cancelled: cancelled.future,
        ),
        throwsStateError,
      );
      cancelled.complete();
      await tester.pump();
      await check;
      pending.completeError(StateError('late callback failure'));
      await tester.pump();
    },
  );

  test(
    'progress/result callback errors do not escape into native handling',
    () {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      try {
        final delegate = WebViewDownloadDelegate(
          onDownloadRequest: (_) => const WebViewDownloadDecision.cancel(),
          onDownloadProgress: (_) => throw StateError('progress'),
          onDownloadResult: (_) => throw StateError('result'),
        );
        delegate.notifyProgress(
          const WebViewDownloadProgress(id: '1', bytesReceived: 1),
        );
        delegate.notifyResult(
          const WebViewDownloadResult(
            id: '1',
            status: WebViewDownloadStatus.completed,
          ),
        );
        expect(errors, hasLength(2));
      } finally {
        FlutterError.onError = previous;
      }
    },
  );

  test('filename parsing preserves UTF-8 and rejects path/control metadata', () {
    String name(String disposition) => webViewDownloadSuggestedFilename(
      url: 'https://example.test/default.txt',
      contentDisposition: disposition,
    );
    expect(
      name(
        "attachment; filename=old.txt; filename*=UTF-8''%E4%B8%AD%E6%96%87.txt",
      ),
      '中文.txt',
    );
    expect(name('attachment; filename="../private/actual.txt"'), 'actual.txt');
    expect(
      name('attachment; filename="report; final.txt"'),
      'report; final.txt',
    );
    expect(name('attachment; filename=".."'), 'download');
    expect(
      name("attachment; filename=fallback.txt; filename*=UTF-8''%GG"),
      'fallback.txt',
    );
    expect(
      webViewDownloadSuggestedFilename(url: 'https://example.test/a%20b.txt'),
      'a b.txt',
    );
  });
}

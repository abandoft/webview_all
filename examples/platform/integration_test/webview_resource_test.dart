import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';

import 'support/resource_test_binding.dart';

void main() {
  initializeResourceTestBinding();

  testWidgets(
    'application resources preserve ranges, streaming and cancellation',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'webview-resource-integration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/large.bin');
      final handle = await file.open(mode: FileMode.write);
      await handle.setPosition(16 * 1024 * 1024);
      await handle.writeFrom(<int>[1, 2, 3, 4]);
      await handle.close();
      final hugeFile = File('${directory.path}/huge.bin');
      final hugeHandle = await hugeFile.open(mode: FileMode.write);
      await hugeHandle.setPosition(2147483648);
      await hugeHandle.writeFrom(<int>[5, 6, 7, 8]);
      await hugeHandle.close();
      final video = File('${directory.path}/sample.mp4');
      final videoBytes = await rootBundle.load('assets/sample_video.mp4');
      await video.writeAsBytes(
        videoBytes.buffer.asUint8List(
          videoBytes.offsetInBytes,
          videoBytes.lengthInBytes,
        ),
      );
      final PlatformWebViewControllerCreationParams creationParams =
          Platform.isIOS || Platform.isMacOS
          ? WebKitWebViewControllerCreationParams(
              allowsInlineMediaPlayback: true,
              mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
            )
          : const PlatformWebViewControllerCreationParams();
      final controller = WebViewController.fromPlatformCreationParams(
        creationParams,
      );
      final other = WebViewController.fromPlatformCreationParams(
        creationParams,
      );
      final loaded = Completer<void>();
      final result = Completer<Map<String, dynamic>>();
      final mediaResult = Completer<Map<String, dynamic>>();
      final streamCancelled = Completer<void>();
      final cancelRequested = Completer<void>();
      StreamController<List<int>>? source;
      StreamController<List<int>>? cancelledSource;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await controller.platform.closeWebViewSession();
        await other.platform.closeWebViewSession();
        await source?.close();
        await cancelledSource?.close();
      });
      await other.setResourceDelegate(
        WebViewResourceDelegate(onRequest: (_) => null),
      );
      expect(controller.resourceCapabilities.supportsResources, isTrue);
      if (controller.platform is LinuxWebViewController) {
        final linux = controller.platform as LinuxWebViewController;
        await linux.setMediaPlaybackRequiresUserGesture(false);
        await linux.setMediaPlaybackAllowsInline(true);
      }
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.addJavaScriptChannel(
        'ResourceResults',
        onMessageReceived: (message) {
          final value = jsonDecode(message.message) as Map<String, dynamic>;
          if (value['phase'] == 'first') {
            source!.add(utf8.encode('end'));
            unawaited(source!.close());
          } else if (value['phase'] == 'abort') {
            if (!cancelRequested.isCompleted) cancelRequested.complete();
          } else if (value['phase'] == 'media') {
            if (!mediaResult.isCompleted) mediaResult.complete(value);
          } else if (!result.isCompleted) {
            result.complete(value);
          }
        },
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
      final seen = <String>[];
      await controller.setResourceDelegate(
        WebViewResourceDelegate(
          onRequest: (request) {
            seen.add(request.path);
            switch (request.path) {
              case '/index.html':
                return WebViewResourceResponse.bytes(
                  Uint8List.fromList(
                    utf8.encode(
                      '<!doctype html><meta charset="utf-8"><title>resources</title>',
                    ),
                  ),
                  mimeType: 'text/html',
                );
              case '/bytes.bin':
              case '/图像/空 格.bin':
                return WebViewResourceResponse.bytes(
                  Uint8List.fromList(<int>[0, 1, 2, 3, 4]),
                  mimeType: 'application/octet-stream',
                  headers: const <String, String>{'etag': '"current"'},
                );
              case '/file.bin':
                return WebViewResourceResponse.file(
                  file.path,
                  mimeType: 'application/octet-stream',
                );
              case '/huge.bin':
                return WebViewResourceResponse.file(
                  hugeFile.path,
                  mimeType: 'application/octet-stream',
                );
              case '/video%20literal.mp4':
                return WebViewResourceResponse.file(
                  video.path,
                  mimeType: 'video/mp4',
                );
              case '/stream.bin':
                source = StreamController<List<int>>();
                source!.add(List<int>.filled(65536, 65));
                return WebViewResourceResponse.stream(
                  source!.stream,
                  mimeType: 'application/octet-stream',
                );
              case '/cancel.bin':
                cancelledSource = StreamController<List<int>>(
                  onCancel: () {
                    if (!streamCancelled.isCompleted) {
                      streamCancelled.complete();
                    }
                  },
                );
                cancelledSource!.add(List<int>.filled(65536, 66));
                return WebViewResourceResponse.stream(
                  cancelledSource!.stream,
                  mimeType: 'application/octet-stream',
                );
              default:
                return null;
            }
          },
        ),
      );
      final entry = controller.getResourceUri('index.html')!;
      final bytes = controller.getResourceUri('bytes.bin')!;
      final unicode = controller.getResourceUri('图像/空 格.bin')!;
      final fileUrl = controller.getResourceUri('file.bin')!;
      final hugeUrl = controller.getResourceUri('huge.bin')!;
      final missing = controller.getResourceUri('missing')!;
      final stream = controller.getResourceUri('stream.bin')!;
      final cancel = controller.getResourceUri('cancel.bin')!;
      final videoUrl = controller.getResourceUri('video%20literal.mp4')!;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 640,
            height: 480,
            child: WebViewWidget(controller: controller),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await controller.loadRequest(entry);
      await loaded.future.timeout(const Duration(seconds: 25));
      await controller.runJavaScript('''
      void (async () => {
        try {
          const ranged = await fetch(${jsonEncode(fileUrl.toString())}, {headers: {Range: 'bytes=-4'}});
          const file = Array.from(new Uint8Array(await ranged.arrayBuffer()));
          const byteResponse = await fetch(${jsonEncode(bytes.toString())}, {headers: {Range: 'bytes=1-2'}});
          const byteValues = Array.from(new Uint8Array(await byteResponse.arrayBuffer()));
          const huge = await fetch(${jsonEncode(hugeUrl.toString())}, {headers: {Range: 'bytes=-4'}});
          const hugeBytes = Array.from(new Uint8Array(await huge.arrayBuffer()));
          const conditional = await fetch(${jsonEncode(bytes.toString())}, {headers: {Range: 'bytes=1-2', 'If-Range': '"old"'}});
          const conditionalBytes = Array.from(new Uint8Array(await conditional.arrayBuffer()));
          const head = await fetch(${jsonEncode(fileUrl.toString())}, {method: 'HEAD'});
          const absent = await fetch(${jsonEncode(missing.toString())});
          const unicode = await fetch(${jsonEncode(unicode.toString())});
          let streamLength = 0;
          if (${controller.resourceCapabilities.supportsStreaming}) {
            const response = await fetch(${jsonEncode(stream.toString())});
            const reader = response.body.getReader();
            const first = await reader.read();
            streamLength += first.value.length;
            ResourceResults.postMessage(JSON.stringify({phase: 'first'}));
            while (true) {
              const next = await reader.read();
              if (next.done) break;
              streamLength += next.value.length;
            }
            const abort = new AbortController();
            const cancelled = await fetch(${jsonEncode(cancel.toString())}, {signal: abort.signal});
            await cancelled.body.getReader().read();
            abort.abort();
            ResourceResults.postMessage(JSON.stringify({phase: 'abort'}));
          }
          ResourceResults.postMessage(JSON.stringify({
            status: ranged.status, range: ranged.headers.get('content-range'), file,
            bytes: byteValues, byteLength: byteResponse.headers.get('content-length'),
            type: byteResponse.headers.get('content-type'),
            huge: huge.status, hugeRange: huge.headers.get('content-range'), hugeBytes,
            conditional: conditional.status, conditionalBytes,
            head: head.status, length: head.headers.get('content-length'),
            missing: absent.status, unicode: unicode.status, streamLength
          }));
        } catch (error) {
          ResourceResults.postMessage(JSON.stringify({error: String(error)}));
        }
      })();
    ''');
      final actual = await result.future.timeout(const Duration(seconds: 35));
      expect(actual, <String, Object?>{
        'status': 206,
        'range': 'bytes 16777216-16777219/16777220',
        'file': <int>[1, 2, 3, 4],
        'bytes': <int>[1, 2],
        'byteLength': '2',
        'type': 'application/octet-stream',
        'huge': Platform.isAndroid ? 501 : 206,
        'hugeRange': Platform.isAndroid
            ? null
            : 'bytes 2147483648-2147483651/2147483652',
        'hugeBytes': Platform.isAndroid ? <int>[] : <int>[5, 6, 7, 8],
        'conditional': Platform.isAndroid ? 501 : 200,
        'conditionalBytes': Platform.isAndroid ? <int>[] : <int>[0, 1, 2, 3, 4],
        'head': 200,
        'length': '16777220',
        'missing': 404,
        'unicode': 200,
        'streamLength': controller.resourceCapabilities.supportsStreaming
            ? 65539
            : 0,
      });
      if (controller.resourceCapabilities.supportsStreaming) {
        await cancelRequested.future.timeout(const Duration(seconds: 10));
        await streamCancelled.future.timeout(const Duration(seconds: 10));
      }
      expect(seen, contains('/图像/空 格.bin'));
      // Exercise the documented HTML media use case, including seeking and a
      // literal percent-encoded-looking name, from a separate HTML document.
      await controller.loadHtmlString('''
<!doctype html><meta charset="utf-8">
<video id="video" preload="auto" muted playsinline autoplay></video>
<script>
const video = document.getElementById('video');
const report = (value) => ResourceResults.postMessage(JSON.stringify({phase: 'media', ...value}));
video.onerror = () => report({error: video.error ? video.error.code : 'unknown'});
video.onloadedmetadata = () => { video.currentTime = Math.min(1, video.duration / 2); };
video.onseeked = () => report({duration: video.duration, time: video.currentTime, width: video.videoWidth});
const source = document.createElement('source');
source.type = 'video/mp4';
source.src = ${jsonEncode(videoUrl.toString())};
video.appendChild(source);
video.load();
video.play().catch(error => report({error: String(error)}));
</script>
''', baseUrl: controller.getResourceUri('/')!.toString());
      final media = await mediaResult.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () async {
          final state = await controller.runJavaScriptReturningResult('''
JSON.stringify({readyState: video.readyState, networkState: video.networkState, src: video.currentSrc, visibility: document.visibilityState, error: video.error && video.error.code})
''');
          throw TimeoutException('Media state: $state; requests: $seen');
        },
      );
      expect(media, isNot(contains('error')));
      expect(media['duration'], greaterThan(0));
      expect(media['time'], greaterThan(0));
      expect(media['width'], greaterThan(0));
      expect(seen, contains('/video%20literal.mp4'));
      await controller.setResourceDelegate(null);
      expect(controller.getResourceUri('file.bin'), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

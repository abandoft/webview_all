import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_all/webview_all.dart';

/// Keeps application-owned download UI above native desktop WebViews.
Future<void> showDownloadExample(
  BuildContext context,
  WebViewController controller,
) => Navigator.of(context).push<void>(
  PageRouteBuilder<void>(
    opaque: true,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    pageBuilder: (_, _, _) => _DownloadExamplePage(controller: controller),
  ),
);

class _DownloadExamplePage extends StatefulWidget {
  const _DownloadExamplePage({required this.controller});

  final WebViewController controller;

  @override
  State<_DownloadExamplePage> createState() => _DownloadExamplePageState();
}

class _DownloadExamplePageState extends State<_DownloadExamplePage> {
  final _pageReady = Completer<void>();
  late final Future<void> _ready;
  bool _delegateInstalled = false;
  String _status = 'Choose Download to start.';

  @override
  void initState() {
    super.initState();
    _ready = _prepare();
  }

  Future<void> _prepare() async {
    await widget.controller.setDownloadDelegate(
      WebViewDownloadDelegate(
        onDownloadRequest: _chooseTarget,
        onDownloadProgress: (progress) => _setStatus(
          'Received ${progress.bytesReceived} bytes'
          '${progress.totalBytes == null ? '' : ' of ${progress.totalBytes}'}',
        ),
        onDownloadResult: (result) => _setStatus(switch (result.status) {
          WebViewDownloadStatus.completed => 'Saved to ${result.path}',
          WebViewDownloadStatus.cancelled => 'Download cancelled',
          WebViewDownloadStatus.failed =>
            'Download failed: ${result.description ?? result.errorCode}',
          WebViewDownloadStatus.handedOff => 'Download request handed over',
        }),
      ),
    );
    _delegateInstalled = true;
    if (!mounted) return;
    await widget.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    if (!mounted) return;
    await widget.controller.addJavaScriptChannel(
      'DownloadExampleReady',
      onMessageReceived: (_) {
        if (!_pageReady.isCompleted) _pageReady.complete();
      },
    );
    try {
      if (!mounted) return;
      await widget.controller.loadHtmlString(
        '''<!doctype html><title>Downloads</title>
        <a download="example.txt" href="data:text/plain;charset=utf-8,Downloaded%20from%20webview_all">Download</a>
        <script>DownloadExampleReady.postMessage('ready');</script>''',
      );
      await _pageReady.future.timeout(const Duration(seconds: 10));
    } finally {
      await widget.controller.removeJavaScriptChannel('DownloadExampleReady');
    }
  }

  void _setStatus(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<WebViewDownloadDecision> _chooseTarget(
    WebViewDownloadRequest request,
  ) async {
    if (!mounted) return const WebViewDownloadDecision.cancel();
    if (!request.supportedActions.contains(WebViewDownloadAction.saveToFile)) {
      if (request.supportedActions.contains(
        WebViewDownloadAction.platformDefault,
      )) {
        return const WebViewDownloadDecision.platformDefault();
      }
      _setStatus('This platform requires an application download handler.');
      return const WebViewDownloadDecision.cancel();
    }
    final directory = await getApplicationDocumentsDirectory();
    var filename = (request.suggestedFilename ?? 'download')
        .replaceAll('\\', '/')
        .split('/')
        .last;
    if (filename.isEmpty || filename == '.' || filename == '..') {
      filename = 'download';
    }
    final path = '${directory.path}/$filename';
    if (!mounted) return const WebViewDownloadDecision.cancel();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save download?'),
        content: Text(
          'Save to $path\n\nAn existing file will not be replaced.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return accepted == true
        ? WebViewDownloadDecision.saveToFile(path)
        : const WebViewDownloadDecision.cancel();
  }

  Future<void> _download() async {
    try {
      await widget.controller.runJavaScript(
        'document.querySelector("a").click()',
      );
    } catch (error) {
      _setStatus('Download failed: $error');
    }
  }

  @override
  void dispose() {
    if (!_pageReady.isCompleted) _pageReady.complete();
    unawaited(_clearDelegate());
    super.dispose();
  }

  Future<void> _clearDelegate() async {
    try {
      // Wait for an in-flight installation before removing this demo's delegate.
      try {
        await _ready;
      } finally {
        if (_delegateInstalled) {
          await widget.controller.setDownloadDelegate(null);
        }
      }
    } catch (error) {
      debugPrint('Download example cleanup: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Downloads')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: FutureBuilder<void>(
        future: _ready,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text('Download handling unavailable: ${snapshot.error}');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton(
                onPressed: snapshot.connectionState == ConnectionState.done
                    ? _download
                    : null,
                child: const Text('Download a text file'),
              ),
              const SizedBox(height: 16),
              Text(_status),
            ],
          );
        },
      ),
    ),
  );
}

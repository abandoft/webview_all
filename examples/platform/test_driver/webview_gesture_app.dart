import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_wkwebview/webview_all_wkwebview.dart';

// Native XCUITest drives this app so that touches reach UIKit, rather than only
// being synthesized inside Flutter's widget test binding.
void main() => runApp(const MaterialApp(home: GestureTestPage()));

class GestureTestPage extends StatefulWidget {
  const GestureTestPage({super.key});

  @override
  State<GestureTestPage> createState() => _GestureTestPageState();
}

class _GestureTestPageState extends State<GestureTestPage> {
  WebViewSession? _session;
  bool _overlayVisible = false;
  int _overlayTaps = 0;
  WebKitGestureBlockingPolicy _policy =
      WebKitGestureBlockingPolicy.fallbackToPluginDefault;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final session = await WebViewSession.create(
      mode: WebViewSessionMode.shared,
    );
    if (session == null) throw StateError('Could not create the test WebView');
    await session.controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await session.controller.loadHtmlString('''
<!doctype html>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
  body { margin: 0; height: 2400px; background: linear-gradient(white, grey); }
  button { position: fixed; left: 20px; top: 80px; width: 200px; height: 80px; }
</style>
<script>
window.taps = 0;
addEventListener('scroll', function() {
  document.getElementById('scroll').textContent='Scroll: '+Math.round(scrollY);
});
</script>
<div id="scroll" style="position:fixed;top:20px;left:20px">Scroll: 0</div>
<button onclick="this.textContent='Web taps: '+(++window.taps)">Web taps: 0</button>
''');
    if (!mounted) {
      await session.close();
      return;
    }
    setState(() => _session = session);
  }

  Future<void> _nextPolicy() async {
    await _session!.controller.runJavaScript('''
window.taps = 0;
document.querySelector('button').textContent = 'Web taps: 0';
scrollTo(0, 0);
''');
    if (!mounted) return;
    setState(() {
      _policy = WebKitGestureBlockingPolicy.values[_policy.index + 1];
      _overlayTaps = 0;
    });
  }

  @override
  void dispose() {
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Text('Policy: ${_policy.name}'),
          Text('Overlay taps: $_overlayTaps'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () =>
                    setState(() => _overlayVisible = !_overlayVisible),
                child: Text(_overlayVisible ? 'Hide overlay' : 'Show overlay'),
              ),
              TextButton(
                onPressed:
                    _session == null ||
                        _policy == WebKitGestureBlockingPolicy.values.last
                    ? null
                    : _nextPolicy,
                child: const Text('Next policy'),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                if (_session != null)
                  Positioned.fill(
                    child: WebViewWidget.fromPlatformCreationParams(
                      params: WebKitWebViewWidgetCreationParams(
                        controller: _session!.controller.platform,
                        uiKitGestureBlockingPolicy: _policy,
                      ),
                    ),
                  ),
                if (_overlayVisible)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _overlayTaps++),
                      child: const ColoredBox(color: Colors.blue),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_android/webview_all_android.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runInputFocusTests();
}

const _inputPage = '''
<!doctype html>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { margin: 0; }
  canvas { position: absolute; width: 100%; height: 50%; background: #ddd; }
  #editor { opacity: 0; position: absolute; pointer-events: none; }
  #first { position: absolute; top: 60%; left: 10%; width: 80%; height: 20%; }
  #last { position: absolute; top: 85%; left: 10%; width: 80%; }
</style>
<canvas></canvas>
<input id="editor" tabindex="-1">
<input id="first">
<input id="last">
<script>
  requestAnimationFrame(() => { window.readyForInput = true; });
  document.querySelector('canvas').addEventListener('touchstart', function(event) {
    event.preventDefault();
  }, {passive: false});
  document.querySelector('canvas').addEventListener('touchend', function(event) {
    event.preventDefault();
    document.getElementById('editor').focus();
  }, {passive: false});
</script>
''';

void runInputFocusTests() {
  for (final hybrid in <bool>[false, true]) {
    testWidgets('Android input focus and IME (hybrid: $hybrid)', (
      tester,
    ) async {
      final controller = WebViewController();
      final inputFocus = FocusNode();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        inputFocus.dispose();
        await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
        await _waitFor(tester, () async => tester.view.viewInsets.bottom == 0);
      });
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      final loaded = Completer<void>();
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded.isCompleted) loaded.complete();
          },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                TextField(focusNode: inputFocus),
                Expanded(
                  child: WebViewWidget.fromPlatformCreationParams(
                    params:
                        AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                          PlatformWebViewWidgetCreationParams(
                            controller: controller.platform,
                          ),
                          displayWithHybridComposition: hybrid,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await controller.loadHtmlString(_inputPage);
      await loaded.future.timeout(const Duration(seconds: 15));
      await _waitFor(
        tester,
        () async =>
            await controller.runJavaScriptReturningResult(
              'window.readyForInput === true',
            ) ==
            true,
      );
      for (final target in <String>['editor', 'first', 'editor']) {
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(WebViewWidget));
        await tester.tapAt(
          Offset(
            rect.center.dx,
            rect.top + rect.height * (target == 'editor' ? .25 : .7),
          ),
        );
        await _waitFor(
          tester,
          () async =>
              await controller.runJavaScriptReturningResult(
                'document.activeElement.id === "$target"',
              ) ==
              true,
        );
        await tester.pumpAndSettle();
        await _waitFor(tester, () async => tester.view.viewInsets.bottom > 0);
        expect(inputFocus.hasFocus, isFalse);
        inputFocus.requestFocus();
        await _waitFor(tester, () async => inputFocus.hasFocus);
        await _waitFor(tester, () async => tester.view.viewInsets.bottom > 0);
      }
    }, skip: !Platform.isAndroid);
  }

  testWidgets('Windows native keyboard traverses Flutter and WebView inputs', (
    tester,
  ) async {
    final controller = WebViewController();
    final before = FocusNode();
    final after = FocusNode();
    final text = TextEditingController();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await (controller.platform as WindowsWebViewController).dispose();
      before.dispose();
      after.dispose();
      text.dispose();
    });
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final loaded = Completer<void>();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (!loaded.isCompleted) loaded.complete();
        },
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              TextField(focusNode: before, controller: text),
              Expanded(child: WebViewWidget(controller: controller)),
              TextField(focusNode: after),
            ],
          ),
        ),
      ),
    );
    await controller.loadHtmlString(_inputPage);
    await loaded.future.timeout(const Duration(seconds: 15));
    await _windowsKeys('', activate: true);
    before.requestFocus();
    await _waitFor(tester, () async => before.hasFocus);
    await _windowsKeys('flutter');
    await _waitFor(tester, () async => text.text == 'flutter');
    await _windowsKeys('{TAB}');
    await _waitFor(
      tester,
      () async =>
          await controller.runJavaScriptReturningResult(
            'document.hasFocus() && document.activeElement.id === "first"',
          ) ==
          true,
    );
    expect(before.hasFocus, isFalse);
    await _windowsKeys('webview');
    await _waitFor(
      tester,
      () async =>
          await controller.runJavaScriptReturningResult(
            'document.getElementById("first").value === "webview"',
          ) ==
          true,
    );
    await _windowsKeys('{TAB}{TAB}');
    await _waitFor(tester, () async => after.hasFocus);
    await _windowsKeys('+{TAB}');
    await _waitFor(
      tester,
      () async =>
          await controller.runJavaScriptReturningResult(
            'document.hasFocus() && document.activeElement.id === "last"',
          ) ==
          true,
    );
    await _windowsKeys('+{TAB}+{TAB}');
    await _waitFor(tester, () async => before.hasFocus);
    // Desktop traversal can select the whole field. Verify appending explicitly.
    text.selection = TextSelection.collapsed(offset: text.text.length);
    await tester.pump();
    await _windowsKeys('again');
    await _waitFor(tester, () async => text.text == 'flutteragain');

    final rect = tester.getRect(find.byType(WebViewWidget));
    final position = Offset(rect.center.dx, rect.top + rect.height * .7);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(position);
    await mouse.down(position);
    await mouse.up();
    await mouse.removePointer();
    await _waitFor(
      tester,
      () async =>
          await controller.runJavaScriptReturningResult(
            'document.hasFocus() && document.activeElement.id === "first"',
          ) ==
          true,
    );
    expect(before.hasFocus, isFalse);
    await _windowsKeys('{TAB}{TAB}');
    await _waitFor(tester, () async => after.hasFocus);
  }, skip: !Platform.isWindows);

  testWidgets('Windows keyboard survives moved, scaled and restored views', (
    tester,
  ) async {
    final controllers = [WebViewController(), WebViewController()];
    final phase = ValueNotifier<int>(0);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final controller in controllers) {
        await (controller.platform as WindowsWebViewController).dispose();
      }
      phase.dispose();
    });
    final loaded = [Completer<void>(), Completer<void>()];
    for (var i = 0; i < controllers.length; i++) {
      final index = i;
      await controllers[i].setJavaScriptMode(JavaScriptMode.unrestricted);
      await controllers[i].setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (!loaded[index].isCompleted) loaded[index].complete();
          },
        ),
      );
    }
    final children = [
      for (var i = 0; i < controllers.length; i++)
        RepaintBoundary(
          child: SizedBox(
            width: 220,
            height: 150,
            child: WebViewWidget(
              key: ValueKey('geometry-view-$i'),
              controller: controllers[i],
            ),
          ),
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: phase,
            builder: (_, value, _) => Stack(
              children: [
                Positioned(
                  left: value == 0 ? 30 : 65,
                  top: value == 0 ? 25 : 70,
                  child: Offstage(
                    offstage: value == 3,
                    child: Transform.scale(
                      scale: value >= 2 ? 1.25 : 1,
                      alignment: Alignment.topLeft,
                      child: children[0],
                    ),
                  ),
                ),
                Positioned(left: 370, top: 55, child: children[1]),
              ],
            ),
          ),
        ),
      ),
    );
    const html =
        '<!doctype html><html><body style="margin:0"><input id="input" style="position:absolute;left:20px;top:20px;width:160px;height:45px;font-size:20px"></body></html>';
    for (final controller in controllers) {
      await controller.loadHtmlString(html);
    }
    await Future.wait(
      loaded.map((item) => item.future.timeout(const Duration(seconds: 20))),
    );
    await _windowsKeys('', activate: true);
    Future<void> typeIn(
      int index,
      String keys,
      String expected, {
      double cssWidth = 220,
    }) async {
      await tester.pump(const Duration(milliseconds: 200));
      await _waitFor(
        tester,
        () async =>
            await controllers[index].runJavaScriptReturningResult(
              'document.visibilityState === "visible"',
            ) ==
            true,
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      final rect = tester.getRect(find.byKey(ValueKey('geometry-view-$index')));
      final position = rect.topLeft + Offset(40, 40) * (rect.width / 220);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(position);
      await mouse.down(position);
      await mouse.up();
      await mouse.removePointer();
      await _waitFor(
        tester,
        () async =>
            await controllers[index].runJavaScriptReturningResult(
              'document.hasFocus() && document.activeElement.id === "input"',
            ) ==
            true,
      );
      await _windowsKeys('{END}$keys');
      await _waitFor(
        tester,
        () async =>
            await controllers[index].runJavaScriptReturningResult(
              'document.getElementById("input").value === "$expected"',
            ) ==
            true,
      );
      expect(
        await controllers[index].runJavaScriptReturningResult(
          'window.innerWidth',
        ),
        closeTo(cssWidth, 1),
        reason: 'Visual scaling must preserve the page layout width.',
      );
      expect(find.text('WebView rendering failed.'), findsNothing);
    }

    await typeIn(0, 'a', 'a');
    phase.value = 1;
    await typeIn(0, 'b', 'ab');
    phase.value = 2;
    await typeIn(0, 'c', 'abc');
    await (controllers[0].platform as WindowsWebViewController).setZoomFactor(
      1.2,
    );
    phase.value = 3;
    await typeIn(1, 'd', 'd');
    phase.value = 4;
    await typeIn(0, 'e', 'abce', cssWidth: 220 / 1.2);
    await typeIn(1, 'f', 'df');
  }, skip: !Platform.isWindows);
}

Future<void> _waitFor(
  WidgetTester tester,
  Future<bool> Function() condition,
) async {
  final watch = Stopwatch()..start();
  while (!await condition()) {
    if (watch.elapsed > const Duration(seconds: 10)) {
      fail('Input focus did not reach the expected state.');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
}

Future<void> _windowsKeys(String keys, {bool activate = false}) async {
  final result = await Process.run('powershell', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    '''
Add-Type -AssemblyName System.Windows.Forms
${activate ? '''Add-Type 'using System; using System.Runtime.InteropServices; public class FocusTestWindow { [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window); [DllImport("user32.dll")] public static extern IntPtr LoadKeyboardLayout(string layout, uint flags); [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wparam, IntPtr lparam); }'
\$window = (Get-Process -Id $pid).MainWindowHandle
[FocusTestWindow]::SetForegroundWindow(\$window) | Out-Null
[FocusTestWindow]::SendMessage(\$window, 0x50, [IntPtr]::Zero, [FocusTestWindow]::LoadKeyboardLayout('00000409', 0)) | Out-Null''' : ''}
[System.Windows.Forms.SendKeys]::SendWait('$keys')
''',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
}

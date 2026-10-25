// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:webview_all/webview_all.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_all_windows/webview_all_windows.dart';

// Run separately: environment configuration lasts for the native process.
Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('custom storage is shared by views, cookies and cleanup', (
    WidgetTester tester,
  ) async {
    final root = await Directory.systemTemp.createTemp('webview-all-storage-');
    // The engine keeps its profile open until process exit. In particular,
    // Windows cannot delete this temporary directory while WebView2 is alive.
    final dataPath = '${root.path}${Platform.pathSeparator}data';
    final cachePath = '${root.path}${Platform.pathSeparator}cache';

    Future<void> ensure({String? userDataPath, String? cachePath}) {
      if (Platform.isWindows) {
        return WindowsWebViewController.ensureEnvironment(
          userDataPath: userDataPath,
        );
      }
      return LinuxWebViewController.ensureEnvironment(
        userDataPath: userDataPath,
        cachePath: cachePath,
      );
    }

    await Future.wait(<Future<void>>[
      ensure(userDataPath: dataPath, cachePath: cachePath),
      ensure(),
      ensure(userDataPath: dataPath, cachePath: cachePath),
    ]);
    await expectLater(
      ensure(userDataPath: ''),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'environment_configuration_conflict',
        ),
      ),
    );

    // This default manager must inherit the custom environment before there
    // is any visible WebView or controller.
    final initialCleanup = await WebViewDataManager().clearAllWebsiteData();
    expect(initialCleanup.failures, isEmpty);
    expect(initialCleanup.clearedDataTypes, contains(WebViewDataType.cookies));

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        request.response.headers.contentType = ContentType.html;
        request.response.write('<!doctype html><title>Storage test</title>');
        await request.response.close();
      }),
    );
    final origin = Uri.parse('http://127.0.0.1:${server.port}/');
    // Keep a native WebView alive: closing the last WebView2 controller can
    // end its browser session and discard session cookies.
    final session = await OffscreenWebViewSession.create();
    addTearDown(session.close);
    final controller = session.controller;
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    final cookies = WebViewCookieManager();
    await cookies.setCookie(
      const WebViewCookie(
        name: 'shared_environment',
        value: 'selected',
        domain: '127.0.0.1',
        path: '/',
      ),
    );

    var loaded = Completer<void>();
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (url) {
          if (url == origin.toString() && !loaded.isCompleted) {
            loaded.complete();
          }
        },
      ),
    );
    await controller.loadRequest(origin);
    await loaded.future.timeout(const Duration(seconds: 20));
    expect(
      await controller.runJavaScriptReturningResult('document.cookie'),
      contains('shared_environment=selected'),
    );
    await controller.runJavaScript(
      "localStorage.setItem('shared_environment', 'selected')",
    );

    await expectLater(
      ensure(userDataPath: '${root.path}${Platform.pathSeparator}other'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'environment_configuration_conflict',
        ),
      ),
    );
    expect(
      await controller.runJavaScriptReturningResult(
        "localStorage.getItem('shared_environment') === 'selected'",
      ),
      isTrue,
    );

    final cleared = await WebViewDataManager().clearAllWebsiteData();
    expect(cleared.failures, isEmpty);
    expect(cleared.clearedDataTypes, contains(WebViewDataType.localStorage));
    expect(await cookies.getCookies(domain: origin), isEmpty);
    loaded = Completer<void>();
    await controller.reload();
    await loaded.future.timeout(const Duration(seconds: 20));
    expect(
      await controller.runJavaScriptReturningResult('document.cookie'),
      isEmpty,
    );
    expect(
      await controller.runJavaScriptReturningResult(
        "localStorage.getItem('shared_environment') === null",
      ),
      isTrue,
    );
  }, skip: !Platform.isWindows && !Platform.isLinux);
}

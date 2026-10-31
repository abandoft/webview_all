// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'windows_webview_controller.dart';
import 'windows_webview_native.dart' as native_webview;
import 'windows_webview_cookie_manager.dart';
import 'windows_webview_data_manager.dart';

/// Implementation of [WebViewPlatform] using WebView2 on Windows.
class WindowsWebViewPlatform extends WebViewPlatform {
  @override
  Set<WebViewSessionMode> get supportedSessionModes =>
      WebViewSessionMode.values.toSet();

  @override
  Future<WebViewSessionCapabilities> getSessionCapabilities() async {
    final privateSupported =
        await native_webview.WebviewController.isIncognitoSupported();
    return WebViewSessionCapabilities(
      supportedModes: {
        WebViewSessionMode.shared,
        if (privateSupported) ...[
          WebViewSessionMode.incognito,
          WebViewSessionMode.isolatedIncognito,
        ],
      },
      privateSessionRestriction: privateSupported
          ? null
          : 'This WebView2 Runtime does not support InPrivate controller options. Update the WebView2 Runtime to enable private sessions.',
      canClose: true,
      incognitoSupport: privateSupported
          ? WebViewIncognitoSupport.nativeStore
          : WebViewIncognitoSupport.none,
      scopedCookies: true,
      scopedWebsiteData: true,
    );
  }

  @override
  bool get supportsOffscreenWebViews => true;

  /// Registers this class as the default instance of [WebViewPlatform].
  static void registerWith() {
    WebViewPlatform.instance = WindowsWebViewPlatform();
  }

  @override
  WindowsWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return WindowsWebViewController(params);
  }

  @override
  WindowsNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return WindowsNavigationDelegate(params);
  }

  @override
  WindowsWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return WindowsWebViewWidget(params);
  }

  @override
  WindowsWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return WindowsWebViewCookieManager(params);
  }

  @override
  WindowsWebViewDataManager createPlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    return WindowsWebViewDataManager(params);
  }
}

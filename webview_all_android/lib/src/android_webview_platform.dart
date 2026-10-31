// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'android_webview_controller.dart';
import 'android_webview_cookie_manager.dart';
import 'android_webview_data_manager.dart';

/// Implementation of [WebViewPlatform] using the WebKit API.
class AndroidWebViewPlatform extends WebViewPlatform {
  @override
  Set<WebViewSessionMode> get supportedSessionModes => const {
    WebViewSessionMode.shared,
    WebViewSessionMode.incognito,
  };

  @override
  bool get supportsOffscreenWebViews => true;

  @override
  Future<WebViewSessionCapabilities>
  getSessionCapabilities() async => WebViewSessionCapabilities(
    canClose: true,
    supportedModes: supportedSessionModes,
    incognitoSupport: WebViewIncognitoSupport.limited,
    privateSessionRestriction:
        "Android disables cache use and form saving and clears this view's history. Cookies and website storage remain shared and persistent; ordinary cookies are not automatically cleared. Independent private stores are unavailable.",
    scopedCookies: true,
    scopedWebsiteData: true,
  );

  /// Registers this class as the default instance of [WebViewPlatform].
  static void registerWith() {
    WebViewPlatform.instance = AndroidWebViewPlatform();
  }

  @override
  AndroidWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return AndroidWebViewController(params);
  }

  @override
  AndroidNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return AndroidNavigationDelegate(params);
  }

  @override
  AndroidWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return AndroidWebViewWidget(params);
  }

  @override
  AndroidWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return AndroidWebViewCookieManager(params);
  }

  @override
  AndroidWebViewDataManager createPlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    return AndroidWebViewDataManager(params);
  }
}

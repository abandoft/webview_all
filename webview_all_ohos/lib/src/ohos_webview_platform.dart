// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'ohos_webview_controller.dart';
import 'ohos_webview_cookie_manager.dart';
import 'ohos_webview_data_manager.dart';

/// Implementation of [WebViewPlatform] using the WebKit API.
class OhosWebViewPlatform extends WebViewPlatform {
  @override
  Set<WebViewSessionMode> get supportedSessionModes => const {
    WebViewSessionMode.shared,
    WebViewSessionMode.incognito,
  };

  @override
  Future<WebViewSessionCapabilities>
  getSessionCapabilities() async => WebViewSessionCapabilities(
    supportedModes: supportedSessionModes,
    canClose: true,
    incognitoSupport: WebViewIncognitoSupport.nativeStore,
    privateSessionRestriction:
        'ArkWeb supports native incognito mode, but private WebViews share the same private store.',
    scopedCookies: true,
    scopedWebsiteData: true,
  );

  /// Registers this class as the default instance of [WebViewPlatform].
  static void registerWith() {
    WebViewPlatform.instance = OhosWebViewPlatform();
  }

  @override
  OhosWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return OhosWebViewController(params);
  }

  @override
  OhosNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return OhosNavigationDelegate(params);
  }

  @override
  OhosWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return OhosWebViewWidget(params);
  }

  @override
  OhosWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return OhosWebViewCookieManager(params);
  }

  @override
  OhosWebViewDataManager createPlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    return OhosWebViewDataManager(params);
  }
}

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

/// App and package facing native API provided by the `webview_all_wkwebview` plugin.
///
/// This class follows the convention of breaking changes of the Dart API, which means that any
/// changes to the class that are not backwards compatible will only be made with a major version
/// change of the plugin. Native code other than this external API does not follow breaking change
/// conventions, so app or plugin clients should not use any other native APIs.
@objc(FWFWebViewFlutterWKWebViewExternalAPI)
public class FWFWebViewFlutterWKWebViewExternalAPI: NSObject {
  /// Retrieves the `WKWebView` that is associated with `identifier`.
  ///
  /// See the Dart method `WebKitWebViewController.webViewIdentifier` to get the identifier of an
  /// underlying `WKWebView`.
  #if os(iOS)
    @available(*, deprecated, message: "Use webView(forIdentifier:withPluginRegistrar:) instead.")
  #endif
  @objc(webViewForIdentifier:withPluginRegistry:)
  public static func webView(
    forIdentifier identifier: Int64, withPluginRegistry registry: FlutterPluginRegistry
  ) -> WKWebView? {
    let plugin = registry.valuePublished(byPlugin: "WebViewFlutterPlugin")
    guard let webviewPlugin = plugin as? WebViewFlutterPlugin else {
      return nil
    }

    return webView(forIdentifier: identifier, withPlugin: webviewPlugin)
  }

  #if os(iOS)
    /// Retrieves the `WKWebView` associated with `identifier` using a plugin registrar.
    ///
    /// Flutter 3.44 and later resolve the published plugin through the registrar directly. Earlier
    /// supported Flutter versions use an engine-scoped compatibility lookup.
    @objc(webViewForIdentifier:withPluginRegistrar:)
    public static func webView(
      forIdentifier identifier: Int64, withPluginRegistrar registrar: FlutterPluginRegistrar
    ) -> WKWebView? {
      guard let webviewPlugin = WebViewFlutterPluginLookup.plugin(publishedBy: registrar) else {
        return nil
      }

      return webView(forIdentifier: identifier, withPlugin: webviewPlugin)
    }
  #endif

  private static func webView(
    forIdentifier identifier: Int64, withPlugin webviewPlugin: WebViewFlutterPlugin
  ) -> WKWebView? {
    let webView: WKWebView? = webviewPlugin.proxyApiRegistrar?.instanceManager.instance(
      forIdentifier: identifier)
    return webView
  }
}

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit
import XCTest

@testable import webview_all_wkwebview

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

class WebviewAllWKWebViewExternalAPITests: XCTestCase {
  func testObjectiveCClassNameUsesPackageNamespace() {
    XCTAssertEqual(
      NSStringFromClass(WebviewAllWKWebViewExternalAPI.self),
      "WebviewAllWKWebViewExternalAPI")
    XCTAssertNil(NSClassFromString("FWFWebViewFlutterWKWebViewExternalAPI"))
  }

  @MainActor func testWebViewForIdentifier() {
    let registry = TestRegistry()

    #if os(iOS)
      let registrar = registry.registrar(forPlugin: "")!
    #elseif os(macOS)
      let registrar = registry.registrar(forPlugin: "")
    #endif

    WebviewAllWKWebViewPlugin.register(with: registrar)

    let plugin = registry.registrar.plugin

    let webView = WKWebView(frame: .zero)
    let webViewIdentifier = 0
    plugin?.proxyApiRegistrar?.instanceManager.addDartCreatedInstance(
      webView, withIdentifier: Int64(webViewIdentifier))

    let result = WebviewAllWKWebViewExternalAPI.webView(
      forIdentifier: Int64(webViewIdentifier), withPluginRegistry: registry)
    XCTAssertEqual(result, webView)
  }

  @MainActor func testWebViewForIdentifierHandlesIncorrectRegistry() {
    let registry = TestRegistry(publishedValue: false)
    // Ensure that passing an empty registry, such as the FlutterAppDelegate
    // in an app that has adopted UIScene, gracefully returns nil.
    let result = WebviewAllWKWebViewExternalAPI.webView(
      forIdentifier: 0, withPluginRegistry: registry)
    XCTAssertEqual(result, nil)
  }

  #if os(iOS)
    @MainActor func testWebViewForIdentifierFromRegistrarUsesOfficialLookup() {
      let registry = TestRegistry()
      let registrar = registry.registrar(forPlugin: "")!

      WebviewAllWKWebViewPlugin.register(with: registrar)

      let plugin = registry.registrar.plugin!
      let webView = WKWebView(frame: .zero)
      let webViewIdentifier = 1
      plugin.proxyApiRegistrar?.instanceManager.addDartCreatedInstance(
        webView, withIdentifier: Int64(webViewIdentifier))

      // Prove this path does not depend on the compatibility lookup.
      WebviewAllWKWebViewPluginLookup.unregister(
        plugin, for: registry.registrar.testBinaryMessenger)

      let result = WebviewAllWKWebViewExternalAPI.webView(
        forIdentifier: Int64(webViewIdentifier), withPluginRegistrar: registrar)
      XCTAssertEqual(result, webView)
    }

    @MainActor func testWebViewForIdentifierFromRegistrarUsesLegacyLookup() {
      let registry = TestRegistry()
      registry.registrar.supportsOfficialPublishedValueLookup = false
      let registrar = registry.registrar(forPlugin: "")!

      WebviewAllWKWebViewPlugin.register(with: registrar)

      let plugin = registry.registrar.plugin!
      let webView = WKWebView(frame: .zero)
      let webViewIdentifier = 2
      plugin.proxyApiRegistrar?.instanceManager.addDartCreatedInstance(
        webView, withIdentifier: Int64(webViewIdentifier))

      let result = WebviewAllWKWebViewExternalAPI.webView(
        forIdentifier: Int64(webViewIdentifier), withPluginRegistrar: registrar)
      XCTAssertEqual(result, webView)
    }

    @MainActor func testWebViewForIdentifierFromRegistrarIsEngineScoped() {
      let registry = TestRegistry()
      registry.registrar.supportsOfficialPublishedValueLookup = false
      WebviewAllWKWebViewPlugin.register(with: registry.registrar(forPlugin: "")!)

      let unrelatedRegistrar = TestFlutterPluginRegistrar()
      unrelatedRegistrar.supportsOfficialPublishedValueLookup = false
      let result = WebviewAllWKWebViewExternalAPI.webView(
        forIdentifier: 0, withPluginRegistrar: unrelatedRegistrar)
      XCTAssertNil(result)
    }

    @MainActor func testLegacyRegistrarLookupIsRemovedDuringTeardown() {
      let registry = TestRegistry()
      registry.registrar.supportsOfficialPublishedValueLookup = false
      let registrar = registry.registrar(forPlugin: "")!
      WebviewAllWKWebViewPlugin.register(with: registrar)

      let plugin = registry.registrar.plugin!
      plugin.detachFromEngine(for: registrar)

      XCTAssertNil(WebviewAllWKWebViewPluginLookup.plugin(publishedBy: registrar))
    }
  #endif
}

class TestRegistry: NSObject, FlutterPluginRegistry {
  let registrar = TestFlutterPluginRegistrar()
  let publishedValue: Bool

  init(publishedValue: Bool) {
    self.publishedValue = publishedValue
  }

  convenience override init() {
    self.init(publishedValue: true)
  }

  #if os(iOS)
    func registrar(forPlugin pluginKey: String) -> FlutterPluginRegistrar? {
      return registrar
    }
  #elseif os(macOS)
    func registrar(forPlugin pluginKey: String) -> FlutterPluginRegistrar {
      return registrar
    }
  #endif

  func hasPlugin(_ pluginKey: String) -> Bool {
    return true
  }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? {
    if publishedValue && pluginKey == "WebviewAllWKWebViewPlugin" {
      return registrar.plugin
    }
    return nil
  }
}

class TestFlutterTextureRegistry: NSObject, FlutterTextureRegistry {
  func register(_ texture: FlutterTexture) -> Int64 {
    return 0
  }

  func textureFrameAvailable(_ textureId: Int64) {

  }

  func unregisterTexture(_ textureId: Int64) {

  }
}

class TestFlutterPluginRegistrar: NSObject, FlutterPluginRegistrar {
  let testBinaryMessenger = TestBinaryMessenger()
  var publishedValue: NSObject?
  var registeredViewType: String?
  var supportsOfficialPublishedValueLookup = true
  var plugin: WebviewAllWKWebViewPlugin? {
    return publishedValue as? WebviewAllWKWebViewPlugin
  }

  #if os(iOS)
    var viewController: UIViewController?
    var sceneDelegate: AnyObject?

    func messenger() -> FlutterBinaryMessenger {
      return testBinaryMessenger
    }

    func textures() -> FlutterTextureRegistry {
      return TestFlutterTextureRegistry()
    }

    func addApplicationDelegate(_ delegate: FlutterPlugin) {

    }

    func register(
      _ factory: FlutterPlatformViewFactory, withId factoryId: String,
      gestureRecognizersBlockingPolicy: FlutterPlatformViewGestureRecognizersBlockingPolicy
    ) {
      registeredViewType = factoryId
    }

    func addSceneDelegate(_ delegate: any FlutterSceneLifeCycleDelegate) {
      sceneDelegate = delegate as AnyObject
    }
  #elseif os(macOS)
    var view: NSView?
    var viewController: NSViewController?

    var messenger: FlutterBinaryMessenger {
      return testBinaryMessenger
    }

    var textures: FlutterTextureRegistry {
      return TestFlutterTextureRegistry()
    }

    func addApplicationDelegate(_ delegate: FlutterAppLifecycleDelegate) {

    }
  #endif

  func register(_ factory: FlutterPlatformViewFactory, withId factoryId: String) {
    registeredViewType = factoryId
  }

  func publish(_ value: NSObject) {
    publishedValue = value
  }

  func addMethodCallDelegate(_ delegate: FlutterPlugin, channel: FlutterMethodChannel) {

  }

  func lookupKey(forAsset asset: String) -> String {
    return ""
  }

  func lookupKey(forAsset asset: String, fromPackage package: String) -> String {
    return ""
  }

  func valuePublished(byPlugin pluginKey: String) -> NSObject? {
    if pluginKey == "WebviewAllWKWebViewPlugin" {
      return publishedValue
    }
    return nil
  }

  override func responds(to aSelector: Selector!) -> Bool {
    if !supportsOfficialPublishedValueLookup
      && aSelector == NSSelectorFromString("valuePublishedByPlugin:")
    {
      return false
    }
    return super.responds(to: aSelector)
  }
}

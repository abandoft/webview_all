// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

@testable import webview_all_wkwebview

#if os(iOS)
  import Flutter
  import UIKit
#endif

class WebviewAllWKWebViewPluginTests: XCTestCase {
  #if os(iOS)
    @MainActor func testRegisterAddsSceneLifeCycleDelegateWhenSupported() {
      let registry = TestRegistry()
      let registrar = registry.registrar(forPlugin: "")!

      WebviewAllWKWebViewPlugin.register(with: registrar)

      let plugin = registry.registrar.plugin!
      XCTAssertEqual(
        registry.registrar.registeredViewType,
        "com.abandoft.webview_all_wkwebview/webview")
      XCTAssertTrue(registry.registrar.sceneDelegate === plugin)
      let sceneLifeCycleProtocol = NSProtocolFromString("FlutterSceneLifeCycleDelegate")
      XCTAssertNotNil(sceneLifeCycleProtocol)
      XCTAssertTrue(plugin.conforms(to: sceneLifeCycleProtocol!))
    }

    func testApplicationTerminationReleasesTheInstanceManager() {
      let plugin = WebviewAllWKWebViewPlugin(binaryMessenger: TestBinaryMessenger())
      let view = UIView()
      _ = plugin.proxyApiRegistrar!.instanceManager.addHostCreatedInstance(view)

      (plugin as FlutterApplicationLifeCycleDelegate).applicationWillTerminate!(
        UIApplication.shared)

      XCTAssertNil(plugin.proxyApiRegistrar)

      // Application and engine lifecycle callbacks may race during shutdown.
      // A repeated callback must remain harmless.
      (plugin as FlutterApplicationLifeCycleDelegate).applicationWillTerminate!(
        UIApplication.shared)
      XCTAssertNil(plugin.proxyApiRegistrar)
    }
  #endif
}

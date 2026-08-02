// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

@testable import webview_all_wkwebview

#if os(iOS)
  import Flutter
  import UIKit
#endif

class WebViewFlutterPluginTests: XCTestCase {
  #if os(iOS)
    @MainActor func testRegisterAddsSceneLifeCycleDelegateWhenSupported() {
      let registry = TestRegistry()
      let registrar = registry.registrar(forPlugin: "")!

      WebViewFlutterPlugin.register(with: registrar)

      let plugin = registry.registrar.plugin!
      XCTAssertTrue(registry.registrar.sceneDelegate === plugin)
      let sceneLifeCycleProtocol = NSProtocolFromString("FlutterSceneLifeCycleDelegate")
      XCTAssertNotNil(sceneLifeCycleProtocol)
      XCTAssertTrue(plugin.conforms(to: sceneLifeCycleProtocol!))
    }

    func testApplicationTerminationReleasesTheInstanceManager() {
      let plugin = WebViewFlutterPlugin(binaryMessenger: TestBinaryMessenger())
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

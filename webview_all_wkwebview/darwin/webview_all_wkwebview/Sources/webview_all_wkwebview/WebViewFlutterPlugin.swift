// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import Flutter
  import ObjectiveC
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
#else
  #error("Unsupported platform.")
#endif

public class WebViewFlutterPlugin: NSObject, FlutterPlugin {
  var proxyApiRegistrar: ProxyAPIRegistrar?
  #if os(iOS)
    private weak var compatibilityBinaryMessenger: AnyObject?
  #endif

  init(binaryMessenger: FlutterBinaryMessenger) {
    proxyApiRegistrar = ProxyAPIRegistrar(
      binaryMessenger: binaryMessenger)
    proxyApiRegistrar?.setUp()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let binaryMessenger = registrar.messenger()
    #else
      let binaryMessenger = registrar.messenger
    #endif
    let plugin = WebViewFlutterPlugin(binaryMessenger: binaryMessenger)

    let viewFactory = FlutterViewFactory(instanceManager: plugin.proxyApiRegistrar!.instanceManager)
    #if os(iOS)
      plugin.registerForCompatibilityLookup(binaryMessenger: binaryMessenger)
      registrar.addApplicationDelegate(plugin)
      plugin.registerForSceneLifeCycle(with: registrar)
    #endif
    registrar.register(viewFactory, withId: "plugins.flutter.io/webview")
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    tearDownProxyAPIRegistrar()
  }

  private func tearDownProxyAPIRegistrar() {
    #if os(iOS)
      if let compatibilityBinaryMessenger {
        WebViewFlutterPluginLookup.unregister(self, for: compatibilityBinaryMessenger)
        self.compatibilityBinaryMessenger = nil
      }
    #endif
    proxyApiRegistrar?.ignoreCallsToDart = true
    proxyApiRegistrar?.tearDown()
    try? proxyApiRegistrar?.instanceManager.removeAllObjects()
    proxyApiRegistrar = nil
  }
}

#if os(iOS)
  extension WebViewFlutterPlugin: FlutterApplicationLifeCycleDelegate {
    public func applicationWillTerminate(_ application: UIApplication) {
      tearDownProxyAPIRegistrar()
    }

    @objc(sceneDidDisconnect:)
    public func sceneDidDisconnect(_ scene: UIScene) {
      tearDownProxyAPIRegistrar()
    }

    private func registerForCompatibilityLookup(binaryMessenger: FlutterBinaryMessenger) {
      let messengerObject = binaryMessenger as AnyObject
      compatibilityBinaryMessenger = messengerObject
      WebViewFlutterPluginLookup.register(self, for: binaryMessenger)
    }

    private func registerForSceneLifeCycle(with registrar: FlutterPluginRegistrar) {
      let addSceneDelegateSelector = NSSelectorFromString("addSceneDelegate:")
      guard
        let registrarObject = registrar as? NSObject,
        registrarObject.responds(to: addSceneDelegateSelector),
        let sceneLifeCycleProtocol = NSProtocolFromString("FlutterSceneLifeCycleDelegate")
      else {
        return
      }

      if !class_conformsToProtocol(WebViewFlutterPlugin.self, sceneLifeCycleProtocol) {
        _ = class_addProtocol(WebViewFlutterPlugin.self, sceneLifeCycleProtocol)
      }
      guard class_conformsToProtocol(WebViewFlutterPlugin.self, sceneLifeCycleProtocol) else {
        return
      }

      registrarObject.perform(addSceneDelegateSelector, with: self)
    }
  }
#endif

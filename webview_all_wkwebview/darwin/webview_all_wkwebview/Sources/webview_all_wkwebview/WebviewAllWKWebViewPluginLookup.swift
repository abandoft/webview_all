// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#if os(iOS)
  import Flutter
  import Foundation

  private final class WebviewAllWKWebViewPluginLookupEntry {
    weak var binaryMessenger: AnyObject?
    weak var plugin: WebviewAllWKWebViewPlugin?

    init(binaryMessenger: AnyObject, plugin: WebviewAllWKWebViewPlugin) {
      self.binaryMessenger = binaryMessenger
      self.plugin = plugin
    }
  }

  /// Resolves the plugin published by a registrar on every supported Flutter version.
  ///
  /// Flutter 3.44 added `valuePublishedByPlugin:` to `FlutterPluginRegistrar`. Earlier engines
  /// expose the same binary messenger to every registrar belonging to an engine, so a weak,
  /// messenger-scoped lookup preserves engine isolation without extending either object's lifetime.
  enum WebviewAllWKWebViewPluginLookup {
    private static let lock = NSLock()
    private static var entries: [ObjectIdentifier: WebviewAllWKWebViewPluginLookupEntry] = [:]
    private static let valuePublishedSelector = NSSelectorFromString("valuePublishedByPlugin:")

    static func register(
      _ plugin: WebviewAllWKWebViewPlugin, for binaryMessenger: FlutterBinaryMessenger
    ) {
      let messengerObject = binaryMessenger as AnyObject
      let identifier = ObjectIdentifier(messengerObject)

      lock.lock()
      defer { lock.unlock() }
      removeExpiredEntries()
      entries[identifier] = WebviewAllWKWebViewPluginLookupEntry(
        binaryMessenger: messengerObject, plugin: plugin)
    }

    static func unregister(
      _ plugin: WebviewAllWKWebViewPlugin, for binaryMessenger: AnyObject
    ) {
      let identifier = ObjectIdentifier(binaryMessenger)

      lock.lock()
      defer { lock.unlock() }
      guard
        let entry = entries[identifier],
        entry.binaryMessenger === binaryMessenger,
        entry.plugin === plugin
      else {
        return
      }
      entries.removeValue(forKey: identifier)
    }

    static func plugin(
      publishedBy registrar: FlutterPluginRegistrar
    ) -> WebviewAllWKWebViewPlugin? {
      if let plugin = pluginFromOfficialRegistrarAPI(registrar) {
        return plugin
      }
      return compatibilityPlugin(for: registrar.messenger())
    }

    private static func pluginFromOfficialRegistrarAPI(
      _ registrar: FlutterPluginRegistrar
    ) -> WebviewAllWKWebViewPlugin? {
      guard
        let registrarObject = registrar as? NSObject,
        registrarObject.responds(to: valuePublishedSelector),
        let publishedValue = registrarObject.perform(
          valuePublishedSelector, with: "WebviewAllWKWebViewPlugin"
        )?.takeUnretainedValue()
      else {
        return nil
      }
      return publishedValue as? WebviewAllWKWebViewPlugin
    }

    private static func compatibilityPlugin(
      for binaryMessenger: FlutterBinaryMessenger
    ) -> WebviewAllWKWebViewPlugin? {
      let messengerObject = binaryMessenger as AnyObject
      let identifier = ObjectIdentifier(messengerObject)

      lock.lock()
      defer { lock.unlock() }
      guard
        let entry = entries[identifier],
        entry.binaryMessenger === messengerObject
      else {
        entries.removeValue(forKey: identifier)
        return nil
      }
      guard let plugin = entry.plugin else {
        entries.removeValue(forKey: identifier)
        return nil
      }
      return plugin
    }

    private static func removeExpiredEntries() {
      entries = entries.filter {
        $0.value.binaryMessenger != nil && $0.value.plugin != nil
      }
    }
  }
#endif

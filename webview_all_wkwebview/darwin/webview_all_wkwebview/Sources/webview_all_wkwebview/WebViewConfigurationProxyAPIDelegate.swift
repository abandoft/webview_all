// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

/// ProxyApi implementation for `WKWebViewConfiguration`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class WebViewConfigurationProxyAPIDelegate: PigeonApiDelegateWKWebViewConfiguration {
  func setCustomSchemes(
    pigeonApi: PigeonApiWKWebViewConfiguration,
    pigeonInstance: WKWebViewConfiguration, schemes: [String]
  ) throws {
    guard schemes.count <= 16,
      schemes.allSatisfy({
        $0.range(of: "^[a-z][a-z0-9+.-]{0,31}$", options: .regularExpression) != nil
          && !WKWebView.handlesURLScheme($0)
          && !["webview-all-resource", "javascript", "blob", "ws", "wss"].contains($0)
      })
    else {
      throw PigeonError(
        code: "invalid_scheme", message: "A custom scheme is invalid or owned by the engine.",
        details: nil)
    }
    ResourceSchemeHandler.installCustom(schemes, on: pigeonInstance)
  }
  func pigeonDefaultConstructor(pigeonApi: PigeonApiWKWebViewConfiguration) throws
    -> WKWebViewConfiguration
  {
    return WKWebViewConfiguration()
  }

  func setUserContentController(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration,
    controller: WKUserContentController
  ) throws {
    pigeonInstance.userContentController = controller
  }

  func getUserContentController(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration
  ) throws -> WKUserContentController {
    return pigeonInstance.userContentController
  }

  func setWebsiteDataStore(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration,
    dataStore: WKWebsiteDataStore
  ) throws {
    pigeonInstance.websiteDataStore = dataStore
    BrowserProfiles.track(pigeonInstance, store: dataStore, manager: pigeonApi.pigeonRegistrar.instanceManager)
  }

  func getWebsiteDataStore(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration
  ) throws -> WKWebsiteDataStore {
    let store = pigeonInstance.websiteDataStore
    BrowserProfiles.track(store, store: store, manager: pigeonApi.pigeonRegistrar.instanceManager)
    BrowserProfiles.track(pigeonInstance, store: store, manager: pigeonApi.pigeonRegistrar.instanceManager)
    return store
  }

  func setPreferences(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration,
    preferences: WKPreferences
  ) throws {
    pigeonInstance.preferences = preferences
  }

  func getPreferences(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration
  ) throws -> WKPreferences {
    return pigeonInstance.preferences
  }

  func setAllowsInlineMediaPlayback(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration, allow: Bool
  ) throws {
    #if !os(macOS)
      pigeonInstance.allowsInlineMediaPlayback = allow
    #endif
    // No-op, rather than error out, on macOS, since it's not a meaningful option on macOS and it's
    // easier for clients if it's just ignored.
  }

  func setLimitsNavigationsToAppBoundDomains(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration, limit: Bool
  ) throws -> Bool {
    if #available(iOS 14.0, macOS 11.0, *) {
      pigeonInstance.limitsNavigationsToAppBoundDomains = limit
      return true
    } else {
      return false
    }
  }

  func setMediaTypesRequiringUserActionForPlayback(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration,
    type: AudiovisualMediaType
  ) throws {
    switch type {
    case .none:
      pigeonInstance.mediaTypesRequiringUserActionForPlayback = []
    case .audio:
      pigeonInstance.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.audio
    case .video:
      pigeonInstance.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.video
    case .all:
      pigeonInstance.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.all
    }
  }

  func getDefaultWebpagePreferences(
    pigeonApi: PigeonApiWKWebViewConfiguration, pigeonInstance: WKWebViewConfiguration
  ) throws -> WKWebpagePreferences {
    return pigeonInstance.defaultWebpagePreferences
  }
}

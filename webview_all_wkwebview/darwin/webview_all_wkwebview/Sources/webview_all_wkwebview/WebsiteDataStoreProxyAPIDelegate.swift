// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

/// ProxyApi implementation for `WKWebsiteDataStore`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class WebsiteDataStoreProxyAPIDelegate: PigeonApiDelegateWKWebsiteDataStore {
  func named(pigeonApi: PigeonApiWKWebsiteDataStore, name: String) throws -> WKWebsiteDataStore {
    guard name.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil else {
      throw PigeonError(code: "invalid_profile", message: "Invalid profile name.", details: nil)
    }
    if #available(iOS 17.0, macOS 14.0, *) {
      return try BrowserProfiles.store(name, manager: pigeonApi.pigeonRegistrar.instanceManager)
    }
    throw PigeonError(
      code: "unsupported_profile", message: "Named stores require iOS 17 or macOS 14.", details: nil
    )
  }
  func nonPersistent(pigeonApi: PigeonApiWKWebsiteDataStore) throws -> WKWebsiteDataStore {
    return WKWebsiteDataStore.nonPersistent()
  }

  func defaultDataStore(pigeonApi: PigeonApiWKWebsiteDataStore) -> WKWebsiteDataStore {
    return WKWebsiteDataStore.default()
  }

  func httpCookieStore(pigeonApi: PigeonApiWKWebsiteDataStore, pigeonInstance: WKWebsiteDataStore)
    -> WKHTTPCookieStore
  {
    let cookies = pigeonInstance.httpCookieStore
    BrowserProfiles.track(cookies, store: pigeonInstance, manager: pigeonApi.pigeonRegistrar.instanceManager)
    return cookies
  }

  func removeDataOfTypes(
    pigeonApi: PigeonApiWKWebsiteDataStore, pigeonInstance: WKWebsiteDataStore,
    dataTypes: [WebsiteDataType], modificationTimeInSecondsSinceEpoch: Double,
    completion: @escaping (Result<Bool, Error>) -> Void
  ) {
    let nativeDataTypes = Set(
      dataTypes.map {
        switch $0 {
        case .cookies:
          return WKWebsiteDataTypeCookies
        case .memoryCache:
          return WKWebsiteDataTypeMemoryCache
        case .diskCache:
          return WKWebsiteDataTypeDiskCache
        case .offlineWebApplicationCache:
          return WKWebsiteDataTypeOfflineWebApplicationCache
        case .localStorage:
          return WKWebsiteDataTypeLocalStorage
        case .sessionStorage:
          return WKWebsiteDataTypeSessionStorage
        case .webSQLDatabases:
          return WKWebsiteDataTypeWebSQLDatabases
        case .indexedDBDatabases:
          return WKWebsiteDataTypeIndexedDBDatabases
        case .fetchCache:
          return WKWebsiteDataTypeFetchCache
        case .serviceWorkerRegistrations:
          return WKWebsiteDataTypeServiceWorkerRegistrations
        }
      })

    pigeonInstance.fetchDataRecords(ofTypes: nativeDataTypes) { records in
      if records.isEmpty {
        completion(.success(false))
      } else {
        pigeonInstance.removeData(
          ofTypes: nativeDataTypes,
          modifiedSince: Date(timeIntervalSince1970: modificationTimeInSecondsSinceEpoch)
        ) {
          completion(.success(true))
        }
      }
    }
  }
}

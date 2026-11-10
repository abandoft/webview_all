// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import XCTest

@testable import webview_all_wkwebview

class HTTPCookieProxyAPITests: XCTestCase {
  func testPigeonDefaultConstructor() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiHTTPCookie(registrar)

    let instance = try? api.pigeonDelegate.pigeonDefaultConstructor(
      pigeonApi: api,
      properties: [.name: "foo", .value: "bar", .domain: "http://google.com", .path: "/anything"])
    XCTAssertNotNil(instance)
  }

  func testCookieExpiryAndSecurityMetadata() throws {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiHTTPCookie(registrar)
    let expiry = floor(Date().timeIntervalSince1970 + 3600) * 1000
    let cookie = try api.pigeonDelegate.pigeonDefaultConstructor(
      pigeonApi: api,
      properties: [
        .name: "session", .value: "v", .domain: "example.test", .path: "/",
        .expires: expiry, .secure: "TRUE", .httpOnly: "TRUE", .sameSitePolicy: "lax",
      ])
    XCTAssertTrue(cookie.isSecure)
    XCTAssertTrue(cookie.isHTTPOnly)
    XCTAssertEqual(cookie.expiresDate!.timeIntervalSince1970 * 1000, expiry, accuracy: 1)
    let properties = try api.pigeonDelegate.getProperties(pigeonApi: api, pigeonInstance: cookie)
    XCTAssertEqual(properties?[.expires] as? Double, expiry)
    XCTAssertEqual(properties?[.secure] as? Bool, true)
    XCTAssertEqual(properties?[.httpOnly] as? Bool, true)
    XCTAssertEqual(properties?[.discard] as? Bool, false)
  }

  func testGetProperties() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiHTTPCookie(registrar)

    let instance = HTTPCookie(properties: [
      .name: "foo", .value: "bar", .domain: "http://google.com", .path: "/anything",
    ])!
    let value = try? api.pigeonDelegate.getProperties(pigeonApi: api, pigeonInstance: instance)

    XCTAssertEqual(value?[.name] as? String, "foo")
    XCTAssertEqual(value?[.value] as? String, "bar")
    XCTAssertEqual(value?[.domain] as? String, "http://google.com")
    XCTAssertEqual(value?[.path] as? String, "/anything")
  }
}

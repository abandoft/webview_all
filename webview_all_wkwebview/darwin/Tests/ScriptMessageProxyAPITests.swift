// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit
import XCTest

@testable import webview_all_wkwebview

class ScriptMessageProxyAPITests: XCTestCase {
  @MainActor func testName() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiWKScriptMessage(registrar)

    let instance = TestScriptMessage.instance
    let value = try? api.pigeonDelegate.name(pigeonApi: api, pigeonInstance: instance)

    XCTAssertEqual(value, instance.name)
  }

  @MainActor func testBody() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiWKScriptMessage(registrar)

    let instance = TestScriptMessage.instance
    let value = try? api.pigeonDelegate.body(pigeonApi: api, pigeonInstance: instance)

    XCTAssertEqual(value as! Int, 23)
  }

  @MainActor func testFrameInfo() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiWKScriptMessage(registrar)
    let instance = TestScriptMessage.instance
    let value = try? api.pigeonDelegate.frameInfo(pigeonApi: api, pigeonInstance: instance)
    XCTAssertIdentical(value, TestFrameInfo.instance)
  }
}

class TestScriptMessage: WKScriptMessage {
  // WebKit can crash while deallocating a manually constructed message on newer OS versions.
  static let instance = TestScriptMessage()

  private override init() {}

  override var name: String {
    return "myString"
  }

  override var body: Any {
    return NSNumber(integerLiteral: 23)
  }

  override var frameInfo: WKFrameInfo {
    return TestFrameInfo.instance
  }
}

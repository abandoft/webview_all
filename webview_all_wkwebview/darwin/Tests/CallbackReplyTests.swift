// Copyright 2026 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit
import XCTest

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

@testable import webview_all_wkwebview

class CallbackReplyTests: XCTestCase {
  @MainActor func testNavigationActionRejectsNullAndEmptyReplies() {
    assertInvalidReplies { registrar, completion in
      let api = registrar.apiDelegate.pigeonApiWKNavigationDelegate(registrar)
      let delegate = NavigationDelegateImpl(api: api, registrar: registrar)
      _ = registrar.instanceManager.addHostCreatedInstance(delegate)
      api.decidePolicyForNavigationAction(
        pigeonInstance: delegate, webView: WKWebView(frame: .zero),
        navigationAction: TestNavigationAction(), completion: completion)
    }
  }

  @MainActor func testNavigationResponseRejectsNullAndEmptyReplies() {
    assertInvalidReplies { registrar, completion in
      let api = registrar.apiDelegate.pigeonApiWKNavigationDelegate(registrar)
      let delegate = NavigationDelegateImpl(api: api, registrar: registrar)
      _ = registrar.instanceManager.addHostCreatedInstance(delegate)
      api.decidePolicyForNavigationResponse(
        pigeonInstance: delegate, webView: WKWebView(frame: .zero),
        navigationResponse: TestNavigationResponse.instance, completion: completion)
    }
  }

  @MainActor func testAuthenticationChallengeRejectsNullAndEmptyReplies() {
    assertInvalidReplies { registrar, completion in
      let api = registrar.apiDelegate.pigeonApiWKNavigationDelegate(registrar)
      let delegate = NavigationDelegateImpl(api: api, registrar: registrar)
      _ = registrar.instanceManager.addHostCreatedInstance(delegate)
      let challenge = URLAuthenticationChallenge(
        protectionSpace: URLProtectionSpace(), proposedCredential: nil,
        previousFailureCount: 0, failureResponse: nil, error: nil,
        sender: TestURLAuthenticationChallengeSender())
      api.didReceiveAuthenticationChallenge(
        pigeonInstance: delegate, webView: WKWebView(frame: .zero),
        challenge: challenge, completion: completion)
    }
  }

  @MainActor func testMediaPermissionRejectsNullAndEmptyReplies() {
    assertInvalidReplies { registrar, completion in
      let api = registrar.apiDelegate.pigeonApiWKUIDelegate(registrar)
      let delegate = UIDelegateImpl(api: api, registrar: registrar)
      _ = registrar.instanceManager.addHostCreatedInstance(delegate)
      api.requestMediaCapturePermission(
        pigeonInstance: delegate, webView: WKWebView(frame: .zero),
        origin: SecurityOriginProxyAPITests.testSecurityOrigin,
        frame: TestFrameInfo.instance, type: .camera, completion: completion)
    }
  }

  @MainActor func testJavaScriptConfirmRejectsNullAndEmptyReplies() {
    assertInvalidReplies { registrar, completion in
      let api = registrar.apiDelegate.pigeonApiWKUIDelegate(registrar)
      let delegate = UIDelegateImpl(api: api, registrar: registrar)
      _ = registrar.instanceManager.addHostCreatedInstance(delegate)
      api.runJavaScriptConfirmPanel(
        pigeonInstance: delegate, webView: WKWebView(frame: .zero), message: "confirm",
        frame: TestFrameInfo.instance, completion: completion)
    }
  }

  @MainActor func testJavaScriptConfirmStillAcceptsFalse() {
    let messenger = CallbackReplyMessenger(reply: [false])
    let registrar = ProxyAPIRegistrar(binaryMessenger: messenger)
    let api = registrar.apiDelegate.pigeonApiWKUIDelegate(registrar)
    let delegate = UIDelegateImpl(api: api, registrar: registrar)
    _ = registrar.instanceManager.addHostCreatedInstance(delegate)
    let replied = expectation(description: "The confirm reply is decoded")
    api.runJavaScriptConfirmPanel(
      pigeonInstance: delegate, webView: WKWebView(frame: .zero), message: "confirm",
      frame: TestFrameInfo.instance
    ) { result in
      switch result {
      case .success(let value): XCTAssertFalse(value)
      case .failure(let error): XCTFail("Unexpected failure: \(error)")
      }
      replied.fulfill()
    }
    wait(for: [replied], timeout: 1)
  }

  @MainActor private func assertInvalidReplies<Value>(
    _ invoke: (ProxyAPIRegistrar, @escaping (Result<Value, PigeonError>) -> Void) -> Void,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    // Use the actual message codec: NSNull inside an array must not reach a
    // forced Swift cast, even though it is distinct from Optional.none.
    for reply: [Any] in [[NSNull()], []] {
      let messenger = CallbackReplyMessenger(reply: reply)
      let registrar = ProxyAPIRegistrar(binaryMessenger: messenger)
      let replied = expectation(description: "The malformed reply is rejected")
      invoke(registrar) { result in
        switch result {
        case .success: XCTFail("A malformed reply was accepted", file: file, line: line)
        case .failure(let error): XCTAssertEqual(error.code, "null-error", file: file, line: line)
        }
        replied.fulfill()
      }
      wait(for: [replied], timeout: 1)
    }
  }
}

private class CallbackReplyMessenger: TestBinaryMessenger {
  let reply: [Any]

  init(reply: [Any]) {
    self.reply = reply
  }

  override func send(
    onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil
  ) {
    callback?(FlutterStandardMessageCodec.sharedInstance().encode(reply))
  }
}

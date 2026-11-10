// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit
import XCTest

@testable import webview_all_wkwebview

class UIDelegateProxyAPITests: XCTestCase {
  func testPigeonDefaultConstructor() {
    let registrar = TestProxyApiRegistrar()
    let api = registrar.apiDelegate.pigeonApiWKUIDelegate(registrar)

    let instance = try? api.pigeonDelegate.pigeonDefaultConstructor(pigeonApi: api)
    XCTAssertNotNil(instance)
  }

  #if os(macOS) || compiler(>=6.1)
    @available(iOS 18.4, macOS 11.0, *)
    @MainActor func testFileSelectorPreservesDefaultsAndFiltersResults() throws {
      let api = TestDelegateApi()
      let registrar = TestProxyApiRegistrar()
      let instance = UIDelegateImpl(api: api, registrar: registrar)
      let selector = NSSelectorFromString(
        "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:")
      XCTAssertFalse(instance.responds(to: selector))
      instance.fileSelectorEnabled = true
      XCTAssertTrue(instance.responds(to: selector))
      let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try Data([1, 2, 3]).write(to: file)
      defer { try? FileManager.default.removeItem(at: file) }
      api.fileSelection = ["https://example.test/file", file.path, file.path]
      let completed = expectation(description: "file selection")
      instance.webView(
        WKWebView(frame: .zero), runOpenPanelWith: TestOpenPanelParameters(),
        initiatedByFrame: TestFrameInfo.instance
      ) { urls in
        XCTAssertEqual(urls, [file])
        completed.fulfill()
      }
      wait(for: [completed], timeout: 2)
      XCTAssertEqual(api.fileSelectorArgs, [false, false])
    }

    @available(iOS 18.4, macOS 11.0, *)
    @MainActor func testCancelledFileSelectorIgnoresLateResult() {
      let api = TestDelegateApi()
      api.holdFileSelection = true
      let registrar = TestProxyApiRegistrar()
      let instance = UIDelegateImpl(api: api, registrar: registrar)
      instance.fileSelectorEnabled = true
      let completed = expectation(description: "cancelled file selection")
      var completions = 0
      instance.webView(
        WKWebView(frame: .zero), runOpenPanelWith: TestOpenPanelParameters(),
        initiatedByFrame: TestFrameInfo.instance
      ) { urls in
        completions += 1
        XCTAssertNil(urls)
        completed.fulfill()
      }
      instance.cancelFileSelections()
      api.fileSelectorCompletion?(.success(["/late-result"]))
      wait(for: [completed], timeout: 2)
      XCTAssertEqual(completions, 1)
    }
  #endif

  @MainActor func testOnCreateWebView() {
    let api = TestDelegateApi()
    let registrar = TestProxyApiRegistrar()
    let instance = UIDelegateImpl(api: api, registrar: registrar)
    let webView = WKWebView(frame: .zero)
    let configuration = WKWebViewConfiguration()
    let navigationAction = TestNavigationAction()

    let result = instance.webView(
      webView, createWebViewWith: configuration, for: navigationAction,
      windowFeatures: WKWindowFeatures())

    XCTAssertEqual(api.onCreateWebViewArgs, [webView, configuration, navigationAction])
    XCTAssertNil(result)
  }

  @available(iOS 15.0, macOS 12.0, *)
  @MainActor func testRequestMediaCapturePermission() {
    let api = TestDelegateApi()
    let registrar = TestProxyApiRegistrar()
    let instance = UIDelegateImpl(api: api, registrar: registrar)
    let webView = WKWebView(frame: .zero)
    let origin = SecurityOriginProxyAPITests.testSecurityOrigin
    let frame = TestFrameInfo.instance
    let type: WKMediaCaptureType = .camera

    var resultDecision: WKPermissionDecision?
    let callbackExpectation = expectation(description: "Wait for callback.")
    instance.webView(
      webView, requestMediaCapturePermissionFor: origin, initiatedByFrame: frame, type: type
    ) { decision in
      resultDecision = decision
      callbackExpectation.fulfill()
    }

    wait(for: [callbackExpectation], timeout: 1.0)

    XCTAssertEqual(
      api.requestMediaCapturePermissionArgs, [webView, origin, frame, MediaCaptureType.camera])
    XCTAssertEqual(resultDecision, .prompt)
  }

  @MainActor func testRunJavaScriptAlertPanel() {
    let api = TestDelegateApi()
    let registrar = TestProxyApiRegistrar()
    let instance = UIDelegateImpl(api: api, registrar: registrar)
    let webView = WKWebView(frame: .zero)
    let message = "myString"
    let frame = TestFrameInfo.instance

    instance.webView(webView, runJavaScriptAlertPanelWithMessage: message, initiatedByFrame: frame)
    {
    }

    XCTAssertEqual(api.runJavaScriptAlertPanelArgs, [webView, message, frame])
  }

  @MainActor func testRunJavaScriptConfirmPanel() {
    let api = TestDelegateApi()
    let registrar = TestProxyApiRegistrar()
    let instance = UIDelegateImpl(api: api, registrar: registrar)
    let webView = WKWebView(frame: .zero)
    let message = "myString"
    let frame = TestFrameInfo.instance

    var confirmedResult: Bool?
    let callbackExpectation = expectation(description: "Wait for callback.")
    instance.webView(
      webView, runJavaScriptConfirmPanelWithMessage: message, initiatedByFrame: frame
    ) { confirmed in
      confirmedResult = confirmed
      callbackExpectation.fulfill()
    }

    wait(for: [callbackExpectation], timeout: 1.0)

    XCTAssertEqual(api.runJavaScriptConfirmPanelArgs, [webView, message, frame])
    XCTAssertEqual(confirmedResult, true)
  }

  @MainActor func testRunJavaScriptTextInputPanel() {
    let api = TestDelegateApi()
    let registrar = TestProxyApiRegistrar()
    let instance = UIDelegateImpl(api: api, registrar: registrar)
    let webView = WKWebView(frame: .zero)
    let prompt = "myString"
    let defaultText = "myString3"
    let frame = TestFrameInfo.instance

    var inputResult: String?
    let callbackExpectation = expectation(description: "Wait for callback.")
    instance.webView(
      webView, runJavaScriptTextInputPanelWithPrompt: prompt, defaultText: defaultText,
      initiatedByFrame: frame
    ) { input in
      inputResult = input
      callbackExpectation.fulfill()
    }

    wait(for: [callbackExpectation], timeout: 1.0)

    XCTAssertEqual(api.runJavaScriptTextInputPanelArgs, [webView, prompt, defaultText, frame])
    XCTAssertEqual(inputResult, "myString2")
  }
}

class TestDelegateApi: PigeonApiProtocolWKUIDelegate {
  var onCreateWebViewArgs: [AnyHashable?]? = nil
  var requestMediaCapturePermissionArgs: [AnyHashable?]? = nil
  var runJavaScriptAlertPanelArgs: [AnyHashable?]? = nil
  var runJavaScriptConfirmPanelArgs: [AnyHashable?]? = nil
  var runJavaScriptTextInputPanelArgs: [AnyHashable?]? = nil

  var fileSelection: [String]? = nil
  var holdFileSelection = false
  var fileSelectorArgs: [Bool]? = nil
  var fileSelectorCompletion: ((Result<[String]?, PigeonError>) -> Void)?

  func onFileSelector(
    pigeonInstance: WKUIDelegate, multiple: Bool, directories: Bool,
    completion: @escaping (Result<[String]?, PigeonError>) -> Void
  ) {
    fileSelectorArgs = [multiple, directories]
    if holdFileSelection {
      fileSelectorCompletion = completion
    } else {
      completion(.success(fileSelection))
    }
  }

  func onCreateWebView(
    pigeonInstance pigeonInstanceArg: WKUIDelegate, webView webViewArg: WKWebView,
    configuration configurationArg: WKWebViewConfiguration,
    navigationAction navigationActionArg: WKNavigationAction,
    completion: @escaping (Result<Void, PigeonError>) -> Void
  ) {
    onCreateWebViewArgs = [webViewArg, configurationArg, navigationActionArg]
  }

  func requestMediaCapturePermission(
    pigeonInstance pigeonInstanceArg: WKUIDelegate, webView webViewArg: WKWebView,
    origin originArg: WKSecurityOrigin, frame frameArg: WKFrameInfo, type typeArg: MediaCaptureType,
    completion: @escaping (Result<PermissionDecision, PigeonError>) -> Void
  ) {
    requestMediaCapturePermissionArgs = [webViewArg, originArg, frameArg, typeArg]
    completion(.success(.prompt))
  }

  func runJavaScriptAlertPanel(
    pigeonInstance pigeonInstanceArg: WKUIDelegate, webView webViewArg: WKWebView,
    message messageArg: String, frame frameArg: WKFrameInfo,
    completion: @escaping (Result<Void, PigeonError>) -> Void
  ) {
    runJavaScriptAlertPanelArgs = [webViewArg, messageArg, frameArg]
  }

  func runJavaScriptConfirmPanel(
    pigeonInstance pigeonInstanceArg: WKUIDelegate, webView webViewArg: WKWebView,
    message messageArg: String, frame frameArg: WKFrameInfo,
    completion: @escaping (Result<Bool, PigeonError>) -> Void
  ) {
    runJavaScriptConfirmPanelArgs = [webViewArg, messageArg, frameArg]
    completion(.success(true))
  }

  func runJavaScriptTextInputPanel(
    pigeonInstance pigeonInstanceArg: WKUIDelegate, webView webViewArg: WKWebView,
    prompt promptArg: String, defaultText defaultTextArg: String?, frame frameArg: WKFrameInfo,
    completion: @escaping (Result<String?, PigeonError>) -> Void
  ) {
    runJavaScriptTextInputPanelArgs = [webViewArg, promptArg, defaultTextArg, frameArg]
    completion(.success("myString2"))
  }
}

#if os(macOS) || compiler(>=6.1)
  @available(iOS 18.4, macOS 11.0, *)
  private class TestOpenPanelParameters: WKOpenPanelParameters {
    override var allowsMultipleSelection: Bool { false }
    override var allowsDirectories: Bool { false }
  }
#endif

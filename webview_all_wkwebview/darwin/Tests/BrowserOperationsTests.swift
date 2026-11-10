import WebKit
import XCTest

@testable import webview_all_wkwebview

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

final class BrowserOperationsTests: XCTestCase {
  @MainActor func testNavigationStateMatchesProfilesWithoutMergingPrivateStores() {
    let privateStore = WKWebsiteDataStore.nonPersistent()
    XCTAssertTrue(BrowserOperationsChannel.canRestoreBetween(privateStore, privateStore))
    XCTAssertFalse(BrowserOperationsChannel.canRestoreBetween(privateStore, .nonPersistent()))
    XCTAssertFalse(BrowserOperationsChannel.canRestoreBetween(privateStore, .default()))
    XCTAssertTrue(BrowserOperationsChannel.canRestoreBetween(.default(), .default()))
    if #available(iOS 17.0, macOS 14.0, *) {
      let identifier = UUID()
      let otherIdentifier = UUID()
      defer {
        WKWebsiteDataStore.remove(forIdentifier: identifier) { _ in }
        WKWebsiteDataStore.remove(forIdentifier: otherIdentifier) { _ in }
      }
      let named = WKWebsiteDataStore(forIdentifier: identifier)
      XCTAssertTrue(
        BrowserOperationsChannel.canRestoreBetween(
          named, WKWebsiteDataStore(forIdentifier: identifier)))
      XCTAssertFalse(
        BrowserOperationsChannel.canRestoreBetween(
          named, WKWebsiteDataStore(forIdentifier: otherIdentifier)))
      XCTAssertFalse(BrowserOperationsChannel.canRestoreBetween(named, .default()))
    }
  }

  @MainActor func testProcessFailureSurvivesDelegateReplacementAndForwards() {
    let messenger = BrowserMessenger()
    let registrar = ProxyAPIRegistrar(binaryMessenger: messenger)
    let channel = BrowserOperationsChannel(registrar: registrar, messenger: messenger)
    let view = WKWebView(frame: .zero)
    let identifier = registrar.instanceManager.addHostCreatedInstance(view)
    messenger.call("observeProcessFailures", args: ["webViewId": identifier])
    let forward = ProcessNavigationDelegate()
    BrowserOperationsChannel.setNavigationDelegate(forward, on: view)
    XCTAssertFalse(view.navigationDelegate === forward)
    view.navigationDelegate?.webViewWebContentProcessDidTerminate?(view)
    XCTAssertEqual(forward.failures, 1)
    XCTAssertEqual(messenger.events.last?.method, "processFailed")
    let args = messenger.events.last?.arguments as? [String: Any]
    XCTAssertEqual((args?["webViewId"] as? NSNumber)?.int64Value, identifier)
    channel.close()
    XCTAssertTrue(view.navigationDelegate === forward)
  }

  @MainActor func testUnsupportedFullscreenLeavesPreferencesUnchanged() {
    let messenger = BrowserMessenger()
    let registrar = ProxyAPIRegistrar(binaryMessenger: messenger)
    let channel = BrowserOperationsChannel(registrar: registrar, messenger: messenger)
    let view = WKWebView(frame: .zero)
    let identifier = registrar.instanceManager.addHostCreatedInstance(view)
    if #available(iOS 16, macOS 13, *) {
      let initial = view.configuration.preferences.isElementFullscreenEnabled
      messenger.call(
        "setFullscreenDelegateEnabled", args: ["webViewId": identifier, "enabled": true])
      XCTAssertTrue(view.configuration.preferences.isElementFullscreenEnabled)
      messenger.call(
        "setFullscreenDelegateEnabled", args: ["webViewId": identifier, "enabled": false])
      XCTAssertEqual(view.configuration.preferences.isElementFullscreenEnabled, initial)
    }
    channel.close()
  }
}

private final class ProcessNavigationDelegate: NSObject, WKNavigationDelegate {
  var failures = 0
  func webViewWebContentProcessDidTerminate(_ view: WKWebView) { failures += 1 }
}

private final class BrowserMessenger: TestBinaryMessenger {
  private var browserHandler: FlutterBinaryMessageHandler?
  var events: [FlutterMethodCall] = []
  override func send(onChannel channel: String, message: Data?) {
    send(onChannel: channel, message: message, binaryReply: nil)
  }
  override func setMessageHandlerOnChannel(
    _ channel: String,
    binaryMessageHandler handler: FlutterBinaryMessageHandler? = nil
  ) -> FlutterBinaryMessengerConnection {
    if channel == "com.abandoft.webview_all_wkwebview/browser" { browserHandler = handler }
    return 0
  }
  func call(_ method: String, args: [String: Any]) {
    let message = FlutterStandardMethodCodec.sharedInstance().encode(
      FlutterMethodCall(methodName: method, arguments: args))
    browserHandler?(message) { _ in }
  }
  override func send(
    onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply? = nil
  ) {
    if channel == "com.abandoft.webview_all_wkwebview/browser", let message {
      events.append(FlutterStandardMethodCodec.sharedInstance().decodeMethodCall(message))
    }
    callback?(nil)
  }
}

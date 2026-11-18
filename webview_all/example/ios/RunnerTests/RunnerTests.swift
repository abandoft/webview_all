import Flutter
import UIKit
import XCTest
import webview_all_wkwebview

class RunnerTests: XCTestCase {
  @MainActor func testSceneEngineRegistersTheWebViewPlugin() async throws {
    var sceneEngine: FlutterEngine?
    for _ in 0..<100 {
      sceneEngine =
        UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .compactMap { $0.rootViewController as? FlutterViewController }
        .first?.engine
      if sceneEngine != nil { break }
      try await Task.sleep(nanoseconds: 100_000_000)
    }

    let engine = try XCTUnwrap(sceneEngine, "The scene did not create a Flutter engine.")
    let plugin = engine.valuePublished(byPlugin: "WebviewAllWKWebViewPlugin")
    XCTAssertTrue(
      plugin is WebviewAllWKWebViewPlugin, "The scene engine did not publish the WebView plugin.")
  }
}

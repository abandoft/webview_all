import XCTest

final class WebViewGestureUITests: XCTestCase {
  func testNativeTouchesAndFlutterOverlaysForEachPolicy() {
    continueAfterFailure = false
    let app = XCUIApplication()
    app.launch()
    defer { app.terminate() }
    for policy in ["fallbackToPluginDefault", "eager", "waitUntilTouchesEnded", "doNotBlockGesture"] {
      XCTContext.runActivity(named: policy) { _ in
        XCTAssertTrue(app.staticTexts["Policy: " + policy].waitForExistence(timeout: 30))

        let webView = app.webViews.firstMatch
        var button = webView.buttons["Web taps: 0"]
        XCTAssertTrue(button.waitForExistence(timeout: 30))
        XCTAssertTrue(webView.staticTexts["Scroll: 0"].exists)
        button.tap()
        button = webView.buttons["Web taps: 1"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))

        webView.swipeUp()
        let scrolled = expectation(
          for: NSPredicate(format: "exists == false"),
          evaluatedWith: webView.staticTexts["Scroll: 0"])
        wait(for: [scrolled], timeout: 5)
        button.tap()
        button = webView.buttons["Web taps: 2"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        let buttonPosition = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        app.buttons["Show overlay"].tap()
        XCTAssertTrue(app.buttons["Hide overlay"].waitForExistence(timeout: 5))
        buttonPosition.tap()
        XCTAssertTrue(app.staticTexts["Overlay taps: 1"].waitForExistence(timeout: 5))
        app.buttons["Hide overlay"].tap()

        // The covered WebView must not have received the overlay's touch.
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(webView.buttons["Web taps: 3"].waitForExistence(timeout: 5))
        if policy != "doNotBlockGesture" {
          app.buttons["Next policy"].tap()
        }
      }
    }
  }
}

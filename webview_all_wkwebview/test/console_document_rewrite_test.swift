// Run on macOS: swift test/console_document_rewrite_test.swift
// Uses the actual Dart-injected source in a native WKWebView.
import AppKit
import WebKit

final class ConsoleRewriteTest: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
  private var webView: WKWebView!
  private var window: NSWindow!
  private var messages: [[String: Any]] = []
  private var started = false
  private let source: String

  init(source: String) {
    self.source = source
    super.init()
    let configuration = WKWebViewConfiguration()
    let content = configuration.userContentController
    content.add(self, name: "fltConsoleMessage")
    content.add(self, name: "testStatus")
    content.addUserScript(WKUserScript(source: """
      (function() {
        if (window.originalConsoleCalls) { return; }
        window.originalConsoleCalls = [];
        ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
          const original = console[level];
          console[level] = function() {
            window.originalConsoleCalls.push(level);
            return original.apply(console, arguments);
          };
        });
      })();
      """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    content.addUserScript(WKUserScript(
      source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600),
                        configuration: configuration)
    webView.navigationDelegate = self
    window = NSWindow(contentRect: webView.frame, styleMask: .borderless,
                      backing: .buffered, defer: false)
    window.contentView = webView
    webView.loadHTMLString("<html><body>Initial document</body></html>",
                          baseURL: URL(string: "https://document-rewrite.test/"))
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !started else { return }
    started = true
    let encodedSource = String(data: try! JSONSerialization.data(
      withJSONObject: [source]), encoding: .utf8)!
    webView.evaluateJavaScript("""
      (function() {
        const source = \(encodedSource)[0];
        let stage = 0;
        function report() {
          // Re-injection must neither redeclare global lexical bindings nor
          // wrap console functions or attach the error callback twice.
          (0, eval)(source);
          (0, eval)(source);
          ['log', 'info', 'warn', 'error', 'debug'].forEach(function(level) {
            console[level]('stage-' + stage + '-' + level);
          });
          setTimeout(function() { throw new Error('uncaught-stage-' + stage); }, 0);
          setTimeout(nextStage, 80);
        }
        function nextStage() {
          stage++;
          if (stage === 3) {
            const oldRoot = document.documentElement;
            oldRoot.replaceWith(oldRoot.cloneNode(true));
            setTimeout(report, 0);
          } else if (stage < 3) {
            document.open();
            document.write('<html><body>Replacement ' + stage +
              '<script>throw new Error("inline-stage-' + stage + '")<\\/script></body></html>');
            // The first rewrite intentionally remains open; restoration must
            // not depend on document.close() or a navigation completion event.
            if (stage === 2) { document.close(); }
            // Allow the retained Document observer to restore window listeners.
            setTimeout(report, 0);
          } else {
            window.webkit.messageHandlers.testStatus.postMessage({
              originalCalls: window.originalConsoleCalls.length
            });
          }
        }
        report();
      })();
      """) { _, error in
      if let error = error { self.fail("JavaScript execution failed: \(error)") }
    }
  }

  func userContentController(_ userContentController: WKUserContentController,
                             didReceive message: WKScriptMessage) {
    guard message.frameInfo.isMainFrame else { fail("Unexpected subframe message") }
    if message.name == "fltConsoleMessage" {
      guard let body = message.body as? String,
            let data = body.data(using: .utf8),
            let log = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { fail("Malformed console bridge message") }
      messages.append(log)
      return
    }
    guard let status = message.body as? [String: Any],
          status["originalCalls"] as? Int == 20 else {
      fail("Original console methods were skipped or called more than once: \(message.body)")
    }
    for stage in 0...3 {
      for level in ["log", "info", "warn", "error", "debug"] {
        let marker = "stage-\(stage)-\(level)"
        let matches = messages.filter { $0["message"] as? String == marker }
        guard matches.count == 1,
              matches[0]["level"] as? String == (level == "warn" ? "warning" : level)
        else { fail("Expected exactly one correctly leveled console message: \(marker)") }
      }
      let marker = "uncaught-stage-\(stage)"
      let matches = messages.filter { ($0["message"] as? String)?.contains(marker) == true }
      guard matches.count == 1, matches[0]["level"] as? String == "error" else {
        fail("Expected one complete runtime error message: \(marker)")
      }
    }
    for stage in 1...2 {
      let marker = "inline-stage-\(stage)"
      let matches = messages.filter { ($0["message"] as? String)?.contains(marker) == true }
      guard matches.count == 1, matches[0]["level"] as? String == "error" else {
        fail("Expected one inline runtime error during document.write: \(marker)")
      }
    }
    guard messages.count == 26 else { fail("Unexpected duplicate or extra bridge messages") }
    print("PASS: native WKWebView console methods and uncaught errors survive two document.open rewrites, inline scripts, root replacement, and repeated injection (26 messages; 20 original calls).")
    exit(0)
  }

  private func fail(_ message: String) -> Never {
    fputs("FAIL: \(message)\n", stderr)
    exit(1)
  }
}

let testFile = URL(fileURLWithPath: #filePath)
let controllerFile = testFile.deletingLastPathComponent().deletingLastPathComponent()
  .appendingPathComponent("lib/src/webkit_webview_controller.dart")
let dartSource = try String(contentsOf: controllerFile, encoding: .utf8)
let start = dartSource.range(of: "(function() {\n  if (window._flutter_webview_plugin_overrides)")!
let end = dartSource.range(of: "      ''',", range: start.lowerBound..<dartSource.endIndex)!
let source = String(dartSource[start.lowerBound..<end.lowerBound])
  .replacingOccurrences(of: "$_onConsoleMessageChannelName", with: "fltConsoleMessage")
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let test = ConsoleRewriteTest(source: source)
DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
  fputs("FAIL: WKWebView test timed out\n", stderr)
  exit(1)
}
app.run()

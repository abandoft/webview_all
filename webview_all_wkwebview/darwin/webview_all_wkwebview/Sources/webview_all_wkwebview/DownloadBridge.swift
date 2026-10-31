import Foundation
import ObjectiveC
import WebKit

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

private var downloadBridgeAssociation: UInt8 = 0

/// Engine-scoped registration; active bridges are owned by their WKWebView.
final class DownloadBridgeChannel {
  private let channel: FlutterMethodChannel
  private weak var registrar: ProxyAPIRegistrar?
  private let messenger: FlutterBinaryMessenger
  private let bridges = NSHashTable<AnyObject>.weakObjects()

  init(registrar: ProxyAPIRegistrar, messenger: FlutterBinaryMessenger) {
    self.registrar = registrar
    self.messenger = messenger
    channel = FlutterMethodChannel(
      name: "com.abandoft.webview_all_wkwebview/downloads", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      guard call.method == "configure",
        let args = call.arguments as? [String: Any],
        let identifier = args["webViewId"] as? NSNumber,
        let enabled = args["enabled"] as? Bool,
        let view: WKWebView = self.registrar?.instanceManager.instance(
          forIdentifier: identifier.int64Value)
      else {
        result(
          FlutterError(
            code: "invalid_download_request", message: "Unknown WebView or method.", details: nil))
        return
      }
      guard #available(iOS 14.5, macOS 11.3, *) else {
        result(
          FlutterError(
            code: "not_supported", message: "Downloads require iOS 14.5 or macOS 11.3.",
            details: nil))
        return
      }
      if args["dispose"] as? Bool == true {
        DownloadBridge.remove(from: view)
      } else if let bridge = DownloadBridge.get(from: view) {
        bridge.update(
          enabled: enabled, generation: (args["generation"] as? NSNumber)?.intValue ?? 0)
      } else if enabled {
        let bridge = DownloadBridge(
          view: view, identifier: identifier.int64Value,
          generation: (args["generation"] as? NSNumber)?.intValue ?? 0,
          messenger: self.messenger)
        objc_setAssociatedObject(
          view, &downloadBridgeAssociation, bridge, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        self.bridges.add(bridge)
      }
      result(nil)
    }
  }

  func close() {
    channel.setMethodCallHandler(nil)
    if #available(iOS 14.5, macOS 11.3, *) {
      for bridge in bridges.allObjects {
        if let bridge = bridge as? DownloadBridge, let view = bridge.view {
          DownloadBridge.remove(from: view)
        }
      }
    }
    bridges.removeAllObjects()
  }

  static func setNavigationDelegate(_ delegate: WKNavigationDelegate, on view: WKWebView) {
    if #available(iOS 14.5, macOS 11.3, *), let bridge = DownloadBridge.get(from: view) {
      bridge.forwardDelegate = delegate
      // WebKit caches which optional selectors the delegate implements when
      // it is assigned. Refresh that cache after changing the forwarded API.
      view.navigationDelegate = nil
      view.navigationDelegate = bridge
    } else {
      view.navigationDelegate = delegate
    }
  }

  static func dispose(_ view: WKWebView) {
    if #available(iOS 14.5, macOS 11.3, *) { DownloadBridge.remove(from: view) }
  }

  static func noteNavigation(on view: WKWebView, navigation: WKNavigation?, url: URL?) {
    if #available(iOS 14.5, macOS 11.3, *) {
      DownloadBridge.get(from: view)?.noteNavigation(navigation, url: url)
    }
  }
}

#if compiler(>=6.0)
  private typealias DownloadActionPolicyHandler = @MainActor (WKNavigationActionPolicy) -> Void
  private typealias DownloadResponsePolicyHandler = @MainActor (WKNavigationResponsePolicy) -> Void
  private typealias DownloadDestinationHandler = @MainActor (URL?) -> Void
  private typealias DownloadAuthenticationHandler =
    @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
#else
  private typealias DownloadActionPolicyHandler = (WKNavigationActionPolicy) -> Void
  private typealias DownloadResponsePolicyHandler = (WKNavigationResponsePolicy) -> Void
  private typealias DownloadDestinationHandler = (URL?) -> Void
  private typealias DownloadAuthenticationHandler = (
    URLSession.AuthChallengeDisposition, URLCredential?
  ) -> Void
#endif

@available(iOS 14.5, macOS 11.3, *)
private final class DownloadRecord {
  let id = UUID().uuidString
  let download: WKDownload
  let generation: Int
  var url = ""
  var target: URL?
  var temporaryDirectory: URL?
  var pendingDestination: DownloadDestinationHandler?
  var timeout: DispatchWorkItem?
  var progressObservation: NSKeyValueObservation?
  var navigation: WKNavigation?

  init(_ download: WKDownload, generation: Int) {
    self.download = download
    self.generation = generation
  }
}

/// Wraps the current navigation delegate rather than replacing its callbacks.
@available(iOS 14.5, macOS 11.3, *)
private final class DownloadBridge: NSObject, WKNavigationDelegate, WKDownloadDelegate {
  weak var view: WKWebView?
  weak var forwardDelegate: WKNavigationDelegate?
  private let channel: FlutterMethodChannel
  private var records: [ObjectIdentifier: DownloadRecord] = [:]
  private var conversionURLs: [String: Set<String>] = [:]
  private var conversionNavigations: [String: WKNavigation] = [:]
  private var pendingNavigation: (url: String, navigation: WKNavigation)?
  private var closed = false
  private var enabled = true
  private var generation: Int

  static func get(from view: WKWebView) -> DownloadBridge? {
    objc_getAssociatedObject(view, &downloadBridgeAssociation) as? DownloadBridge
  }

  static func remove(from view: WKWebView) {
    get(from: view)?.close()
    objc_setAssociatedObject(
      view, &downloadBridgeAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  init(view: WKWebView, identifier: Int64, generation: Int, messenger: FlutterBinaryMessenger) {
    self.view = view
    self.generation = generation
    forwardDelegate = view.navigationDelegate
    channel = FlutterMethodChannel(
      name: "com.abandoft.webview_all_wkwebview/downloads/\(identifier)", binaryMessenger: messenger
    )
    super.init()
    view.navigationDelegate = self
  }

  func update(enabled: Bool, generation: Int) {
    self.enabled = enabled
    self.generation = generation
    // Accepted transfers belong to the controller, not to its latest delegate.
    for record in Array(records.values) where record.target == nil {
      finish(record.download, status: "cancelled")
    }
  }

  func noteNavigation(_ navigation: WKNavigation?, url: URL?) {
    if let navigation, let url {
      pendingNavigation = (url.absoluteString, navigation)
    } else {
      pendingNavigation = nil
    }
  }

  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (forwardDelegate?.responds(to: selector) ?? false)
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if forwardDelegate?.responds(to: selector) ?? false { return forwardDelegate }
    return super.forwardingTarget(for: selector)
  }

  @objc(webView:decidePolicyForNavigationAction:decisionHandler:)
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping DownloadActionPolicyHandler
  ) {
    let complete: DownloadActionPolicyHandler = { [weak self] policy in
      let selected: WKNavigationActionPolicy =
        policy == .allow && self?.enabled == true && action.shouldPerformDownload
        ? .download : policy
      if selected == .download { self?.expectPolicyConversion(action.request.url) }
      decisionHandler(selected)
    }
    if let forwardDelegate,
      forwardDelegate.responds(
        to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:"))
    {
      forwardDelegate.webView?(webView, decidePolicyFor: action, decisionHandler: complete)
    } else {
      complete(.allow)
    }
  }

  @objc(webView:decidePolicyForNavigationResponse:decisionHandler:)
  func webView(
    _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
    decisionHandler: @escaping DownloadResponsePolicyHandler
  ) {
    let disposition = (response.response as? HTTPURLResponse)?.allHeaderFields.first {
      String(describing: $0.key).lowercased() == "content-disposition"
    }.map { String(describing: $0.value).lowercased() }
    let attachment =
      disposition?.split(separator: ";", maxSplits: 1).first?
      .trimmingCharacters(in: .whitespacesAndNewlines) == "attachment"
    let complete: DownloadResponsePolicyHandler = { [weak self] policy in
      let selected: WKNavigationResponsePolicy =
        policy == .allow && self?.enabled == true && (attachment || !response.canShowMIMEType)
        ? .download : policy
      if selected == .download { self?.expectPolicyConversion(response.response.url) }
      decisionHandler(selected)
    }
    if let forwardDelegate,
      forwardDelegate.responds(
        to: NSSelectorFromString("webView:decidePolicyForNavigationResponse:decisionHandler:"))
    {
      forwardDelegate.webView?(webView, decidePolicyFor: response, decisionHandler: complete)
    } else {
      complete(.allow)
    }
  }

  func webView(
    _ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload
  ) {
    attach(download)
  }

  func webView(
    _ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload
  ) {
    attach(download)
  }

  private func expectConversion(_ record: DownloadRecord, url: URL?) {
    guard let url = url?.absoluteString else { return }
    let first = conversionURLs[record.id] == nil
    conversionURLs[record.id, default: []].insert(url)
    if let navigation = record.navigation { conversionNavigations[record.id] = navigation }
    if first {
      let identifier = record.id
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
        self?.conversionURLs.removeValue(forKey: identifier)
        self?.conversionNavigations.removeValue(forKey: identifier)
      }
    }
  }

  private func expectPolicyConversion(_ url: URL?) {
    guard let url = url?.absoluteString else { return }
    let identifier = "policy-\(UUID().uuidString)"
    conversionURLs[identifier] = [url]
    if pendingNavigation?.url == url {
      conversionNavigations[identifier] = pendingNavigation?.navigation
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
      self?.conversionURLs.removeValue(forKey: identifier)
      self?.conversionNavigations.removeValue(forKey: identifier)
    }
  }

  private func isDownloadConversion(_ error: Error, navigation: WKNavigation?) -> Bool {
    let error = error as NSError
    guard error.domain == "WebKitErrorDomain", error.code == 102 else { return false }
    if let navigation,
      conversionNavigations.values.contains(where: { $0 === navigation })
    {
      return true
    }
    let failingURL =
      error.userInfo[NSURLErrorFailingURLStringErrorKey] as? String
      ?? (error.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
    guard let url = failingURL
    else { return false }
    let matches = conversionURLs.filter { $0.value.contains(url) }.keys
    // Prefer the actual WKNavigation identity. URL matching is only a fallback
    // for downloads for which WebKit did not provide a navigation object.
    for identifier in matches where conversionNavigations[identifier] == nil {
      // The policy callback can precede didBecomeDownload. Bind its expected
      // interruption to the actual navigation as soon as WebKit supplies it.
      if let navigation { conversionNavigations[identifier] = navigation }
      return true
    }
    return navigation == nil && !matches.isEmpty
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    if pendingNavigation?.navigation === navigation { pendingNavigation = nil }
    forwardDelegate?.webView?(webView, didFinish: navigation)
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    if !isDownloadConversion(error, navigation: navigation) {
      forwardDelegate?.webView?(webView, didFail: navigation, withError: error)
    }
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    if !isDownloadConversion(error, navigation: navigation) {
      forwardDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
  }

  private func attach(_ download: WKDownload) {
    guard !closed else {
      download.cancel(nil)
      return
    }
    // With no download delegate, retain the pre-existing WKWebView behavior.
    guard enabled else { return }
    let record = DownloadRecord(download, generation: generation)
    record.url = download.originalRequest?.url?.absoluteString ?? ""
    if pendingNavigation?.url == record.url {
      record.navigation = pendingNavigation?.navigation
      pendingNavigation = nil
    }
    expectConversion(record, url: download.originalRequest?.url)
    records[ObjectIdentifier(download)] = record
    download.delegate = self
  }

  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse,
    suggestedFilename: String, completionHandler: @escaping DownloadDestinationHandler
  ) {
    let key = ObjectIdentifier(download)
    guard !closed, let record = records[key] else {
      completionHandler(nil)
      return
    }
    record.url = response.url?.absoluteString ?? record.url
    expectConversion(record, url: response.url)
    record.pendingDestination = completionHandler
    var request: [String: Any] = [
      "id": record.id, "url": record.url,
      "generation": record.generation,
      "suggestedFilename": suggestedFilename,
      "supportedActions": ["cancel", "saveToFile", "handledExternally"],
    ]
    if let mime = response.mimeType { request["mimeType"] = mime }
    if response.expectedContentLength >= 0 {
      request["contentLength"] = response.expectedContentLength
    }
    if let http = response as? HTTPURLResponse,
      let disposition = http.allHeaderFields.first(where: {
        String(describing: $0.key).lowercased() == "content-disposition"
      })
    {
      request["contentDisposition"] = String(describing: disposition.value)
    }
    let timeout = DispatchWorkItem { [weak self, weak download] in
      guard let self, let download else { return }
      self.finish(
        download, status: "failed", code: "download_decision_timeout",
        description: "The download decision timed out.")
    }
    record.timeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 35, execute: timeout)
    channel.invokeMethod("request", arguments: request) { [weak self, weak download] decision in
      DispatchQueue.main.async {
        guard let self, let download, let record = self.records[key],
          record.pendingDestination != nil
        else { return }
        record.timeout?.cancel()
        guard let decision = decision as? [String: Any], let action = decision["action"] as? String
        else {
          self.finish(
            download, status: "failed", code: "invalid_download_decision",
            description: "The application returned no download decision.")
          return
        }
        if let error = decision["errorCode"] as? String {
          self.finish(
            download, status: "failed", code: error, description: decision["description"] as? String
          )
          return
        }
        switch action {
        case "cancel": self.finish(download, status: "cancelled")
        case "handledExternally": self.finish(download, status: "handedOff")
        case "saveToFile":
          guard let path = decision["path"] as? String, (path as NSString).isAbsolutePath,
            !path.contains("\0"), !FileManager.default.fileExists(atPath: path)
          else {
            self.finish(
              download, status: "failed", code: "invalid_download_destination",
              description: "Choose an absolute path that does not already exist.")
            return
          }
          do {
            let target = URL(fileURLWithPath: path)
            let parent = target.deletingLastPathComponent().path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory),
              isDirectory.boolValue, FileManager.default.isWritableFile(atPath: parent)
            else {
              self.finish(
                download, status: "failed", code: "invalid_download_destination",
                description: "The parent directory must already exist and be writable.")
              return
            }
            // Keep staging on the destination volume so final publication is
            // a no-replace move rather than a large cross-volume copy on the
            // WebKit callback thread.
            let directory = target.deletingLastPathComponent().appendingPathComponent(
              ".webview-all-download-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(
              at: directory, withIntermediateDirectories: false,
              attributes: [.posixPermissions: 0o700])
            record.target = target
            record.temporaryDirectory = directory
            record.progressObservation = download.progress.observe(
              \.completedUnitCount, options: [.new]
            ) { [weak self, weak download] progress, _ in
              DispatchQueue.main.async {
                guard let self, let download, let current = self.records[ObjectIdentifier(download)]
                else { return }
                var event: [String: Any] = [
                  "id": current.id, "bytesReceived": progress.completedUnitCount,
                ]
                if progress.totalUnitCount >= 0 { event["totalBytes"] = progress.totalUnitCount }
                self.channel.invokeMethod("progress", arguments: event)
              }
            }
            let complete = record.pendingDestination
            record.pendingDestination = nil
            complete?(directory.appendingPathComponent("payload"))
          } catch {
            self.finish(
              download, status: "failed", code: "download_destination_failed",
              description: error.localizedDescription)
          }
        default:
          self.finish(
            download, status: "failed", code: "unsupported_download_action",
            description: "This download requires an explicit file target.")
        }
      }
    }
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let record = records[ObjectIdentifier(download)],
      let directory = record.temporaryDirectory, let target = record.target
    else { return }
    do {
      // moveItem does not replace an existing target, including a concurrent
      // file created after the application's decision.
      try FileManager.default.moveItem(at: directory.appendingPathComponent("payload"), to: target)
      finish(download, status: "completed", cancel: false)
    } catch {
      finish(
        download, status: "failed", code: "download_save_failed",
        description: error.localizedDescription, cancel: false)
    }
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    finish(
      download, status: "failed", code: String((error as NSError).code),
      description: error.localizedDescription, cancel: false)
  }

  func download(
    _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping DownloadAuthenticationHandler
  ) {
    if let view, let forwardDelegate,
      forwardDelegate.responds(
        to: NSSelectorFromString("webView:didReceiveAuthenticationChallenge:completionHandler:"))
    {
      forwardDelegate.webView?(view, didReceive: challenge, completionHandler: completionHandler)
    } else {
      completionHandler(.performDefaultHandling, nil)
    }
  }

  private func finish(
    _ download: WKDownload, status: String, code: String? = nil,
    description: String? = nil, cancel: Bool = true
  ) {
    guard let record = records.removeValue(forKey: ObjectIdentifier(download)) else { return }
    record.timeout?.cancel()
    record.progressObservation?.invalidate()
    let pending = record.pendingDestination
    record.pendingDestination = nil
    pending?(nil)
    download.delegate = nil
    if cancel { download.cancel(nil) }
    if let directory = record.temporaryDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    var result: [String: Any] = ["id": record.id, "status": status]
    if status == "completed", let target = record.target { result["path"] = target.path }
    if let code { result["errorCode"] = code }
    if let description { result["description"] = description }
    channel.invokeMethod("result", arguments: result)
  }

  func close() {
    guard !closed else { return }
    closed = true
    conversionURLs.removeAll()
    conversionNavigations.removeAll()
    pendingNavigation = nil
    for record in Array(records.values) { finish(record.download, status: "cancelled") }
    if view?.navigationDelegate === self { view?.navigationDelegate = forwardDelegate }
  }

  deinit {
    // Explicit WebView disposal and engine teardown close the bridge on the
    // main thread. This handles final collection of an unused WKWebView too.
    for record in records.values {
      record.timeout?.cancel()
      record.progressObservation?.invalidate()
      let download = record.download
      let pending = record.pendingDestination
      let directory = record.temporaryDirectory
      DispatchQueue.main.async {
        pending?(nil)
        download.delegate = nil
        download.cancel(nil)
        if let directory { try? FileManager.default.removeItem(at: directory) }
      }
    }
  }
}

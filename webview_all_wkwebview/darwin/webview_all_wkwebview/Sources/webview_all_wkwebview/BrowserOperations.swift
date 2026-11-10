import Foundation
import ObjectiveC
import WebKit

#if os(iOS)
  import Flutter
  import UIKit
#else
  import FlutterMacOS
  import AppKit
#endif

private var browserCaptureAssociation: UInt8 = 0
private var browserRecordAssociation: UInt8 = 0

/// Captures native page content without including Flutter overlays or print UI.
final class BrowserOperationsChannel {
  private let channel: FlutterMethodChannel
  private weak var registrar: ProxyAPIRegistrar?
  private var requests: [UUID: BrowserCapture] = [:]
  private let views = NSHashTable<WKWebView>.weakObjects()
  private var navigationStates: [String: (state: Any, store: WKWebsiteDataStore)] = [:]
  private var printJobs: [String: BrowserPrintJob] = [:]

  static func canRestoreBetween(_ source: WKWebsiteDataStore, _ target: WKWebsiteDataStore) -> Bool
  {
    if source === target { return true }
    // Distinct ephemeral stores must never be treated as the same profile.
    guard source.isPersistent, target.isPersistent else { return false }
    if #available(iOS 17.0, macOS 14.0, *) {
      if let identifier = source.identifier { return identifier == target.identifier }
      return source === WKWebsiteDataStore.default() && target === WKWebsiteDataStore.default()
    }
    // Before named stores, the default store is the only persistent store.
    return true
  }

  init(registrar: ProxyAPIRegistrar, messenger: FlutterBinaryMessenger) {
    self.registrar = registrar
    channel = FlutterMethodChannel(
      name: "com.abandoft.webview_all_wkwebview/browser", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      if BrowserProfiles.handle(call, result: result) { return }
      if call.method == "releaseNavigationState" {
        if let args = call.arguments as? [String: Any], let id = args["stateId"] as? String {
          if let state = self.navigationStates.removeValue(forKey: id) {
            BrowserProfiles.releaseSnapshot(state.store)
          }
        }
        result(nil)
        return
      }
      if call.method == "supportsNamedProfiles" {
        if #available(iOS 17.0, macOS 14.0, *) { result(true) } else { result(false) }
        return
      }
      if ["getWebsiteDataRecords", "clearWebsiteDataFor"].contains(call.method) {
        guard let args = call.arguments as? [String: Any], let id = args["storeId"] as? NSNumber,
          let store: WKWebsiteDataStore = self.registrar?.instanceManager.instance(
            forIdentifier: id.int64Value),
          let indices = args["dataTypes"] as? [Int],
          indices.allSatisfy({ $0 >= 0 && $0 < BrowserWebsiteData.types.count })
        else {
          result(
            FlutterError(
              code: "invalid_store", message: "The website-data store or category is unavailable.",
              details: nil))
          return
        }
        BrowserWebsiteData.handle(
          store: store, args: args, clearing: call.method == "clearWebsiteDataFor", result: result)
        return
      }
      if ["printJobState", "cancelPrintJob", "releasePrintJob"].contains(call.method) {
        let id = (call.arguments as? [String: Any])?["jobId"] as? String ?? ""
        if call.method == "printJobState" {
          result(self.printJobs[id]?.state ?? "unknown")
        } else if call.method == "cancelPrintJob" {
          result(self.printJobs[id]?.cancel() ?? false)
        } else {
          self.printJobs.removeValue(forKey: id)
          result(nil)
        }
        return
      }
      guard let args = call.arguments as? [String: Any],
        let identifier = args["webViewId"] as? NSNumber,
        let view: WKWebView = self.registrar?.instanceManager.instance(
          forIdentifier: identifier.int64Value)
      else {
        result(
          FlutterError(
            code: "invalid_view", message: "The WebView is closed or unavailable.", details: nil))
        return
      }
      let record = self.observe(view)
      switch call.method {
      case "setContentRules":
        record.setContentRules(args["rules"] as? [[String: Any]] ?? [], result: result)
        return
      case "pauseMedia", "setMediaPlaybackSuspended":
        if #available(iOS 15.0, macOS 12.0, *) {
          if call.method == "pauseMedia" {
            view.pauseAllMediaPlayback { result(true) }
          } else {
            view.setAllMediaPlaybackSuspended(args["suspended"] as? Bool == true) { result(true) }
          }
        } else {
          result(false)
        }
        return
      case "setContextMenuEnabled":
        #if os(macOS)
          (view as? WebViewImpl)?.browserContextMenusEnabled = args["enabled"] as? Bool
          result(true)
        #else
          result(false)
        #endif
        return
      case "createRelatedView":
        guard let source = view as? WebViewImpl, let manager = self.registrar?.instanceManager
        else {
          result(nil)
          return
        }
        let configuration = view.configuration.copy() as! WKWebViewConfiguration
        configuration.userContentController = WKUserContentController()
        configuration.preferences = configuration.preferences.copy() as! WKPreferences
        ResourceSchemeHandler.install(on: configuration)
        let child = WebViewImpl(
          api: source.api, registrar: source.registrar, frame: .zero, configuration: configuration)
        let childConfiguration = child.configuration
        BrowserProfiles.track(childConfiguration, store: childConfiguration.websiteDataStore, manager: manager)
        self.observe(child).contentJavaScriptOverride =
          configuration.defaultWebpagePreferences.allowsContentJavaScript
        result([
          "webViewId": manager.addHostCreatedInstance(child),
          "configurationId": manager.addHostCreatedInstance(childConfiguration),
        ])
        return
      case "printPage":
        guard self.printJobs.count < 32, let name = args["jobName"] as? String,
          !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 256,
          let job = BrowserPrintJob(view: view, name: name)
        else {
          result(nil)
          return
        }
        let id = UUID().uuidString
        self.printJobs[id] = job
        guard job.present() else {
          self.printJobs.removeValue(forKey: id)
          result(nil)
          return
        }
        result(["jobId": id, "state": job.state, "canQuery": true, "canCancel": job.canCancel])
        return
      case "saveNavigationState":
        if #available(iOS 15.0, macOS 12.0, *) {
          guard self.navigationStates.count < 16, let state = view.interactionState else {
            result(nil)
            return
          }
          let id = UUID().uuidString
          self.navigationStates[id] = (state, view.configuration.websiteDataStore)
          BrowserProfiles.retainSnapshot(view.configuration.websiteDataStore)
          result(id)
        } else {
          result(nil)
        }
        return
      case "restoreNavigationState":
        if #available(iOS 15.0, macOS 12.0, *), let id = args["stateId"] as? String,
          let state = self.navigationStates[id],
          Self.canRestoreBetween(state.store, view.configuration.websiteDataStore)
        {
          record.cancelWindows()
          (view as? WebViewImpl)?.navigationPolicyGeneration &+= 1
          view.interactionState = state.state
          result(true)
        } else {
          result(false)
        }
        return
      case "setChildJavaScriptEnabled":
        record.contentJavaScriptOverride = args["enabled"] as? Bool
        result(true)
        return
      case "browserCapabilities":
        if #available(iOS 16.0, macOS 13.0, *) {
          result(["fullscreenEvents": true, "navigationState": true])
        } else if #available(iOS 15.0, macOS 12.0, *) {
          result(["fullscreenEvents": false, "navigationState": true])
        } else {
          result(["fullscreenEvents": false, "navigationState": false])
        }
        return
      case "setFullscreenDelegateEnabled":
        if #available(iOS 16.0, macOS 13.0, *) {
          record.observeFullscreen(enabled: args["enabled"] as? Bool == true)
          result(true)
        } else {
          result(false)
        }
        return
      case "observeProcessFailures":
        result(nil)
        return
      case "setNewWindowDelegateEnabled":
        record.delegateWindows =
          args["enabled"] as? Bool == true
        if !record.delegateWindows { record.cancelWindows() }
        result(nil)
        return
      case "setPopupWindowPolicy":
        record.denyWindows = args["policy"] as? Int == 1
        if record.denyWindows { record.cancelWindows() }
        result(nil)
        return
      case "observeWindowClose":
        result(nil)
        return
      case "claimNewWindow", "attachNewWindow":
        let id = args["requestId"] as? String ?? ""
        guard let pending = record.windows[id], !pending.resolved else {
          result(call.method == "claimNewWindow" ? nil : false)
          return
        }
        if call.method == "claimNewWindow" {
          guard !pending.claimed, let manager = self.registrar?.instanceManager else {
            result(nil)
            return
          }
          pending.claimed = true
          let child = pending.child
          let viewId = manager.addHostCreatedInstance(child)
          let childConfiguration = child.configuration
          BrowserProfiles.track(childConfiguration, store: childConfiguration.websiteDataStore, manager: manager)
          let configurationId = manager.addHostCreatedInstance(childConfiguration)
          pending.identifier = viewId
          result(["webViewId": viewId, "configurationId": configurationId])
        } else {
          let accepted =
            pending.claimed && record.delegateWindows && !record.denyWindows
            && (args["childWebViewId"] as? NSNumber)?.int64Value == pending.identifier
          pending.finish(accept: accepted)
          result(accepted)
        }
        return
      case "takeScreenshot", "createPdf", "createArchive": break
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      if let active = objc_getAssociatedObject(view, &browserCaptureAssociation) as? BrowserCapture
      {
        if !active.done {
          result(
            FlutterError(
              code: "capture_busy", message: "A native capture is in progress.", details: nil))
          return
        }
      }
      let id = UUID()
      let request = BrowserCapture(view: view) { [weak self] value in
        self?.requests.removeValue(forKey: id)
        result(value)
      }
      self.requests[id] = request
      objc_setAssociatedObject(
        view, &browserCaptureAssociation, request, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      if call.method == "createArchive", args["format"] as? String != "webArchive" {
        request.cancel()
        return
      }
      request.start(
        pdf: call.method == "createPdf", options: args["options"] as? [String: Any],
        archive: call.method == "createArchive")
    }
  }

  static func cancel(_ view: WKWebView) {
    if let record = record(view) {
      record.cancelWindows()
      record.incoming?.finish(accept: false)
      record.closed = true
      record.cancelContentRules()
      record.stopObservingFullscreen()
      view.navigationDelegate = record.forward
      objc_setAssociatedObject(
        view, &browserRecordAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    (objc_getAssociatedObject(view, &browserCaptureAssociation) as? BrowserCapture)?.cancel()
    objc_setAssociatedObject(
      view, &browserCaptureAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  func close() {
    for job in printJobs.values { _ = job.cancel() }
    printJobs.removeAll()
    for state in navigationStates.values { BrowserProfiles.releaseSnapshot(state.store) }
    navigationStates.removeAll()
    for view in views.allObjects { Self.cancel(view) }
    views.removeAllObjects()
    for request in Array(requests.values) { request.cancel() }
    requests.removeAll()
    channel.setMethodCallHandler(nil)
  }

  fileprivate static func record(_ view: WKWebView) -> BrowserRecord? {
    objc_getAssociatedObject(view, &browserRecordAssociation) as? BrowserRecord
  }

  fileprivate func observe(_ view: WKWebView) -> BrowserRecord {
    if let existing = Self.record(view) { return existing }
    let record = BrowserRecord(view: view, owner: self)
    objc_setAssociatedObject(
      view, &browserRecordAssociation, record, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    views.add(view)
    view.navigationDelegate = record
    return record
  }

  static func navigationDelegate(on view: WKWebView) -> WKNavigationDelegate? {
    record(view)?.forward ?? view.navigationDelegate
  }

  static func setNavigationDelegate(_ delegate: WKNavigationDelegate?, on view: WKWebView) {
    if let record = record(view) {
      record.forward = delegate
      view.navigationDelegate = nil
      view.navigationDelegate = record
    } else {
      view.navigationDelegate = delegate
    }
  }

  static func delegatesWindows(_ view: WKWebView) -> Bool {
    record(view)?.delegateWindows == true
  }

  static func createWindow(
    _ view: WKWebView, configuration: WKWebViewConfiguration,
    action: WKNavigationAction
  ) -> WKWebView? {
    guard let parent = record(view), !parent.denyWindows, let owner = parent.owner,
      let source = view as? WebViewImpl
    else { return nil }
    // Keep WebKit's related configuration and store, but never share scripts,
    // message handlers or resource delegates with the opener.
    configuration.userContentController = WKUserContentController()
    configuration.preferences = configuration.preferences.copy() as! WKPreferences
    ResourceSchemeHandler.install(on: configuration)
    let child = WebViewImpl(
      api: source.api, registrar: source.registrar,
      frame: .zero, configuration: configuration)
    let childRecord = owner.observe(child)
    // Related configurations share webpage preferences. Apply the child's
    // content-JavaScript setting to each navigation, leaving the opener's
    // defaults and all other engine-provided policy fields intact.
    childRecord.contentJavaScriptOverride =
      configuration.defaultWebpagePreferences.allowsContentJavaScript
    let pending = BrowserWindow(parent: parent, child: child)
    child.uiDelegate = pending.earlyUIDelegate
    parent.windows[pending.id] = pending
    childRecord.incoming = pending
    pending.startTimeout()
    var event: [String: Any] = ["requestId": pending.id]
    if let url = action.request.url { event["url"] = url.absoluteString }
    owner.emit("newWindowRequested", view: view, arguments: event)
    return child
  }

  static func windowCloseRequested(_ view: WKWebView) {
    guard let record = record(view) else { return }
    record.incoming?.finish(accept: false)
    record.owner?.emit("windowCloseRequested", view: view)
  }

  fileprivate func emit(_ method: String, view: WKWebView, arguments: [String: Any] = [:]) {
    guard
      let identifier = registrar?.instanceManager.identifierWithStrongReference(forInstance: view)
    else { return }
    var event = arguments
    event["webViewId"] = identifier
    channel.invokeMethod(method, arguments: event)
  }
}

private final class BrowserWindow {
  let id = UUID().uuidString
  weak var parent: BrowserRecord?
  let child: WKWebView
  var identifier: Int64?
  var claimed = false
  var resolved = false
  var gates: [(Bool) -> Void] = []
  let earlyUIDelegate = BrowserPendingUIDelegate()
  private var timeout: DispatchWorkItem?

  init(parent: BrowserRecord, child: WKWebView) {
    self.parent = parent
    self.child = child
    earlyUIDelegate.pending = self
  }
  func startTimeout() {
    let timer = DispatchWorkItem { [weak self] in self?.finish(accept: false) }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 25, execute: timer)
  }
  func finish(accept: Bool) {
    guard !resolved else { return }
    resolved = true
    timeout?.cancel()
    timeout = nil
    parent?.windows.removeValue(forKey: id)
    BrowserOperationsChannel.record(child)?.incoming = nil
    let callbacks = gates
    gates.removeAll()
    for callback in callbacks { callback(accept) }
    if !accept { child.stopLoading() }
  }
}

/// Handles window.close before Dart installs the child's normal UI delegate.
private final class BrowserPendingUIDelegate: NSObject, WKUIDelegate {
  weak var pending: BrowserWindow?
  func webViewDidClose(_ webView: WKWebView) { pending?.finish(accept: false) }
}

#if compiler(>=6.0)
  private typealias BrowserPolicyCallback = @MainActor (WKNavigationActionPolicy) -> Void
  private typealias BrowserPreferencesCallback =
    @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
#else
  private typealias BrowserPolicyCallback = (WKNavigationActionPolicy) -> Void
  private typealias BrowserPreferencesCallback = (WKNavigationActionPolicy, WKWebpagePreferences) ->
    Void
#endif

/// Keeps related-window navigation pending until Dart has configured its child.
/// All normal navigation/download callbacks continue through the installed delegate.
private final class BrowserRecord: NSObject, WKNavigationDelegate {
  weak var view: WKWebView?
  weak var owner: BrowserOperationsChannel?
  var forward: WKNavigationDelegate?
  var delegateWindows = false
  var denyWindows = false
  var closed = false
  var contentJavaScriptOverride: Bool?
  var windows: [String: BrowserWindow] = [:]
  weak var incoming: BrowserWindow?
  private var fullscreenObservation: NSKeyValueObservation?
  private var originalFullscreenPreference: Bool?
  private var fullscreen = false
  private var contentRuleList: WKContentRuleList?
  private var ruleGeneration = 0
  private var ruleReply: FlutterResult?
  private var ruleTimeout: DispatchWorkItem?

  func cancelContentRules() {
    ruleGeneration &+= 1
    ruleTimeout?.cancel()
    ruleTimeout = nil
    let reply = ruleReply
    ruleReply = nil
    reply?(false)
  }
  func setContentRules(_ rules: [[String: Any]], result: @escaping FlutterResult) {
    cancelContentRules()
    guard let view, !closed, rules.count <= 256 else {
      result(false)
      return
    }
    if rules.isEmpty {
      if let current = contentRuleList { view.configuration.userContentController.remove(current) }
      contentRuleList = nil
      result(true)
      return
    }
    let names = [
      "document": "document", "image": "image", "styleSheet": "style-sheet", "script": "script",
      "font": "font", "media": "media", "raw": "raw", "svgDocument": "svg-document",
    ]
    var encoded: [[String: Any]] = []
    for rule in rules {
      guard let pattern = rule["urlFilter"] as? String, !pattern.isEmpty, pattern.count <= 8192,
        let action = rule["action"] as? String, ["block", "allow", "hideElements", "upgradeToHttps"].contains(action),
        let types = rule["resourceTypes"] as? [String], types.allSatisfy({ names[$0] != nil })
      else {
        result(false)
        return
      }
      var trigger: [String: Any] = [
        "url-filter": pattern,
        "url-filter-is-case-sensitive": rule["caseSensitive"] as? Bool ?? false,
      ]
      if !types.isEmpty { trigger["resource-type"] = types.map { names[$0]! } }
      let conditions = ["ifDomains": "if-domain", "unlessDomains": "unless-domain",
        "ifTopUrls": "if-top-url", "unlessTopUrls": "unless-top-url", "loadTypes": "load-type"]
      for (input, output) in conditions {
        if let values = rule[input] as? [String], !values.isEmpty { trigger[output] = values }
      }
      var nativeAction: [String: Any] = ["type": ["block": "block", "allow": "ignore-previous-rules",
        "hideElements": "css-display-none", "upgradeToHttps": "make-https"][action]!]
      if action == "hideElements" {
        guard let selector = rule["selector"] as? String, !selector.isEmpty else { result(false); return }
        nativeAction["selector"] = selector
      }
      encoded.append(["trigger": trigger, "action": nativeAction])
    }
    guard let data = try? JSONSerialization.data(withJSONObject: encoded),
      let json = String(data: data, encoding: .utf8)
    else {
      result(false)
      return
    }
    let generation = ruleGeneration
    ruleReply = result
    let timer = DispatchWorkItem { [weak self] in self?.cancelContentRules() }
    ruleTimeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
    let id = "webview_all_" + UUID().uuidString
    let store = WKContentRuleListStore.default()!
    store.compileContentRuleList(forIdentifier: id, encodedContentRuleList: json) {
      [weak self, weak view] list, error in
      // Compiled rules are retained by the user-content controller. Do not
      // leave user-supplied URL patterns in the persistent compiler cache.
      store.removeContentRuleList(forIdentifier: id) { _ in }
      guard let self, let view, !self.closed, self.ruleGeneration == generation else { return }
      self.ruleTimeout?.cancel()
      self.ruleTimeout = nil
      let reply = self.ruleReply
      self.ruleReply = nil
      guard let list, error == nil else {
        reply?(false)
        return
      }
      let controller = view.configuration.userContentController
      if let previous = self.contentRuleList { controller.remove(previous) }
      controller.add(list)
      self.contentRuleList = list
      reply?(true)
    }
  }

  @available(iOS 16.0, macOS 13.0, *)
  func observeFullscreen(enabled: Bool) {
    stopObservingFullscreen()
    guard enabled, let view else { return }
    originalFullscreenPreference = view.configuration.preferences.isElementFullscreenEnabled
    view.configuration.preferences.isElementFullscreenEnabled = true
    fullscreenObservation = view.observe(\.fullscreenState, options: [.initial, .new]) {
      [weak self] view, _ in
      guard let self else { return }
      let active = view.fullscreenState == .inFullscreen
      guard active || view.fullscreenState == .notInFullscreen, active != self.fullscreen else {
        return
      }
      self.fullscreen = active
      self.owner?.emit("fullscreenChanged", view: view, arguments: ["active": active])
    }
  }

  func stopObservingFullscreen() {
    fullscreenObservation?.invalidate()
    fullscreenObservation = nil
    if #available(iOS 15.4, macOS 12.3, *), let value = originalFullscreenPreference {
      view?.configuration.preferences.isElementFullscreenEnabled = value
    }
    originalFullscreenPreference = nil
    fullscreen = false
  }

  init(view: WKWebView, owner: BrowserOperationsChannel) {
    self.view = view
    self.owner = owner
    self.forward = view.navigationDelegate
  }
  func cancelWindows() {
    for pending in Array(windows.values) { pending.finish(accept: false) }
  }
  override func responds(to selector: Selector!) -> Bool {
    super.responds(to: selector) || (forward?.responds(to: selector) ?? false)
  }
  override func forwardingTarget(for selector: Selector!) -> Any? {
    forward?.responds(to: selector) == true ? forward : super.forwardingTarget(for: selector)
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping BrowserPolicyCallback
  ) {
    let decide: (Bool) -> Void = { [weak self, weak webView] accepted in
      guard accepted, let self, !self.closed, let webView else {
        decisionHandler(.cancel)
        return
      }
      if let delegate = self.forward,
        delegate.responds(
          to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:"))
      {
        delegate.webView?(webView, decidePolicyFor: action, decisionHandler: decisionHandler)
      } else {
        decisionHandler(.allow)
      }
    }
    if let pending = incoming, !pending.resolved {
      pending.gates.append(decide)
    } else {
      decide(true)
    }
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    preferences: WKWebpagePreferences,
    decisionHandler: @escaping BrowserPreferencesCallback
  ) {
    let decide: (Bool) -> Void = { [weak self, weak webView] accepted in
      guard accepted, let self, !self.closed, let webView else {
        decisionHandler(.cancel, preferences)
        return
      }
      if let enabled = self.contentJavaScriptOverride {
        preferences.allowsContentJavaScript = enabled
      }
      if let delegate = self.forward,
        delegate.responds(
          to: #selector(
            WKNavigationDelegate.webView(_:decidePolicyFor:preferences:decisionHandler:)))
      {
        delegate.webView?(
          webView, decidePolicyFor: action, preferences: preferences,
          decisionHandler: decisionHandler)
      } else if let delegate = self.forward {
        let callback: BrowserPolicyCallback = { decisionHandler($0, preferences) }
        if delegate.responds(
          to: NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:"))
        {
          delegate.webView?(webView, decidePolicyFor: action, decisionHandler: callback)
        } else {
          decisionHandler(.allow, preferences)
        }
      } else {
        decisionHandler(.allow, preferences)
      }
    }
    if let pending = incoming, !pending.resolved {
      pending.gates.append(decide)
    } else {
      decide(true)
    }
  }
  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    cancelWindows()
    forward?.webView?(webView, didStartProvisionalNavigation: navigation)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    cancelWindows()
    incoming?.finish(accept: false)
    (objc_getAssociatedObject(webView, &browserCaptureAssociation) as? BrowserCapture)?.cancel()
    (webView.uiDelegate as? UIDelegateImpl)?.cancelFileSelections()
    (webView as? WebViewImpl)?.navigationPolicyGeneration &+= 1
    fullscreen = false
    owner?.emit("processFailed", view: webView)
    forward?.webViewWebContentProcessDidTerminate?(webView)
  }
}

private final class BrowserCapture {
  private weak var view: WKWebView?
  private var reply: FlutterResult?
  private var timeout: DispatchWorkItem?
  private(set) var done = false
  private let maxBytes = 64 * 1024 * 1024

  init(view: WKWebView, reply: @escaping FlutterResult) {
    self.view = view
    self.reply = reply
  }

  func start(pdf: Bool, options: [String: Any]? = nil, archive: Bool = false) {
    let timer = DispatchWorkItem { [weak self] in self?.fail("The native capture timed out.") }
    timeout = timer
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timer)
    guard let view else {
      cancel()
      return
    }
    if archive {
      view.createWebArchiveData { [weak self] result in
        switch result {
        case .success(let bytes): self?.complete(bytes)
        case .failure(let error): self?.fail(error.localizedDescription)
        }
      }
      return
    }
    if pdf {
      if let options {
        guard let layout = BrowserPdfLayout(options) else {
          fail("Invalid PDF paper size or margins.")
          return
        }
        exportPaginated(view, layout: layout)
        return
      }
      view.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
        switch result {
        case .success(let bytes): self?.complete(bytes)
        case .failure(let error): self?.fail(error.localizedDescription)
        }
      }
    } else {
      let size = view.bounds.size
      #if os(iOS)
        let scale = max(view.traitCollection.displayScale, 1)
      #else
        let scale = view.window?.backingScaleFactor ?? 2
      #endif
      guard size.width > 0, size.height > 0,
        size.width * size.height * scale * scale <= 16 * 1024 * 1024
      else {
        fail("The viewport is empty or exceeds the capture size limit.")
        return
      }
      let configuration = WKSnapshotConfiguration()
      view.takeSnapshot(with: configuration) { [weak self] image, error in
        if let error {
          self?.fail(error.localizedDescription)
          return
        }
        #if os(iOS)
          self?.complete(image?.pngData())
        #else
          guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
          else {
            self?.fail("The native snapshot could not be encoded.")
            return
          }
          self?.complete(bitmap.representation(using: .png, properties: [:]))
        #endif
      }
    }
  }

  private func exportPaginated(_ view: WKWebView, layout: BrowserPdfLayout) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    do {
      #if os(iOS)
        let renderer = BrowserPrintRenderer(layout: layout)
        renderer.addPrintFormatter(view.viewPrintFormatter(), startingAtPageAt: 0)
        let count = renderer.numberOfPages
        guard count > 0, count <= 2000 else {
          fail("The PDF page count is empty or too large.")
          return
        }
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: count))
        try UIGraphicsPDFRenderer(bounds: renderer.paperRect).writePDF(to: url) { context in
          for page in 0..<count {
            context.beginPage()
            renderer.drawPage(at: page, in: renderer.paperRect)
          }
        }
      #else
        // WebKit's NSPrintOperation can synchronously paginate without a
        // finite page count (for example with percentage-height content).
        // Keep PDF export asynchronous and paginate the engine's vector PDF.
        view.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
          guard let self, !self.done else { return }
          switch result {
          case .success(let data): self.paginate(data, layout: layout)
          case .failure(let error): self.fail(error.localizedDescription)
          }
        }
        return
      #endif
      #if os(iOS)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= maxBytes else {
          fail("The PDF exceeds the output size limit.")
          return
        }
        complete(try Data(contentsOf: url))
      #endif
    } catch { fail(error.localizedDescription) }
  }

  #if os(macOS)
    private func paginate(_ data: Data, layout: BrowserPdfLayout) {
      guard data.count <= maxBytes, let provider = CGDataProvider(data: data as CFData),
        let document = CGPDFDocument(provider), document.numberOfPages > 0,
        document.numberOfPages <= 2000
      else {
        fail("The native PDF is empty or exceeds the capture limits.")
        return
      }
      let width = layout.paper.width - layout.left - layout.right
      let height = layout.paper.height - layout.top - layout.bottom
      var total = 0
      for index in 1...document.numberOfPages {
        guard let page = document.page(at: index) else {
          fail("Invalid PDF page.")
          return
        }
        let bounds = page.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0, bounds.width.isFinite, bounds.height.isFinite
        else {
          fail("Invalid PDF page dimensions.")
          return
        }
        let turns = abs(page.rotationAngle) % 180 != 0
        let scaledHeight =
          (turns ? bounds.width / bounds.height : bounds.height / bounds.width) * width
        let count = ceil(scaledHeight / height)
        guard count.isFinite, count > 0, count <= 2000 - Double(total) else {
          fail("The PDF exceeds the 2000 page limit.")
          return
        }
        total += Int(count)
      }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString + ".pdf")
      defer { try? FileManager.default.removeItem(at: url) }
      var paper = CGRect(origin: .zero, size: layout.paper)
      guard let output = CGContext(url as CFURL, mediaBox: &paper, nil) else {
        fail("Cannot create a PDF output.")
        return
      }
      for index in 1...document.numberOfPages {
        guard let page = document.page(at: index) else { continue }
        let bounds = page.getBoxRect(.mediaBox)
        let turns = abs(page.rotationAngle) % 180 != 0
        let scaledHeight =
          (turns ? bounds.width / bounds.height : bounds.height / bounds.width) * width
        let count = Int(ceil(scaledHeight / height))
        for slice in 0..<count {
          output.beginPDFPage(nil)
          output.saveGState()
          output.clip(to: CGRect(x: layout.left, y: layout.bottom, width: width, height: height))
          let target = CGRect(
            x: layout.left, y: layout.bottom + height - scaledHeight + CGFloat(slice) * height,
            width: width, height: scaledHeight)
          output.concatenate(
            page.getDrawingTransform(.mediaBox, rect: target, rotate: 0, preserveAspectRatio: true))
          output.drawPDFPage(page)
          output.restoreGState()
          output.endPDFPage()
          if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber, size.intValue > maxBytes
          {
            output.closePDF()
            fail("The PDF exceeds the output size limit.")
            return
          }
        }
      }
      output.closePDF()
      do { complete(try Data(contentsOf: url)) } catch { fail(error.localizedDescription) }
    }
  #endif

  func cancel() { fail("The WebView was disposed or the Flutter engine closed.") }

  private func complete(_ data: Data?) {
    guard let data, !data.isEmpty, data.count <= maxBytes else {
      fail("The capture is empty or exceeds the output size limit.")
      return
    }
    finish(FlutterStandardTypedData(bytes: data))
  }

  private func fail(_ message: String) {
    finish(FlutterError(code: "capture_failed", message: message, details: nil))
  }

  private func finish(_ value: Any?) {
    guard !done else { return }
    done = true
    timeout?.cancel()
    timeout = nil
    let completion = reply
    reply = nil
    completion?(value)
  }
}

private struct BrowserPdfLayout {
  let paper: CGSize
  let top: CGFloat, bottom: CGFloat, left: CGFloat, right: CGFloat
  init?(_ options: [String: Any]) {
    guard let w = options["paperWidth"] as? Double, let h = options["paperHeight"] as? Double,
      let t = options["marginTop"] as? Double, let b = options["marginBottom"] as? Double,
      let l = options["marginLeft"] as? Double, let r = options["marginRight"] as? Double,
      [w, h, t, b, l, r].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 14400 })
    else { return nil }
    let landscape = options["landscape"] as? Bool == true
    paper = CGSize(width: landscape ? h : w, height: landscape ? w : h)
    guard paper.width > l + r, paper.height > t + b else { return nil }
    top = t
    bottom = b
    left = l
    right = r
  }
}

#if os(iOS)
  private final class BrowserPrintRenderer: UIPrintPageRenderer {
    let layout: BrowserPdfLayout
    init(layout: BrowserPdfLayout) {
      self.layout = layout
      super.init()
    }
    override var paperRect: CGRect { CGRect(origin: .zero, size: layout.paper) }
    override var printableRect: CGRect {
      CGRect(
        x: layout.left, y: layout.top,
        width: layout.paper.width - layout.left - layout.right,
        height: layout.paper.height - layout.top - layout.bottom)
    }
  }
#endif

private enum BrowserWebsiteData {
  static let types: [Set<String>] = [
    [WKWebsiteDataTypeCookies],
    [
      WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeDiskCache,
      WKWebsiteDataTypeOfflineWebApplicationCache,
    ],
    [WKWebsiteDataTypeLocalStorage], [WKWebsiteDataTypeSessionStorage],
    [WKWebsiteDataTypeIndexedDBDatabases], [WKWebsiteDataTypeWebSQLDatabases],
    [WKWebsiteDataTypeFetchCache], [WKWebsiteDataTypeServiceWorkerRegistrations],
  ]
  static func handle(
    store: WKWebsiteDataStore, args: [String: Any], clearing: Bool, result: @escaping FlutterResult
  ) {
    let requested = args["dataTypes"] as? [Int] ?? []
    let target = args["target"] as? [String: Any]
    if let target, target["scope"] as? String != "domain" {
      result(
        FlutterError(
          code: "unsupported_scope",
          message: "WebKit records use domain scope; an exact origin is never widened.",
          details: nil))
      return
    }
    let name = target?["value"] as? String
    if clearing && (name == nil || name!.isEmpty) {
      result(
        FlutterError(code: "invalid_target", message: "A domain record is required.", details: nil))
      return
    }
    let selected = requested.reduce(into: Set<String>()) { $0.formUnion(types[$1]) }
    store.fetchDataRecords(ofTypes: selected) { all in
      let records = all.filter { name == nil || $0.displayName == name }
      if clearing {
        store.removeData(ofTypes: selected, for: records) { result(nil) }
      } else {
        guard records.count <= 4096 else {
          result(
            FlutterError(
              code: "record_limit",
              message: "The store exceeds the record-list limit; request a specific domain.",
              details: nil))
          return
        }
        result(
          records.map { record in
            [
              "scope": "domain", "value": record.displayName,
              "dataTypes": requested.filter { !record.dataTypes.isDisjoint(with: types[$0]) },
            ] as [String: Any]
          })
      }
    }
  }
}

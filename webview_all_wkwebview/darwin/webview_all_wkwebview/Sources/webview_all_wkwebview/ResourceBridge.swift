import Foundation
import ObjectiveC
import WebKit

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

final class ResourceBridgeChannel {
  private let channel: FlutterMethodChannel
  private weak var registrar: ProxyAPIRegistrar?
  private let messenger: FlutterBinaryMessenger
  private let handlers = NSHashTable<ResourceSchemeHandler>.weakObjects()

  init(registrar: ProxyAPIRegistrar, messenger: FlutterBinaryMessenger) {
    self.registrar = registrar
    self.messenger = messenger
    channel = FlutterMethodChannel(
      name: "com.abandoft.webview_all/resources", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      let custom = call.method == "configureSchemes"
      guard let self, call.method == "configure" || custom,
        let args = call.arguments as? [String: Any],
        let identifier = args["webViewId"] as? NSNumber,
        let view: WKWebView = self.registrar?.instanceManager.instance(
          forIdentifier: identifier.int64Value),
        view.configuration.urlSchemeHandler(
          forURLScheme: ResourceSchemeHandler.scheme) is ResourceSchemeRouter,
        let name = args["channel"] as? String,
        let enabled = args["enabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "invalid_resource_configuration",
            message: "Unknown WebView or resource configuration.", details: nil))
        return
      }
      let schemes = args["schemes"] as? [String] ?? []
      if custom
        && (schemes.isEmpty
          || schemes.contains(where: {
            !(view.configuration.urlSchemeHandler(forURLScheme: $0) is ResourceSchemeRouter)
          }))
      {
        result(false)
        return
      }
      let handler = ResourceSchemeHandler.forView(view, custom: custom)
      handler.configure(
        name: name, host: args["host"] as? String ?? "", enabled: enabled,
        messenger: self.messenger, schemes: custom ? Set(schemes) : [])
      self.handlers.add(handler)
      result(custom ? true : nil)
    }
  }

  func close() {
    channel.setMethodCallHandler(nil)
    for handler in handlers.allObjects { handler.close() }
    handlers.removeAllObjects()
  }
}

/// The reserved scheme is installed before WKWebView copies its configuration.
/// No callbacks reach Dart until an application explicitly enables a delegate.
private var resourceStateAssociation: UInt8 = 0
private var customResourceStateAssociation: UInt8 = 0

/// A configuration (including WebKit's related-window configuration) may share
/// a router. Every view still owns its own delegate, host and pending tasks.
private final class ResourceSchemeRouter: NSObject, WKURLSchemeHandler {
  let custom: Bool
  init(custom: Bool = false) { self.custom = custom }
  func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
    ResourceSchemeHandler.forView(webView, custom: custom).webView(webView, start: task)
  }
  func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
    ResourceSchemeHandler.existing(webView, custom: custom)?.webView(webView, stop: task)
  }
}

final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "webview-all-resource"
  private var channel: FlutterMethodChannel?
  private var host = ""
  private var enabled = false
  private var channelName = ""
  private var customSchemes: Set<String> = []
  private var requests: [ObjectIdentifier: ResourceTask] = [:]

  private final class ResourceTask {
    let task: WKURLSchemeTask
    let id = UUID().uuidString
    var timeout: DispatchWorkItem?
    init(_ task: WKURLSchemeTask) { self.task = task }
  }

  static func install(on configuration: WKWebViewConfiguration) {
    if configuration.urlSchemeHandler(forURLScheme: scheme) == nil {
      configuration.setURLSchemeHandler(ResourceSchemeRouter(), forURLScheme: scheme)
    }
  }
  static func installCustom(_ schemes: [String], on configuration: WKWebViewConfiguration) {
    for name in schemes where configuration.urlSchemeHandler(forURLScheme: name) == nil {
      configuration.setURLSchemeHandler(ResourceSchemeRouter(custom: true), forURLScheme: name)
    }
  }

  static func configuration(from initial: WKWebViewConfiguration) -> WKWebViewConfiguration {
    let configuration = initial.copy() as! WKWebViewConfiguration
    // Public WebKit APIs cannot replace an already registered scheme handler.
    // The stateless router safely handles reused and related configurations.
    install(on: configuration)
    return configuration
  }

  static func close(_ view: WKWebView) {
    existing(view)?.close()
    objc_setAssociatedObject(
      view, &resourceStateAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    existing(view, custom: true)?.close()
    objc_setAssociatedObject(
      view, &customResourceStateAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
  }

  static func existing(_ view: WKWebView, custom: Bool = false) -> ResourceSchemeHandler? {
    if custom {
      return objc_getAssociatedObject(view, &customResourceStateAssociation)
        as? ResourceSchemeHandler
    }
    return objc_getAssociatedObject(view, &resourceStateAssociation) as? ResourceSchemeHandler
  }

  static func forView(_ view: WKWebView, custom: Bool = false) -> ResourceSchemeHandler {
    if let handler = existing(view, custom: custom) { return handler }
    let handler = ResourceSchemeHandler()
    if custom {
      objc_setAssociatedObject(
        view, &customResourceStateAssociation, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      return handler
    }
    objc_setAssociatedObject(
      view, &resourceStateAssociation, handler, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return handler
  }

  func configure(
    name: String, host: String, enabled: Bool, messenger: FlutterBinaryMessenger,
    schemes: Set<String> = []
  ) {
    if !enabled && name != channelName { return }
    cancelAll()
    self.channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channelName = name
    customSchemes = schemes
    self.host = host
    self.enabled = enabled
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard enabled, let channel, let url = urlSchemeTask.request.url,
      customSchemes.isEmpty
        ? url.scheme == Self.scheme && url.host == host && url.port == nil
        : customSchemes.contains(url.scheme ?? ""),
      url.user == nil, url.password == nil
    else {
      urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
      return
    }
    let request = ResourceTask(urlSchemeTask)
    let key = ObjectIdentifier(urlSchemeTask)
    requests[key] = request
    armTimeout(request)
    let method = (urlSchemeTask.request.httpMethod ?? "GET").uppercased()
    let nativeBody = urlSchemeTask.request.httpBody
    // WebKit may omit POST bodies from NSURLRequest. Nil is not evidence of
    // an empty POST; only GET/HEAD can report a known empty body here.
    let bodyAvailable =
      urlSchemeTask.request.httpBodyStream == nil
      && (nativeBody != nil || method == "GET" || method == "HEAD")
      && (nativeBody?.count ?? 0) <= 4 * 1024 * 1024
    channel.invokeMethod(
      "open",
      arguments: [
        "id": request.id, "uri": url.absoluteString,
        "method": urlSchemeTask.request.httpMethod ?? "GET",
        "headers": urlSchemeTask.request.allHTTPHeaderFields ?? [:],
        "bodyAvailable": bodyAvailable,
        "body": bodyAvailable ? FlutterStandardTypedData(bytes: nativeBody ?? Data()) : NSNull(),
      ]
    ) { [weak self, weak request] value in
      guard let self, let request, self.requests[key] === request else { return }
      guard let metadata = value as? [String: Any],
        let status = metadata["statusCode"] as? Int,
        let headers = metadata["headers"] as? [String: String],
        let response = HTTPURLResponse(
          url: url, statusCode: status,
          httpVersion: "HTTP/1.1", headerFields: headers)
      else {
        self.fail(request)
        return
      }
      request.task.didReceive(response)
      if request.task.request.httpMethod == "HEAD"
        || (metadata["contentLength"] as? Int) == 0
      {
        self.finish(request)
      } else {
        self.read(request)
      }
    }
  }

  private func read(_ request: ResourceTask) {
    guard requests[ObjectIdentifier(request.task)] === request, let channel else { return }
    armTimeout(request)
    channel.invokeMethod("read", arguments: ["id": request.id, "length": 65536]) {
      [weak self, weak request] value in
      guard let self, let request,
        self.requests[ObjectIdentifier(request.task)] === request
      else { return }
      if value == nil || value is NSNull {
        self.finish(request)
      } else if let bytes = value as? FlutterStandardTypedData, !bytes.data.isEmpty {
        request.task.didReceive(bytes.data)
        // Keep one channel request outstanding, and allow stop callbacks to run.
        DispatchQueue.main.async { [weak self, weak request] in
          if let request { self?.read(request) }
        }
      } else {
        self.fail(request)
      }
    }
  }

  private func armTimeout(_ request: ResourceTask) {
    request.timeout?.cancel()
    let work = DispatchWorkItem { [weak self, weak request] in
      if let request { self?.fail(request, code: .timedOut) }
    }
    request.timeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
  }

  private func remove(_ request: ResourceTask) -> Bool {
    guard requests.removeValue(forKey: ObjectIdentifier(request.task)) === request else {
      return false
    }
    request.timeout?.cancel()
    request.timeout = nil
    channel?.invokeMethod("cancel", arguments: ["id": request.id])
    return true
  }

  private func finish(_ request: ResourceTask) {
    if remove(request) { request.task.didFinish() }
  }

  private func fail(_ request: ResourceTask, code: URLError.Code = .cannotLoadFromNetwork) {
    if remove(request) { request.task.didFailWithError(URLError(code)) }
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
    if let request = requests[ObjectIdentifier(urlSchemeTask)] { _ = remove(request) }
  }

  private func cancelAll() {
    for request in Array(requests.values) { fail(request, code: .cancelled) }
  }

  func close() {
    enabled = false
    cancelAll()
    channel?.invokeMethod("closed", arguments: nil)
    channel = nil
  }
}

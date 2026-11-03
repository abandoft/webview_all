import Foundation
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
      guard let self, call.method == "configure",
        let args = call.arguments as? [String: Any],
        let identifier = args["webViewId"] as? NSNumber,
        let view: WKWebView = self.registrar?.instanceManager.instance(
          forIdentifier: identifier.int64Value),
        let handler = view.configuration.urlSchemeHandler(
          forURLScheme: ResourceSchemeHandler.scheme) as? ResourceSchemeHandler,
        let name = args["channel"] as? String, let host = args["host"] as? String,
        let enabled = args["enabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "invalid_resource_configuration",
            message: "Unknown WebView or resource configuration.", details: nil))
        return
      }
      handler.configure(name: name, host: host, enabled: enabled, messenger: self.messenger)
      self.handlers.add(handler)
      result(nil)
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
final class ResourceSchemeHandler: NSObject, WKURLSchemeHandler {
  static let scheme = "webview-all-resource"
  private var channel: FlutterMethodChannel?
  private var host = ""
  private var enabled = false
  private var requests: [ObjectIdentifier: ResourceTask] = [:]

  private final class ResourceTask {
    let task: WKURLSchemeTask
    let id = UUID().uuidString
    var timeout: DispatchWorkItem?
    init(_ task: WKURLSchemeTask) { self.task = task }
  }

  static func install(on configuration: WKWebViewConfiguration) {
    if configuration.urlSchemeHandler(forURLScheme: scheme) == nil {
      configuration.setURLSchemeHandler(ResourceSchemeHandler(), forURLScheme: scheme)
    }
  }

  static func configuration(from initial: WKWebViewConfiguration) -> WKWebViewConfiguration {
    let configuration = initial.copy() as! WKWebViewConfiguration
    // Configuration copies retain their scheme handler objects. A reused
    // creation configuration must not share one controller's channel or host.
    if configuration.urlSchemeHandler(forURLScheme: scheme) is ResourceSchemeHandler {
      configuration.setURLSchemeHandler(nil, forURLScheme: scheme)
    }
    install(on: configuration)
    return configuration
  }

  static func close(_ view: WKWebView) {
    (view.configuration.urlSchemeHandler(forURLScheme: scheme) as? ResourceSchemeHandler)?.close()
  }

  func configure(name: String, host: String, enabled: Bool, messenger: FlutterBinaryMessenger) {
    cancelAll()
    self.channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    self.host = host
    self.enabled = enabled
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard enabled, let channel, let url = urlSchemeTask.request.url,
      url.scheme == Self.scheme, url.host == host,
      url.port == nil, url.user == nil, url.password == nil
    else {
      urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
      return
    }
    let request = ResourceTask(urlSchemeTask)
    let key = ObjectIdentifier(urlSchemeTask)
    requests[key] = request
    armTimeout(request)
    channel.invokeMethod(
      "open",
      arguments: [
        "id": request.id, "uri": url.absoluteString,
        "method": urlSchemeTask.request.httpMethod ?? "GET",
        "headers": urlSchemeTask.request.allHTTPHeaderFields ?? [:],
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

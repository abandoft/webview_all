// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

private func normalizedJavaScriptError(_ error: NSError) -> (
  name: String?, message: String, stack: String?
) {
  var name = error.userInfo["WKJavaScriptExceptionName"] as? String
  var message =
    error.userInfo["WKJavaScriptExceptionMessage"] as? String
    ?? error.localizedDescription
  let stack = error.userInfo["WKJavaScriptExceptionStackTrace"] as? String

  if name == nil, let separator = message.firstIndex(of: ":") {
    let candidate = String(message[..<separator])
    if candidate.hasSuffix("Error") && !candidate.contains(where: { $0.isWhitespace }) {
      name = candidate
      let remainder = message[message.index(after: separator)...]
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !remainder.isEmpty {
        message = remainder
      }
    }
  }

  return (name, message, stack)
}

#if os(macOS)
  import AppKit
#endif

class WebViewImpl: WKWebView {
  let api: PigeonApiProtocolWKWebView
  unowned let registrar: ProxyAPIRegistrar

  init(
    api: PigeonApiProtocolWKWebView, registrar: ProxyAPIRegistrar, frame: CGRect,
    configuration: WKWebViewConfiguration
  ) {
    self.api = api
    self.registrar = registrar
    super.init(frame: frame, configuration: configuration)
    #if os(iOS)
      scrollView.contentInsetAdjustmentBehavior = .never
      scrollView.automaticallyAdjustsScrollIndicatorInsets = false
    #endif
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func observeValue(
    forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
    context: UnsafeMutableRawPointer?
  ) {
    NSObjectImpl.handleObserveValue(
      withApi: (api as! PigeonApiWKWebView).pigeonApiNSObject, registrar: registrar,
      instance: self as NSObject,
      forKeyPath: keyPath, of: object, change: change, context: context)
  }

  override var frame: CGRect {
    get {
      return super.frame
    }
    set {
      super.frame = newValue
      #if os(iOS)
        // Prevents the contentInsets from being adjusted by iOS and gives control to Flutter.
        scrollView.contentInset = .zero

        // Adjust contentInset to compensate the adjustedContentInset so the sum will
        //  always be 0.
        if scrollView.adjustedContentInset != .zero {
          let insetToAdjust = scrollView.adjustedContentInset
          scrollView.contentInset = UIEdgeInsets(
            top: -insetToAdjust.top, left: -insetToAdjust.left, bottom: -insetToAdjust.bottom,
            right: -insetToAdjust.right)
        }
      #endif
    }
  }
}

/// ProxyApi implementation for `WKWebView`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class WebViewProxyAPIDelegate: PigeonApiDelegateWKWebView, PigeonApiDelegateUIViewWKWebView,
  PigeonApiDelegateNSViewWKWebView
{
  func getUIViewWKWebViewAPI(_ api: PigeonApiNSViewWKWebView) -> PigeonApiUIViewWKWebView {
    return api.pigeonRegistrar.apiDelegate.pigeonApiUIViewWKWebView(api.pigeonRegistrar)
  }

  #if os(iOS)
    func scrollView(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws
      -> UIScrollView
    {
      return pigeonInstance.scrollView
    }
  #endif

  func pigeonDefaultConstructor(
    pigeonApi: PigeonApiUIViewWKWebView, initialConfiguration: WKWebViewConfiguration
  ) throws -> WKWebView {
    return WebViewImpl(
      api: pigeonApi.pigeonApiWKWebView, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar,
      frame: CGRect(), configuration: initialConfiguration)
  }

  func pigeonDefaultConstructor(
    pigeonApi: PigeonApiNSViewWKWebView, initialConfiguration: WKWebViewConfiguration
  ) throws -> WKWebView {
    return try pigeonDefaultConstructor(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), initialConfiguration: initialConfiguration)
  }

  func configuration(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView)
    -> WKWebViewConfiguration
  {
    return pigeonInstance.configuration
  }

  func configuration(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws
    -> WKWebViewConfiguration
  {
    return configuration(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func setUIDelegate(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, delegate: WKUIDelegate
  ) throws {
    pigeonInstance.uiDelegate = delegate
  }

  func setUIDelegate(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, delegate: WKUIDelegate
  ) throws {
    try setUIDelegate(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      delegate: delegate)
  }

  func setNavigationDelegate(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, delegate: WKNavigationDelegate
  ) throws {
    pigeonInstance.navigationDelegate = delegate
  }

  func setNavigationDelegate(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView,
    delegate: WKNavigationDelegate
  ) throws {
    try setNavigationDelegate(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      delegate: delegate)
  }

  func getUrl(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws -> String? {
    return pigeonInstance.url?.absoluteString
  }

  func getUrl(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws -> String? {
    return try getUrl(pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func getEstimatedProgress(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws
    -> Double
  {
    return pigeonInstance.estimatedProgress
  }

  func getEstimatedProgress(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws
    -> Double
  {
    return try getEstimatedProgress(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func load(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, request: URLRequestWrapper
  ) throws {
    pigeonInstance.load(request.value)
  }

  func load(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, request: URLRequestWrapper
  ) throws {
    try load(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, request: request)
  }

  func loadHtmlString(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, string: String, baseUrl: String?
  ) throws {
    pigeonInstance.loadHTMLString(string, baseURL: baseUrl != nil ? URL(string: baseUrl!)! : nil)
  }

  func loadHtmlString(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, string: String, baseUrl: String?
  ) throws {
    try loadHtmlString(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, string: string,
      baseUrl: baseUrl)
  }

  func loadFileUrl(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, url: String,
    readAccessUrl: String
  ) throws {
    let fileURL = URL(fileURLWithPath: url, isDirectory: false)
    let readAccessURL = URL(fileURLWithPath: readAccessUrl, isDirectory: true)

    pigeonInstance.loadFileURL(fileURL, allowingReadAccessTo: readAccessURL)
  }

  func loadFileUrl(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, url: String,
    readAccessUrl: String
  ) throws {
    try loadFileUrl(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, url: url,
      readAccessUrl: readAccessUrl)
  }

  func loadFlutterAsset(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, key: String)
    throws
  {
    let registrar = pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar
    let url = registrar.assetManager.urlForAsset(key)

    if let url = url {
      pigeonInstance.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    } else {
      let assetFilePath = registrar.assetManager.lookupKeyForAsset(key)
      throw PigeonError(
        code: "FWFURLParsingError",
        message: "Failed to find asset with filepath: `\(String(describing: assetFilePath))`.",
        details: nil)
    }
  }

  func loadFlutterAsset(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, key: String)
    throws
  {
    try loadFlutterAsset(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, key: key)
  }

  func canGoBack(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws -> Bool {
    return pigeonInstance.canGoBack
  }

  func canGoBack(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws -> Bool {
    return try canGoBack(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func canGoForward(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws -> Bool {
    return pigeonInstance.canGoForward
  }

  func canGoForward(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws -> Bool {
    return try canGoForward(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func goBack(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws {
    pigeonInstance.goBack()
  }

  func goBack(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws {
    try goBack(pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func goForward(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws {
    pigeonInstance.goForward()
  }

  func goForward(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws {
    try goForward(pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func reload(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws {
    pigeonInstance.reload()
  }

  func reload(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws {
    try reload(pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func getTitle(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws -> String? {
    return pigeonInstance.title
  }

  func getTitle(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws -> String? {
    return try getTitle(pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func setAllowsBackForwardNavigationGestures(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, allow: Bool
  ) throws {
    pigeonInstance.allowsBackForwardNavigationGestures = allow
  }

  func setAllowsBackForwardNavigationGestures(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, allow: Bool
  ) throws {
    try setAllowsBackForwardNavigationGestures(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, allow: allow)
  }

  func setCustomUserAgent(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, userAgent: String?
  ) throws {
    pigeonInstance.customUserAgent = userAgent
  }

  func setCustomUserAgent(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, userAgent: String?
  ) throws {
    try setCustomUserAgent(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      userAgent: userAgent)
  }

  func evaluateJavaScript(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, javaScriptString: String,
    completion: @escaping (Result<Any?, Error>) -> Void
  ) {
    pigeonInstance.evaluateJavaScript(javaScriptString) { result, error in
      if error == nil {
        if let optionalResult = result as Any?? {
          switch optionalResult {
          case .none:
            completion(.success(nil))
          case .some(let value):
            if value is String || value is NSNumber {
              completion(.success(value))
            } else {
              let className = String(describing: value)
              debugPrint(
                "Return type of evaluateJavaScript is not directly supported: \(className). Returned description of value."
              )
              completion(.success((value as AnyObject).description))
            }
          }
        }
      } else {
        let error = PigeonError(
          code: "FWFEvaluateJavaScriptError", message: "Failed evaluating JavaScript.",
          details: error! as NSError)
        completion(.failure(error))
      }
    }
  }

  func callAsyncJavaScript(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, functionBody: String,
    arguments: [String: Any?], completion: @escaping (Result<Any?, Error>) -> Void
  ) {
    guard #available(iOS 14.0, macOS 11.0, *) else {
      completion(
        .failure(
          PigeonError(
            code: "FWFCallAsyncJavaScriptUnavailable",
            message: "WKWebView.callAsyncJavaScript is unavailable on this operating system.",
            details: nil)))
      return
    }

    let nativeArguments = arguments.mapValues { value in value ?? NSNull() }
    pigeonInstance.callAsyncJavaScript(
      functionBody, arguments: nativeArguments, in: nil, in: .page
    ) { result in
      switch result {
      case .success(let value):
        completion(.success(value))
      case .failure(let error):
        let nativeError = error as NSError
        let normalizedError = normalizedJavaScriptError(nativeError)
        var details: [String: Any] = [
          "domain": nativeError.domain,
          "code": nativeError.code,
          "description": nativeError.localizedDescription,
          "message": normalizedError.message,
        ]
        if let name = normalizedError.name {
          details["name"] = name
        }
        if let stack = normalizedError.stack {
          details["stack"] = stack
        }
        completion(
          .failure(
            PigeonError(
              code: "FWFCallAsyncJavaScriptError",
              message: nativeError.localizedDescription,
              details: details)))
      }
    }
  }

  func dispose(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws {
    pigeonInstance.stopLoading()
    pigeonInstance.navigationDelegate = nil
    pigeonInstance.uiDelegate = nil
    pigeonInstance.removeFromSuperview()
  }

  func evaluateJavaScript(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, javaScriptString: String,
    completion: @escaping (Result<Any?, Error>) -> Void
  ) {
    evaluateJavaScript(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      javaScriptString: javaScriptString, completion: completion)
  }

  func callAsyncJavaScript(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, functionBody: String,
    arguments: [String: Any?], completion: @escaping (Result<Any?, Error>) -> Void
  ) {
    callAsyncJavaScript(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      functionBody: functionBody, arguments: arguments, completion: completion)
  }

  func dispose(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws {
    try dispose(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func setInspectable(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, inspectable: Bool
  ) throws -> Bool {
    if #available(iOS 16.4, macOS 13.3, *) {
      pigeonInstance.isInspectable = inspectable
      if pigeonInstance.responds(to: Selector(("isInspectable:"))) {
        pigeonInstance.perform(Selector(("isInspectable:")), with: inspectable)
      }
      return true
    } else {
      return false
    }
  }

  func setInspectable(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, inspectable: Bool
  ) throws -> Bool {
    return try setInspectable(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance,
      inspectable: inspectable)
  }

  func setUnderPageBackgroundColor(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, red: Double, green: Double,
    blue: Double, alpha: Double
  ) throws -> Bool {
    #if os(macOS)
      if #available(macOS 12.0, *) {
        pigeonInstance.underPageBackgroundColor = NSColor(
          red: red, green: green, blue: blue, alpha: alpha)
        return true
      }
    #endif
    return false
  }

  func setAllowsMagnification(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, allow: Bool
  ) throws {
    #if os(macOS)
      pigeonInstance.allowsMagnification = allow
    #endif
  }

  func getCustomUserAgent(pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView) throws
    -> String?
  {
    return pigeonInstance.customUserAgent
  }

  func getCustomUserAgent(pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView) throws
    -> String?
  {
    return try getCustomUserAgent(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance)
  }

  func setAllowsLinkPreview(
    pigeonApi: PigeonApiUIViewWKWebView, pigeonInstance: WKWebView, allow: Bool
  ) throws {
    pigeonInstance.allowsLinkPreview = allow
  }

  func setAllowsLinkPreview(
    pigeonApi: PigeonApiNSViewWKWebView, pigeonInstance: WKWebView, allow: Bool
  ) throws {
    try setAllowsLinkPreview(
      pigeonApi: getUIViewWKWebViewAPI(pigeonApi), pigeonInstance: pigeonInstance, allow: allow)
  }
}

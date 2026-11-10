// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import WebKit

/// Implementation of `WKUIDelegate` that calls to Dart in callback methods.
class UIDelegateImpl: NSObject, WKUIDelegate {
  let api: PigeonApiProtocolWKUIDelegate
  unowned let registrar: ProxyAPIRegistrar

  var fileSelectorEnabled = false
  private var pendingFileSelections: [UUID: ([URL]?) -> Void] = [:]

  override func responds(to selector: Selector!) -> Bool {
    if NSStringFromSelector(selector)
      == "webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:"
    {
      return fileSelectorEnabled
    }
    return super.responds(to: selector)
  }

  func cancelFileSelections() {
    let pending = Array(pendingFileSelections.values)
    pendingFileSelections.removeAll()
    pending.forEach { $0(nil) }
  }

  #if os(macOS) || compiler(>=6.1)
    @available(iOS 18.4, macOS 10.12, *)
    private func selectFiles(
      _ parameters: WKOpenPanelParameters, completion: @escaping ([URL]?) -> Void
    ) {
      let request = UUID()
      pendingFileSelections[request] = completion
      registrar.dispatchOnMainThread { [weak self] onFailure in
        guard let self = self else { return }
        self.api.onFileSelector(
          pigeonInstance: self, multiple: parameters.allowsMultipleSelection,
          directories: parameters.allowsDirectories
        ) { [weak self] result in
          DispatchQueue.main.async {
            guard let complete = self?.pendingFileSelections.removeValue(forKey: request) else {
              return
            }
            switch result {
            case .success(let paths):
              let urls = (paths ?? []).compactMap { value -> URL? in
                let parsed = URL(string: value)
                let url: URL
                if parsed?.isFileURL == true {
                  url = parsed!
                } else if value.hasPrefix("/") {
                  url = URL(fileURLWithPath: value)
                } else {
                  return nil
                }
                guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
                var directory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                if directory.boolValue && !parameters.allowsDirectories { return nil }
                return url
              }
              complete(
                urls.isEmpty
                  ? nil : parameters.allowsMultipleSelection ? urls : Array(urls.prefix(1)))
            case .failure(let error):
              complete(nil)
              onFailure("WKUIDelegate.onFileSelector", error)
            }
          }
        }
      }
    }
    #if compiler(>=6.0)
      @available(iOS 18.4, macOS 10.12, *)
      func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
      ) {
        selectFiles(parameters) { values in DispatchQueue.main.async { completionHandler(values) } }
      }
    #else
      @available(macOS 10.12, *)
      func webView(
        _ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void
      ) {
        selectFiles(parameters, completion: completionHandler)
      }
    #endif
  #endif

  init(api: PigeonApiProtocolWKUIDelegate, registrar: ProxyAPIRegistrar) {
    self.api = api
    self.registrar = registrar
  }

  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if BrowserOperationsChannel.delegatesWindows(webView) {
      return BrowserOperationsChannel.createWindow(
        webView, configuration: configuration, action: navigationAction)
    }
    registrar.dispatchOnMainThread { onFailure in
      self.api.onCreateWebView(
        pigeonInstance: self, webView: webView, configuration: configuration,
        navigationAction: navigationAction
      ) { result in
        if case .failure(let error) = result {
          onFailure("WKUIDelegate.onCreateWebView", error)
        }
      }
    }
    return nil
  }

  func webViewDidClose(_ webView: WKWebView) {
    BrowserOperationsChannel.windowCloseRequested(webView)
  }

  #if compiler(>=6.0)
    @available(iOS 15.0, macOS 12.0, *)
    func webView(
      _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
      decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
      let wrapperCaptureType: MediaCaptureType
      switch type {
      case .camera:
        wrapperCaptureType = .camera
      case .microphone:
        wrapperCaptureType = .microphone
      case .cameraAndMicrophone:
        wrapperCaptureType = .cameraAndMicrophone
      @unknown default:
        wrapperCaptureType = .unknown
      }

      registrar.dispatchOnMainThread { onFailure in
        self.api.requestMediaCapturePermission(
          pigeonInstance: self, webView: webView, origin: origin, frame: frame,
          type: wrapperCaptureType
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let decision):
              switch decision {
              case .deny:
                decisionHandler(.deny)
              case .grant:
                decisionHandler(.grant)
              case .prompt:
                decisionHandler(.prompt)
              }
            case .failure(let error):
              decisionHandler(.deny)
              onFailure("WKUIDelegate.requestMediaCapturePermission", error)
            }
          }
        }
      }
    }
  #else
    @available(iOS 15.0, macOS 12.0, *)
    func webView(
      _ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
      initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
      decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
      let wrapperCaptureType: MediaCaptureType
      switch type {
      case .camera:
        wrapperCaptureType = .camera
      case .microphone:
        wrapperCaptureType = .microphone
      case .cameraAndMicrophone:
        wrapperCaptureType = .cameraAndMicrophone
      @unknown default:
        wrapperCaptureType = .unknown
      }

      registrar.dispatchOnMainThread { onFailure in
        self.api.requestMediaCapturePermission(
          pigeonInstance: self, webView: webView, origin: origin, frame: frame,
          type: wrapperCaptureType
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let decision):
              switch decision {
              case .deny:
                decisionHandler(.deny)
              case .grant:
                decisionHandler(.grant)
              case .prompt:
                decisionHandler(.prompt)
              }
            case .failure(let error):
              decisionHandler(.deny)
              onFailure("WKUIDelegate.requestMediaCapturePermission", error)
            }
          }
        }
      }
    }
  #endif

  #if compiler(>=6.0)
    func webView(
      _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptAlertPanel(
          pigeonInstance: self, webView: webView, message: message, frame: frame
        ) { result in
          DispatchQueue.main.async {
            if case .failure(let error) = result {
              onFailure("WKUIDelegate.runJavaScriptAlertPanel", error)
            }
            completionHandler()
          }
        }
      }
    }
  #else
    func webView(
      _ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptAlertPanel(
          pigeonInstance: self, webView: webView, message: message, frame: frame
        ) { result in
          DispatchQueue.main.async {
            if case .failure(let error) = result {
              onFailure("WKUIDelegate.runJavaScriptAlertPanel", error)
            }
            completionHandler()
          }
        }
      }
    }
  #endif

  #if compiler(>=6.0)
    func webView(
      _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptConfirmPanel(
          pigeonInstance: self, webView: webView, message: message, frame: frame
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let confirmed):
              completionHandler(confirmed)
            case .failure(let error):
              completionHandler(false)
              onFailure("WKUIDelegate.runJavaScriptConfirmPanel", error)
            }
          }
        }
      }
    }
  #else
    func webView(
      _ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
      initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptConfirmPanel(
          pigeonInstance: self, webView: webView, message: message, frame: frame
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let confirmed):
              completionHandler(confirmed)
            case .failure(let error):
              completionHandler(false)
              onFailure("WKUIDelegate.runJavaScriptConfirmPanel", error)
            }
          }
        }
      }
    }
  #endif

  #if compiler(>=6.0)
    func webView(
      _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
      defaultText: String?, initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping @MainActor (String?) -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptTextInputPanel(
          pigeonInstance: self, webView: webView, prompt: prompt, defaultText: defaultText,
          frame: frame
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let response):
              completionHandler(response)
            case .failure(let error):
              completionHandler(nil)
              onFailure("WKUIDelegate.runJavaScriptTextInputPanel", error)
            }
          }
        }
      }
    }
  #else
    func webView(
      _ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
      defaultText: String?, initiatedByFrame frame: WKFrameInfo,
      completionHandler: @escaping (String?) -> Void
    ) {
      registrar.dispatchOnMainThread { onFailure in
        self.api.runJavaScriptTextInputPanel(
          pigeonInstance: self, webView: webView, prompt: prompt, defaultText: defaultText,
          frame: frame
        ) { result in
          DispatchQueue.main.async {
            switch result {
            case .success(let response):
              completionHandler(response)
            case .failure(let error):
              completionHandler(nil)
              onFailure("WKUIDelegate.runJavaScriptTextInputPanel", error)
            }
          }
        }
      }
    }
  #endif
}

/// ProxyApi implementation for `WKUIDelegate`.
///
/// This class may handle instantiating native object instances that are attached to a Dart instance
/// or handle method calls on the associated native class or an instance of that class.
class UIDelegateProxyAPIDelegate: PigeonApiDelegateWKUIDelegate {
  func pigeonDefaultConstructor(pigeonApi: PigeonApiWKUIDelegate) throws -> WKUIDelegate {
    return UIDelegateImpl(
      api: pigeonApi, registrar: pigeonApi.pigeonRegistrar as! ProxyAPIRegistrar)
  }
}

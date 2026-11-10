import Foundation
import WebKit

#if os(iOS)
  import UIKit
#else
  import AppKit
#endif

/// Observes native submission, never claims physical printer completion.
final class BrowserPrintJob: NSObject {
  private weak var view: WKWebView?
  private let name: String
  private(set) var state = "presented"
  #if os(iOS)
    private static weak var active: BrowserPrintJob?
    var canCancel: Bool { true }
  #else
    private var operation: NSPrintOperation?
    private var keepAlive: BrowserPrintJob?
    var canCancel: Bool { false }
  #endif
  init?(view: WKWebView, name: String) {
    guard view.window != nil else { return nil }
    self.view = view
    self.name = name
  }
  func present() -> Bool {
    guard let view, view.window != nil else { return false }
    #if os(iOS)
      guard UIPrintInteractionController.isPrintingAvailable, Self.active == nil else {
        return false
      }
      let controller = UIPrintInteractionController.shared
      let info = UIPrintInfo(dictionary: nil)
      info.jobName = name
      controller.printInfo = info
      controller.printFormatter = view.viewPrintFormatter()
      Self.active = self
      let accepted = controller.present(from: view.bounds, in: view, animated: true) {
        [self] _, completed, error in
        state = error != nil ? "failed" : completed ? "completed" : "cancelled"
        if Self.active === self { Self.active = nil }
      }
      if !accepted, Self.active === self { Self.active = nil }
      return accepted
    #else
      guard let window = view.window else { return false }
      let operation = view.printOperation(with: NSPrintInfo())
      operation.jobTitle = name
      self.operation = operation
      keepAlive = self
      operation.runModal(
        for: window, delegate: self,
        didRun: #selector(didRun(_:success:context:)), contextInfo: nil)
      return true
    #endif
  }
  func cancel() -> Bool {
    #if os(iOS)
      guard Self.active === self else { return false }
      UIPrintInteractionController.shared.dismiss(animated: true)
      Self.active = nil
      state = "cancelled"
      return true
    #else
      return false
    #endif
  }
  #if os(macOS)
    @objc private func didRun(
      _ operation: NSPrintOperation, success: Bool, context: UnsafeMutableRawPointer?
    ) {
      state = success ? "completed" : "cancelledOrFailed"
      self.operation = nil
      keepAlive = nil
    }
  #endif
}

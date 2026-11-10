import Foundation
import WebKit

#if os(iOS)
  import Flutter
#else
  import FlutterMacOS
#endif

/// Named stores owned by this plugin. Never touches default or ephemeral stores.
final class BrowserProfiles {
  private static let key = "com.abandoft.webview_all.namedProfiles"
  private static let views = NSHashTable<WKWebView>.weakObjects()
  private static var snapshots: [UUID: Int] = [:]
  private static var pending = Set<UUID>()
  private struct ProxyObject {
    weak var object: AnyObject?
    weak var manager: WebKitLibraryPigeonInstanceManager?
  }
  private static var proxyObjects: [UUID: [ProxyObject]] = [:]
  static func track(
    _ object: AnyObject, store: WKWebsiteDataStore,
    manager: WebKitLibraryPigeonInstanceManager
  ) {
    if #available(iOS 17.0, macOS 14.0, *), let id = store.identifier {
      var entries = proxyObjects[id, default: []].filter { $0.object != nil && $0.manager != nil }
      if !entries.contains(where: { $0.object === object && $0.manager === manager }) {
        entries.append(ProxyObject(object: object, manager: manager))
      }
      proxyObjects[id] = entries
    }
  }
  @available(iOS 17.0, macOS 14.0, *)
  private static func releaseIdleObjects(_ id: UUID) {
    // Explicit deletion invalidates handles belonging to this closed profile.
    // Do not depend on when Dart GC releases configurations and cookie stores.
    for entry in proxyObjects[id, default: []] {
      guard let object = entry.object, let manager = entry.manager else { continue }
      if let configuration = object as? WKWebViewConfiguration,
        configuration.websiteDataStore.identifier != id
      {
        continue
      }
      if let identifier = manager.identifierWithStrongReference(forInstance: object) {
        let _: AnyObject? = try? manager.removeInstance(withIdentifier: identifier)
      }
    }
  }
  private static var names: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: key) }
  }
  static func valid(_ name: String) -> Bool {
    name.range(of: "^[A-Za-z0-9_-]{1,64}$", options: .regularExpression) != nil
  }
  private static func registeredIdentifier(_ value: String?) -> UUID? {
    guard let value, let id = UUID(uuidString: value),
      id.uuidString != "00000000-0000-0000-0000-000000000000"
    else { return nil }
    return id
  }
  @available(iOS 17.0, macOS 14.0, *)
  static func store(_ name: String, manager: WebKitLibraryPigeonInstanceManager) throws
    -> WKWebsiteDataStore
  {
    let records = names
    // A name identifies a logical profile, not one forever-reused WebKit store.
    // Preserve existing mappings (including the original deterministic IDs),
    // but give a deleted-and-recreated profile a fresh native identity. WebKit
    // may retain session cookies in its network process after disk removal.
    guard records[name] == nil || registeredIdentifier(records[name]) != nil else {
      throw PigeonError(
        code: "invalid_profile_registry",
        message: "The saved profile identifier is invalid. No fallback store was created.",
        details: nil)
    }
    let id = registeredIdentifier(records[name]) ?? UUID()
    guard !pending.contains(id) else {
      throw PigeonError(
        code: "profile_deleting",
        message: "This profile is being deleted. Retry after deletion completes.", details: nil)
    }
    let store = WKWebsiteDataStore(forIdentifier: id)
    track(store, store: store, manager: manager)
    var updated = records
    updated[name] = id.uuidString
    names = updated
    return store
  }
  static func register(_ view: WKWebView) { views.add(view) }
  static func retainSnapshot(_ store: WKWebsiteDataStore) {
    if #available(iOS 17.0, macOS 14.0, *), let id = store.identifier {
      snapshots[id, default: 0] += 1
    }
  }
  static func releaseSnapshot(_ store: WKWebsiteDataStore) {
    if #available(iOS 17.0, macOS 14.0, *), let id = store.identifier {
      let count = snapshots[id, default: 0] - 1
      if count > 0 { snapshots[id] = count } else { snapshots.removeValue(forKey: id) }
    }
  }
  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool {
    guard
      ["profileManagementCapabilities", "listProfiles", "requestProfileDeletion"].contains(
        call.method)
    else { return false }
    guard #available(iOS 17.0, macOS 14.0, *) else {
      if call.method == "profileManagementCapabilities" {
        result([
          "listing": false, "deletion": false,
          "limitation": "Named store management requires iOS 17 or macOS 14.",
        ])
      } else if call.method == "listProfiles" {
        result(nil)
      } else {
        result(["status": "unsupported"])
      }
      return true
    }
    if call.method == "profileManagementCapabilities" {
      result([
        "listing": true, "deletion": true,
        "limitation":
          "Only plugin-owned named persistent stores are managed. Close their views and dispose saved navigation states before deleting.",
      ])
      return true
    }
    if call.method == "listProfiles" {
      // Keep registry entries until explicit deletion: a newly created empty
      // native store need not have appeared in WebKit's disk enumeration yet.
      result(
        names.compactMap { name, value -> [String: Any]? in
          guard valid(name), let id = registeredIdentifier(value) else { return nil }
          return ["name": name, "deletionPending": pending.contains(id)]
        })
      return true
    }
    guard let name = (call.arguments as? [String: Any])?["name"] as? String, valid(name) else {
      result(["status": "failed", "description": "Invalid named profile; no store was cleared."])
      return true
    }
    guard let saved = names[name] else {
      result(["status": "notFound"])
      return true
    }
    guard let id = registeredIdentifier(saved) else {
      result([
        "status": "failed",
        "description": "The saved profile identifier is invalid. No store was cleared.",
      ])
      return true
    }
    if pending.contains(id) {
      result(["status": "pending"])
      return true
    }
    if views.allObjects.contains(where: { $0.configuration.websiteDataStore.identifier == id })
      || snapshots[id, default: 0] > 0
    {
      result([
        "status": "busy",
        "description":
          "Close this profile's views and dispose its saved navigation states before deletion.",
      ])
      return true
    }
    // A static removal can run before any WKWebView exists after app startup.
    // Construct a public store first so WebKit initializes its main run loop.
    // This does not load a page or clear the ordinary store.
    _ = WKWebsiteDataStore.default()
    pending.insert(id)
    autoreleasepool { releaseIdleObjects(id) }
    // Let the current native call/autorelease scope finish before WebKit checks
    // whether the last closed page and its proxy configuration were released.
    DispatchQueue.main.async {
      WKWebsiteDataStore.remove(forIdentifier: id) { error in
        pending.remove(id)
        if let error {
          // WebKit uses one generic NSError code for both I/O errors and
          // occupied stores. Preserve its explicit occupancy diagnostic.
          let occupied = error.localizedDescription.hasPrefix("Data store is in use")
          let status = occupied ? "busy" : "failed"
          result(["status": status, "description": error.localizedDescription])
        } else {
          var records = names
          records.removeValue(forKey: name)
          names = records
          proxyObjects.removeValue(forKey: id)
          result(["status": "deleted"])
        }
      }
    }
    return true
  }
}

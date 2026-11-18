import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterPluginRegistrant {
  override init() {
    super.init()
    // Install before the scene's storyboard creates its engine. This public
    // callback is available on Flutter 3.35 and registers against that engine.
    pluginRegistrant = self
  }

  func register(with registry: FlutterPluginRegistry) {
    GeneratedPluginRegistrant.register(with: registry)
  }
}

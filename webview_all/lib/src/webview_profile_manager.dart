import 'package:flutter/foundation.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

/// Lists and requests deletion of plugin-owned named persistent profiles.
/// Close all related sessions and dispose their navigation-state handles first.
/// Native deletion can remain pending or require a subsequent process launch.
class WebViewProfileManager {
  WebViewProfileManager() : platform = _create();
  WebViewProfileManager.fromPlatform(this.platform);
  final PlatformWebViewProfileManager platform;
  static PlatformWebViewProfileManager _create() {
    try {
      return WebViewPlatform.instance?.createPlatformWebViewProfileManager() ??
          PlatformWebViewProfileManager();
    } catch (error) {
      debugPrint('webview_all: profile management is unavailable: $error');
      return PlatformWebViewProfileManager();
    }
  }

  Future<WebViewProfileManagementCapabilities> getCapabilities() =>
      platform.getCapabilities();
  Future<List<WebViewProfileInfo>?> listProfiles() => platform.listProfiles();
  Future<WebViewProfileDeletionResult> requestDeletion(String name) =>
      platform.requestDeletion(name);
}

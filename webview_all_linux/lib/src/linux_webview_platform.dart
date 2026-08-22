import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_navigation_delegate.dart';
import 'linux_webview_controller.dart';
import 'linux_webview_cookie_manager.dart';
import 'linux_webview_data_manager.dart';
import 'linux_webview_widget.dart';

class LinuxWebViewPlatform extends WebViewPlatform {
  @override
  bool get supportsOffscreenWebViews => true;

  static void registerWith() {
    WebViewPlatform.instance = LinuxWebViewPlatform();
  }

  @override
  LinuxWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    return LinuxWebViewController(params);
  }

  @override
  LinuxNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) {
    return LinuxNavigationDelegate(params);
  }

  @override
  LinuxWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) {
    return LinuxWebViewWidget(params);
  }

  @override
  LinuxWebViewCookieManager createPlatformCookieManager(
    PlatformWebViewCookieManagerCreationParams params,
  ) {
    return LinuxWebViewCookieManager(params);
  }

  @override
  LinuxWebViewDataManager createPlatformWebViewDataManager(
    PlatformWebViewDataManagerCreationParams params,
  ) {
    return LinuxWebViewDataManager(params);
  }
}

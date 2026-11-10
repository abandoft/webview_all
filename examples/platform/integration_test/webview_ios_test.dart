import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'webview_resource_test.dart' as resources;
import 'webview_javascript_test.dart' as javascript;
import 'webview_browser_test.dart' as browser;
import 'webview_capture_data_test.dart' as capture;
import 'webview_advanced_browser_test.dart' as advanced;
import 'webview_profile_management_test.dart' as profiles;
import 'webview_network_test.dart' as network;
import 'webview_session_test.dart' as sessions;
import 'webview_new_window_test.dart' as windows;

// One application launch lets XCTest report each Dart result directly, without
// depending on Flutter tool discovery of the simulator's VM Service.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // XCTest can enable accessibility during the first test. Establish semantics
  // before WidgetTester records its baseline, and restore it after the suite.
  binding.platformDispatcher.semanticsEnabledTestValue = true;
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  group('iOS integrations', () {
    group('resources', resources.main);
    group('javascript', javascript.main);
    group('browser', browser.main);
    group('capture', capture.main);
    group('advanced', advanced.main);
    group('profiles', profiles.main);
    group('network', network.main);
    group('sessions', sessions.main);
    group('windows', windows.main);
  }, skip: !Platform.isIOS);
}

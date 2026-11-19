import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'webview_advanced_browser_test.dart' as advanced;
import 'webview_browser_test.dart' as browser;
import 'webview_capture_data_test.dart' as capture;
import 'webview_download_test.dart' as downloads;
import 'webview_form_request_test.dart' as forms;
import 'webview_fullscreen_test.dart' as fullscreen;
import 'webview_javascript_test.dart' as javascript;
import 'webview_network_test.dart' as network;
import 'webview_new_window_test.dart' as windows;
import 'webview_presentation_test.dart' as presentation;
import 'webview_process_test.dart' as process;
import 'webview_profile_management_test.dart' as profiles;
import 'webview_resource_test.dart' as resources;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Android integrations', () {
    group('resources', resources.main);
    group('javascript', javascript.main);
    group('browser', browser.main);
    group('presentation', presentation.main);
    group('forms', forms.main);
    group('capture', capture.main);
    group('advanced', advanced.main);
    group('profiles', profiles.main);
    group('network', network.main);
    group('windows', windows.main);
    group('fullscreen', fullscreen.main);
    group('downloads', downloads.main);
    group('process', process.main);
  }, skip: !Platform.isAndroid);
}

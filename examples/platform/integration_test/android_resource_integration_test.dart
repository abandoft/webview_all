import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'android_renderer_recovery_test.dart' as recovery;
import 'webview_resource_test.dart' as resources;

void main() {
  // Register driver reporting outside the groups so every group must finish.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Application resources', resources.main);
  group('Renderer recovery', recovery.main);
}

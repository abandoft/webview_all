import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'resource_request_timeout_test.dart' as deadlines;
import 'webview_resource_test.dart' as resources;

void main() {
  // Register driver reporting outside the groups so every group must finish.
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Application resources', resources.main);
  group('Configurable deadlines', deadlines.main);
}

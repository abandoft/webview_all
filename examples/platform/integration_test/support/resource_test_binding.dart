import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

IntegrationTestWidgetsFlutterBinding initializeResourceTestBinding() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (Platform.isIOS) {
    // XCTest can enable platform accessibility after testWidgets records its
    // handle count. Establish that platform-owned handle before each test;
    // the framework still detects handles leaked by the test itself.
    setUp(() => binding.platformDispatcher.semanticsEnabledTestValue = true);
    tearDown(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  }
  return binding;
}

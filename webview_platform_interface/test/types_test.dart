// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/src/types/types.dart';

void main() {
  group('types', () {
    test('WebResourceRequest', () {
      final Uri uri = Uri.parse('https://www.google.com');
      final request = WebResourceRequest(uri: uri);
      expect(request.uri, uri);
    });

    test('WebResourceResponse', () {
      final Uri uri = Uri.parse('https://www.google.com');
      const statusCode = 404;
      const headers = <String, String>{'a': 'header'};

      final response = WebResourceResponse(
        uri: uri,
        statusCode: statusCode,
        headers: headers,
      );

      expect(response.uri, uri);
      expect(response.statusCode, statusCode);
      expect(response.headers, headers);
    });

    test('JavaScriptInvocationParams validates and freezes arguments', () {
      final List<Object?> nested = <Object?>[1, 'two'];
      final JavaScriptInvocationParams params = JavaScriptInvocationParams(
        functionBody: 'return value;',
        arguments: <String, Object?>{'value': nested},
      );
      nested.add(3);

      expect(params.arguments['value'], <Object?>[1, 'two']);
      expect(
        () => (params.arguments['value']! as List<Object?>).add(3),
        throwsUnsupportedError,
      );
      expect(
        () => JavaScriptInvocationParams(
          functionBody: 'return 1;',
          arguments: <String, Object?>{'not-valid!': 1},
        ),
        throwsArgumentError,
      );
      expect(
        () => JavaScriptInvocationParams(
          functionBody: 'return value;',
          arguments: <String, Object?>{'value': double.nan},
        ),
        throwsArgumentError,
      );
      expect(
        () => JavaScriptInvocationParams(
          functionBody: 'return value;',
          arguments: <String, Object?>{'class': 'reserved'},
        ),
        throwsArgumentError,
      );
    });

    test('JavaScriptInvocationParams rejects cyclic arguments', () {
      final List<Object?> cyclicList = <Object?>[];
      cyclicList.add(cyclicList);
      expect(
        () => JavaScriptInvocationParams(
          functionBody: 'return value;',
          arguments: <String, Object?>{'value': cyclicList},
        ),
        throwsArgumentError,
      );

      final Map<String, Object?> cyclicMap = <String, Object?>{};
      cyclicMap['self'] = cyclicMap;
      expect(
        () => JavaScriptInvocationParams(
          functionBody: 'return value;',
          arguments: <String, Object?>{'value': cyclicMap},
        ),
        throwsArgumentError,
      );

      final List<Object?> shared = <Object?>[1];
      final JavaScriptInvocationParams params = JavaScriptInvocationParams(
        functionBody: 'return value;',
        arguments: <String, Object?>{
          'value': <Object?>[shared, shared],
        },
      );
      expect(params.arguments['value'], <Object?>[
        <Object?>[1],
        <Object?>[1],
      ]);
    });

    test('WebViewDataClearingResult rejects contradictory outcomes', () {
      expect(
        () => WebViewDataClearingResult(
          clearedDataTypes: const <WebViewDataType>{WebViewDataType.cookies},
          unsupportedDataTypes: const <WebViewDataType>{
            WebViewDataType.cookies,
          },
        ),
        throwsArgumentError,
      );
      expect(
        () => WebViewDataClearingResult(
          clearedDataTypes: const <WebViewDataType>{WebViewDataType.cookies},
        ),
        throwsArgumentError,
      );

      final WebViewDataClearingResult complete = WebViewDataClearingResult(
        clearedDataTypes: WebViewDataType.values.toSet(),
      );
      expect(complete.isComplete, isTrue);
      expect(
        () => complete.clearedDataTypes.remove(WebViewDataType.cookies),
        throwsUnsupportedError,
      );
    });
  });
}

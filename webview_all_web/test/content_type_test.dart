// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_web/src/content_type.dart';

void main() {
  group('ContentType.parse', () {
    test('basic content-type (lowers case)', () {
      final contentType = ContentType.parse('text/pLaIn');

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, isNull);
      expect(contentType.charset, isNull);
    });

    test('with charset', () {
      final contentType = ContentType.parse('text/pLaIn; charset=utf-8');

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, isNull);
      expect(contentType.charset, 'utf-8');
    });

    test('with boundary', () {
      final contentType = ContentType.parse('text/pLaIn; boundary=---xyz');

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, '---xyz');
      expect(contentType.charset, isNull);
    });

    test('with charset and boundary', () {
      final contentType = ContentType.parse(
        'text/pLaIn; charset=utf-8; boundary=---xyz',
      );

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, '---xyz');
      expect(contentType.charset, 'utf-8');
    });

    test('with boundary and charset', () {
      final contentType = ContentType.parse(
        'text/pLaIn; boundary=---xyz; charset=utf-8',
      );

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, '---xyz');
      expect(contentType.charset, 'utf-8');
    });

    test('with a bunch of whitespace, boundary and charset', () {
      final contentType = ContentType.parse(
        '     text/pLaIn   ; boundary=---xyz;    charset=utf-8    ',
      );

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.boundary, '---xyz');
      expect(contentType.charset, 'utf-8');
    });

    test('empty string', () {
      final contentType = ContentType.parse('');

      expect(contentType.mimeType, '');
      expect(contentType.boundary, isNull);
      expect(contentType.charset, isNull);
    });

    test('ignores extension parameters', () {
      final contentType = ContentType.parse(
        'text/pLaIn; profile="https://example.com/a=b"; charset=utf-8',
      );

      expect(contentType.mimeType, 'text/plain');
      expect(contentType.charset, 'utf-8');
    });

    test('parses quoted values without lowercasing boundary data', () {
      final contentType = ContentType.parse(
        r'multipart/form-data; boundary="Case;Sensitive=Value"',
      );

      expect(contentType.mimeType, 'multipart/form-data');
      expect(contentType.boundary, 'Case;Sensitive=Value');
    });

    test('unescapes quoted parameter values', () {
      final contentType = ContentType.parse(
        r'text/html; charset="utf\-8"; ignored',
      );

      expect(contentType.charset, 'utf-8');
    });

    test('ignores malformed parameters', () {
      final contentType = ContentType.parse(
        'text/html; invalid; =missing-name; charset=utf-8',
      );

      expect(contentType.mimeType, 'text/html');
      expect(contentType.charset, 'utf-8');
    });
  });
}

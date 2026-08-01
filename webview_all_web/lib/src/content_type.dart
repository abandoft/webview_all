// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Class to represent a content-type header value.
class ContentType {
  /// Creates a [ContentType] instance by parsing a "content-type" response [header].
  ///
  /// See: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Type
  /// See: https://httpwg.org/specs/rfc9110.html#media.type
  ContentType.parse(String header) {
    final List<String> chunks = _splitParameters(header);
    _mimeType = chunks.first.trim().toLowerCase();

    for (final String chunk in chunks.skip(1)) {
      final int separator = chunk.indexOf('=');
      if (separator <= 0) {
        // Unknown or malformed parameters do not make an otherwise usable
        // response body unloadable.
        continue;
      }

      final String name = chunk.substring(0, separator).trim().toLowerCase();
      final String value = _unquote(chunk.substring(separator + 1).trim());
      switch (name) {
        case 'charset':
          _charset = value;
        case 'boundary':
          _boundary = value;
        default:
        // Extension parameters are valid and are intentionally ignored.
      }
    }
  }

  String? _mimeType;
  String? _charset;
  String? _boundary;

  /// The MIME-type of the resource or the data.
  String? get mimeType => _mimeType;

  /// The character encoding standard.
  String? get charset => _charset;

  /// The separation boundary for multipart entities.
  String? get boundary => _boundary;

  static List<String> _splitParameters(String header) {
    final List<String> chunks = <String>[];
    final StringBuffer chunk = StringBuffer();
    bool inQuotedString = false;
    bool escaped = false;

    for (final int codePoint in header.runes) {
      final String character = String.fromCharCode(codePoint);
      if (escaped) {
        chunk.write(character);
        escaped = false;
        continue;
      }
      if (inQuotedString && character == '\\') {
        chunk.write(character);
        escaped = true;
        continue;
      }
      if (character == '"') {
        inQuotedString = !inQuotedString;
        chunk.write(character);
        continue;
      }
      if (character == ';' && !inQuotedString) {
        chunks.add(chunk.toString());
        chunk.clear();
        continue;
      }
      chunk.write(character);
    }
    chunks.add(chunk.toString());
    return chunks;
  }

  static String _unquote(String value) {
    if (value.length < 2 || !value.startsWith('"') || !value.endsWith('"')) {
      return value;
    }

    final String quoted = value.substring(1, value.length - 1);
    final StringBuffer unescaped = StringBuffer();
    bool escaped = false;
    for (final int codePoint in quoted.runes) {
      final String character = String.fromCharCode(codePoint);
      if (escaped) {
        unescaped.write(character);
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else {
        unescaped.write(character);
      }
    }
    if (escaped) {
      unescaped.write('\\');
    }
    return unescaped.toString();
  }
}

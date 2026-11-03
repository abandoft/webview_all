import 'dart:typed_data';

import 'resource_file_stub.dart'
    if (dart.library.io) 'resource_file_io.dart'
    as implementation;

/// File access shared by native resource bridges without importing dart:io on Web.
abstract class ResourceFile {
  static Future<ResourceFile> open(String path) =>
      implementation.openResourceFile(path);

  int get length;
  Future<void> seek(int offset);
  Future<Uint8List> read(int count);
  Future<void> close();
}

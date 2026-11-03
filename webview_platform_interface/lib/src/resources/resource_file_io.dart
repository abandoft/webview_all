import 'dart:io';
import 'dart:typed_data';

import 'resource_file.dart';

Future<ResourceFile> openResourceFile(String path) async {
  final file = File(path);
  if (!file.isAbsolute) {
    throw ArgumentError.value(
      path,
      'path',
      'A resource file must be absolute.',
    );
  }
  final handle = await file.open();
  try {
    return _ResourceFile(handle, await handle.length());
  } catch (_) {
    await handle.close();
    rethrow;
  }
}

class _ResourceFile implements ResourceFile {
  _ResourceFile(this.handle, this.length);

  final RandomAccessFile handle;
  @override
  final int length;
  @override
  Future<void> seek(int offset) async => handle.setPosition(offset);
  @override
  Future<Uint8List> read(int count) => handle.read(count);
  @override
  Future<void> close() async => handle.close();
}

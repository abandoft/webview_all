import 'resource_file.dart';

Future<ResourceFile> openResourceFile(String path) =>
    Future<ResourceFile>.error(
      UnsupportedError('Local files are unavailable.'),
    );

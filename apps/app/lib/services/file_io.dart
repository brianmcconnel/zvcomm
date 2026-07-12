import 'dart:typed_data';

import 'file_io_stub.dart' if (dart.library.io) 'file_io_io.dart' as impl;

Future<Uint8List> readBytes(String path) => impl.readBytes(path);

Future<void> writeBytes(String path, Uint8List bytes) =>
    impl.writeBytes(path, bytes);

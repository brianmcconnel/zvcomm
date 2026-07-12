import 'dart:typed_data';

/// Web stub — file paths are not used for PTT capture on web (stream only).
Future<Uint8List> readBytes(String path) async => Uint8List(0);

Future<void> writeBytes(String path, Uint8List bytes) async {}

import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readBytes(String path) async {
  final f = File(path);
  if (!await f.exists()) return Uint8List(0);
  return f.readAsBytes();
}

Future<void> writeBytes(String path, Uint8List bytes) async {
  final f = File(path);
  await f.parent.create(recursive: true);
  await f.writeAsBytes(bytes, flush: true);
}

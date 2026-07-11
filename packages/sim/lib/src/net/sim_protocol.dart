import 'dart:convert';
import 'dart:typed_data';

/// Wire types for the multi-process TCP mesh simulator.
abstract final class SimMsgType {
  static const register = 'register';
  static const registerOk = 'register_ok';
  static const advertise = 'advertise';
  static const peer = 'peer';
  static const connect = 'connect';
  static const connected = 'connected';
  static const data = 'data';
  static const leave = 'leave';
  static const error = 'error';
  static const ping = 'ping';
  static const pong = 'pong';
}

/// Length-prefixed UTF-8 JSON frames (u32 BE length + body).
final class SimCodec {
  final BytesBuilder _buf = BytesBuilder(copy: false);

  /// Encode a JSON-compatible map to a wire frame.
  static Uint8List encode(Map<String, Object?> msg) {
    final body = utf8.encode(jsonEncode(msg));
    final out = ByteData(4 + body.length);
    out.setUint32(0, body.length);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(4, 4 + body.length, body);
    return bytes;
  }

  /// Push socket bytes; returns complete decoded messages.
  List<Map<String, Object?>> add(List<int> chunk) {
    _buf.add(chunk);
    final out = <Map<String, Object?>>[];
    var data = Uint8List.fromList(_buf.takeBytes());
    while (data.length >= 4) {
      final len = ByteData.sublistView(data).getUint32(0);
      if (len < 0 || len > 16 * 1024 * 1024) {
        // Corrupt length — drop buffer.
        return out;
      }
      if (data.length < 4 + len) break;
      final body = data.sublist(4, 4 + len);
      data = data.sublist(4 + len);
      try {
        final decoded = jsonDecode(utf8.decode(body));
        if (decoded is Map) {
          out.add(Map<String, Object?>.from(decoded));
        }
      } catch (_) {
        // Drop malformed frames.
      }
    }
    if (data.isNotEmpty) {
      _buf.add(data);
    }
    return out;
  }
}

/// Base64 helpers for binary mesh payloads on the JSON wire.
String simB64Encode(Uint8List data) => base64Encode(data);

Uint8List simB64Decode(String s) => Uint8List.fromList(base64Decode(s));

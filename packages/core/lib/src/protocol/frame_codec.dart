import 'dart:typed_data';

/// Length-prefixed framing for transports with small MTUs (BLE, etc.).
///
/// Wire format: `u32be length | payload[length]`.
/// Chunks may be delivered separately; [add] reassembles complete frames.
final class StreamFrameCodec {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  static const int headerSize = 4;
  static const int maxFrameBytes = 256 * 1024;

  /// Encode a complete application frame for transmission.
  static Uint8List encode(Uint8List payload) {
    if (payload.length > maxFrameBytes) {
      throw ArgumentError('frame too large: ${payload.length}');
    }
    final out = Uint8List(headerSize + payload.length);
    final bd = ByteData.sublistView(out);
    bd.setUint32(0, payload.length, Endian.big);
    out.setRange(headerSize, out.length, payload);
    return out;
  }

  /// Split [frame] into chunks no larger than [maxChunk].
  static List<Uint8List> chunk(Uint8List frame, int maxChunk) {
    if (maxChunk < 1) {
      throw ArgumentError('maxChunk must be >= 1');
    }
    if (frame.length <= maxChunk) {
      return [frame];
    }
    final parts = <Uint8List>[];
    for (var i = 0; i < frame.length; i += maxChunk) {
      final end = (i + maxChunk < frame.length) ? i + maxChunk : frame.length;
      parts.add(Uint8List.sublistView(frame, i, end));
    }
    return parts;
  }

  /// Feed inbound bytes; returns zero or more complete payloads.
  List<Uint8List> add(Uint8List chunk) {
    _buffer.add(chunk);
    final frames = <Uint8List>[];
    while (true) {
      final bytes = _buffer.toBytes();
      if (bytes.length < headerSize) {
        break;
      }
      final length =
          ByteData.sublistView(bytes).getUint32(0, Endian.big);
      if (length > maxFrameBytes) {
        _buffer.clear();
        throw FormatException('frame length $length exceeds max');
      }
      final total = headerSize + length;
      if (bytes.length < total) {
        break;
      }
      frames.add(Uint8List.fromList(bytes.sublist(headerSize, total)));
      final rest = bytes.sublist(total);
      _buffer.clear();
      if (rest.isNotEmpty) {
        _buffer.add(rest);
      }
    }
    return frames;
  }

  void clear() => _buffer.clear();
}

/// Power-mode helpers shared by transports.
extension TransportPowerModeTiming on Object {
  // Intentionally empty placeholder for discovery — use [scanIntervalFor].
}

/// Recommended discovery cadence for a [TransportPowerMode]-like enum name.
Duration scanIntervalForPowerMode(String modeName) {
  switch (modeName) {
    case 'performance':
      return const Duration(milliseconds: 100);
    case 'powerSaver':
      return const Duration(seconds: 3);
    case 'ultraLow':
      return const Duration(seconds: 10);
    case 'balanced':
    default:
      return const Duration(milliseconds: 500);
  }
}

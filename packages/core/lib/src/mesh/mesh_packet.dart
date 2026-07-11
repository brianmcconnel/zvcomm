import 'dart:convert';
import 'dart:typed_data';

import '../models/message.dart';

/// Wire-level mesh frame for flooding / adaptive routing.
///
/// Binary layout (version 1, little-endian where applicable):
/// ```
/// version:u8 | flags:u8 | hopLimit:u8 | kind:u8
/// seq:u32 | msgIdLen:u8 | msgId | srcLen:u8 | src | dstLen:u8 | dst
/// payloadLen:u16 | payload
/// ```
///
/// Flag bits: `0x01` = prefers adaptive unicast when possible (advisory).
final class MeshPacket {
  static const int version = 1;
  static const int flagAdaptive = 0x01;

  final String messageId;
  final String sourceId;
  final String? destinationId;
  final MessageKind kind;
  final int hopLimit;
  final int sequence;
  final Uint8List payload;
  final int flags;

  const MeshPacket({
    required this.messageId,
    required this.sourceId,
    this.destinationId,
    required this.kind,
    required this.hopLimit,
    required this.sequence,
    required this.payload,
    this.flags = 0,
  });

  bool get isBroadcast => destinationId == null || destinationId!.isEmpty;

  MeshPacket decrementHop() => MeshPacket(
        messageId: messageId,
        sourceId: sourceId,
        destinationId: destinationId,
        kind: kind,
        hopLimit: hopLimit - 1,
        sequence: sequence,
        payload: payload,
        flags: flags,
      );

  /// Dedup key: origin + message id (sequence is advisory).
  String get dedupKey => '$sourceId|$messageId';

  Uint8List encode() {
    final msgId = utf8.encode(messageId);
    final src = utf8.encode(sourceId);
    final dst = utf8.encode(destinationId ?? '');
    if (msgId.length > 255 || src.length > 255 || dst.length > 255) {
      throw ArgumentError('id fields must be <= 255 bytes UTF-8');
    }
    if (payload.length > 0xFFFF) {
      throw ArgumentError('payload too large for v1 frame');
    }

    final builder = BytesBuilder(copy: false);
    builder.addByte(version);
    builder.addByte(flags);
    builder.addByte(hopLimit.clamp(0, 255));
    builder.addByte(kind.index);
    builder.add(_u32le(sequence));
    builder.addByte(msgId.length);
    builder.add(msgId);
    builder.addByte(src.length);
    builder.add(src);
    builder.addByte(dst.length);
    builder.add(dst);
    builder.add(_u16le(payload.length));
    builder.add(payload);
    return builder.toBytes();
  }

  static MeshPacket decode(Uint8List data) {
    if (data.length < 10) {
      throw const FormatException('mesh packet too short');
    }
    var o = 0;
    final ver = data[o++];
    if (ver != version) {
      throw FormatException('unsupported mesh version $ver');
    }
    final flags = data[o++];
    final hopLimit = data[o++];
    final kindIndex = data[o++];
    if (kindIndex >= MessageKind.values.length) {
      throw FormatException('unknown message kind $kindIndex');
    }
    final seq = _readU32le(data, o);
    o += 4;

    final msgIdLen = data[o++];
    final messageId = utf8.decode(data.sublist(o, o + msgIdLen));
    o += msgIdLen;

    final srcLen = data[o++];
    final sourceId = utf8.decode(data.sublist(o, o + srcLen));
    o += srcLen;

    final dstLen = data[o++];
    final dstStr = utf8.decode(data.sublist(o, o + dstLen));
    o += dstLen;

    final payloadLen = _readU16le(data, o);
    o += 2;
    if (o + payloadLen > data.length) {
      throw const FormatException('truncated payload');
    }
    final payload = Uint8List.sublistView(data, o, o + payloadLen);

    return MeshPacket(
      messageId: messageId,
      sourceId: sourceId,
      destinationId: dstStr.isEmpty ? null : dstStr,
      kind: MessageKind.values[kindIndex],
      hopLimit: hopLimit,
      sequence: seq,
      payload: payload,
      flags: flags,
    );
  }

  static Uint8List _u16le(int v) =>
      Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little);

  static Uint8List _u32le(int v) =>
      Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

  static int _readU16le(Uint8List d, int o) =>
      ByteData.sublistView(d).getUint16(o, Endian.little);

  static int _readU32le(Uint8List d, int o) =>
      ByteData.sublistView(d).getUint32(o, Endian.little);
}

import 'dart:typed_data';

/// Application-level message kinds carried over the mesh.
enum MessageKind {
  /// Text chat payload (UTF-8).
  chat,

  /// Presence / heartbeat.
  presence,

  /// Arbitrary binary blob or file chunk.
  data,

  /// Control / routing metadata.
  control,

  /// Certificate or PKI gossip.
  pki,
}

/// A user- or mesh-layer message ready for encryption and routing.
final class MeshMessage {
  final String id;
  final String? sourceId;
  final String? destinationId;
  final MessageKind kind;
  final Uint8List payload;
  final DateTime timestamp;
  final int hopLimit;
  final Map<String, String> headers;

  const MeshMessage({
    required this.id,
    this.sourceId,
    this.destinationId,
    required this.kind,
    required this.payload,
    required this.timestamp,
    this.hopLimit = 8,
    this.headers = const {},
  });

  bool get isBroadcast => destinationId == null || destinationId!.isEmpty;

  MeshMessage copyWith({
    String? id,
    String? sourceId,
    String? destinationId,
    MessageKind? kind,
    Uint8List? payload,
    DateTime? timestamp,
    int? hopLimit,
    Map<String, String>? headers,
  }) {
    return MeshMessage(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      destinationId: destinationId ?? this.destinationId,
      kind: kind ?? this.kind,
      payload: payload ?? this.payload,
      timestamp: timestamp ?? this.timestamp,
      hopLimit: hopLimit ?? this.hopLimit,
      headers: headers ?? this.headers,
    );
  }
}

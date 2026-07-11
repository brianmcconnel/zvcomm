import 'dart:convert';
import 'dart:typed_data';

import 'package:zvcomm_core/zvcomm_core.dart';

/// Compact identity + optional payload carried over NFC NDEF.
final class NfcBootstrapPayload {
  final String peerId;
  final String displayName;
  final Map<String, String> metadata;
  final Uint8List? data;

  const NfcBootstrapPayload({
    required this.peerId,
    this.displayName = '',
    this.metadata = const {},
    this.data,
  });

  /// Encode as JSON UTF-8 for MIME NDEF records.
  Uint8List toBytes() {
    final map = <String, Object?>{
      'v': 1,
      'id': peerId,
      'name': displayName,
      if (metadata.isNotEmpty) 'meta': metadata,
      if (data != null) 'data': base64Url.encode(data!),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  factory NfcBootstrapPayload.fromBytes(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return NfcBootstrapPayload(
      peerId: map['id'] as String? ?? '',
      displayName: map['name'] as String? ?? '',
      metadata: (map['meta'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
      data: map['data'] is String
          ? Uint8List.fromList(base64Url.decode(map['data'] as String))
          : null,
    );
  }

  Peer toPeer() => Peer(
        id: peerId,
        displayName: displayName,
        transports: {TransportKind.nfc},
        addresses: {TransportKind.nfc: peerId},
        lastSeen: DateTime.now().toUtc(),
        metadata: metadata,
      );
}

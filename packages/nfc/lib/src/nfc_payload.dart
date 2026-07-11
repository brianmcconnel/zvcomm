import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Compact identity + optional credential / data carried over NFC NDEF.
///
/// JSON MIME record (`application/x-zvcomm`). When [credential] is set, the
/// tap exchanges a full self-signed [PublicCredential] for QR-less pairing.
final class NfcBootstrapPayload {
  final String peerId;
  final String displayName;
  final Map<String, String> metadata;
  final Uint8List? data;

  /// Optional public credential (self-signed keys) for NFC exchange.
  final PublicCredential? credential;

  const NfcBootstrapPayload({
    required this.peerId,
    this.displayName = '',
    this.metadata = const {},
    this.data,
    this.credential,
  });

  /// Build a payload that carries [credential] for NFC write-on-tap.
  factory NfcBootstrapPayload.forCredential(PublicCredential credential) {
    return NfcBootstrapPayload(
      peerId: credential.subjectId,
      displayName: credential.displayName,
      metadata: const {'kind': 'cred'},
      credential: credential,
    );
  }

  /// Encode as JSON UTF-8 for MIME NDEF records.
  Uint8List toBytes() {
    final map = <String, Object?>{
      'v': 2,
      'id': peerId,
      'name': displayName,
      if (metadata.isNotEmpty) 'meta': metadata,
      if (data != null) 'data': base64Url.encode(data!),
      if (credential != null) 'cred': credential!.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  factory NfcBootstrapPayload.fromBytes(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    PublicCredential? cred;
    final rawCred = map['cred'];
    if (rawCred is Map) {
      try {
        cred = PublicCredential.fromJson(
          Map<String, Object?>.from(rawCred),
        );
      } catch (_) {
        cred = null;
      }
    }
    // Also accept a bare QR payload string in meta.
    if (cred == null && map['meta'] is Map) {
      final meta = Map<String, dynamic>.from(map['meta'] as Map);
      final qr = meta['qr'] ?? meta['cred'];
      if (qr is String && qr.isNotEmpty) {
        try {
          cred = PublicCredential.parse(qr);
        } catch (_) {}
      }
    }
    return NfcBootstrapPayload(
      peerId: map['id'] as String? ?? cred?.subjectId ?? '',
      displayName: map['name'] as String? ?? cred?.displayName ?? '',
      metadata: (map['meta'] as Map<String, dynamic>? ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
      data: map['data'] is String
          ? Uint8List.fromList(base64Url.decode(map['data'] as String))
          : null,
      credential: cred,
    );
  }

  Peer toPeer() => Peer(
        id: peerId.isNotEmpty ? peerId : (credential?.subjectId ?? 'unknown'),
        displayName: displayName.isNotEmpty
            ? displayName
            : (credential?.displayName ?? ''),
        transports: {TransportKind.nfc},
        addresses: {
          TransportKind.nfc:
              peerId.isNotEmpty ? peerId : (credential?.subjectId ?? ''),
        },
        lastSeen: DateTime.now().toUtc(),
        metadata: {
          ...metadata,
          if (credential != null) 'shortCode': credential!.shortCode,
        },
      );
}

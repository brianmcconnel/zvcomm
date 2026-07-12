import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

/// Compact identity + optional credential / URI payload for NFC NDEF.
///
/// JSON MIME record (`application/x-zvcomm`).
/// - [credential]: peer public credential (`kind=cred`)
/// - [uriPayload]: any `zvcomm:…` URI (cred or org) for generic share
final class NfcBootstrapPayload {
  final String peerId;
  final String displayName;
  final Map<String, String> metadata;
  final Uint8List? data;

  /// Optional public credential (self-signed keys) for NFC exchange.
  final PublicCredential? credential;

  /// Optional raw URI (`zvcomm:cred:v1:…` or `zvcomm:org:v1:…`).
  final String? uriPayload;

  const NfcBootstrapPayload({
    required this.peerId,
    this.displayName = '',
    this.metadata = const {},
    this.data,
    this.credential,
    this.uriPayload,
  });

  /// Build a payload that carries [credential] for NFC write-on-tap.
  factory NfcBootstrapPayload.forCredential(PublicCredential credential) {
    return NfcBootstrapPayload(
      peerId: credential.subjectId,
      displayName: credential.displayName,
      metadata: const {'kind': 'cred'},
      credential: credential,
      uriPayload: credential.toQrPayload(),
    );
  }

  /// Build a payload that carries an arbitrary ZVComm URI (org or cred).
  factory NfcBootstrapPayload.forUri({
    required String uri,
    required String peerId,
    String displayName = '',
  }) {
    final kind = uri.toLowerCase().startsWith('zvcomm:org:') ? 'org' : 'uri';
    return NfcBootstrapPayload(
      peerId: peerId,
      displayName: displayName,
      metadata: {'kind': kind, 'qr': uri},
      data: Uint8List.fromList(utf8.encode(uri)),
      uriPayload: uri,
    );
  }

  /// Encode as JSON UTF-8 for MIME NDEF records.
  Uint8List toBytes() {
    final map = <String, Object?>{
      'v': 3,
      'id': peerId,
      'name': displayName,
      if (metadata.isNotEmpty) 'meta': metadata,
      if (data != null) 'data': base64Url.encode(data!),
      if (credential != null) 'cred': credential!.toJson(),
      if (uriPayload != null && uriPayload!.isNotEmpty) 'uri': uriPayload,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  factory NfcBootstrapPayload.fromBytes(Uint8List bytes) {
    final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    PublicCredential? cred;
    String? uri;
    final rawCred = map['cred'];
    if (rawCred is Map) {
      try {
        cred = PublicCredential.fromJson(
          Map<String, Object?>.from(rawCred),
        );
        uri = cred.toQrPayload();
      } catch (_) {
        cred = null;
      }
    }
    if (map['uri'] is String && (map['uri'] as String).isNotEmpty) {
      uri = map['uri'] as String;
    }
    // Also accept a bare QR payload string in meta / data.
    if (uri == null && map['meta'] is Map) {
      final meta = Map<String, dynamic>.from(map['meta'] as Map);
      final qr = meta['qr'] ?? meta['cred'] ?? meta['org'];
      if (qr is String && qr.isNotEmpty) {
        uri = qr;
        if (cred == null && qr.toLowerCase().startsWith('zvcomm:cred:')) {
          try {
            cred = PublicCredential.parse(qr);
          } catch (_) {}
        }
      }
    }
    if (uri == null && map['data'] is String) {
      try {
        final raw = utf8.decode(base64Url.decode(map['data'] as String));
        if (raw.startsWith('zvcomm:')) {
          uri = raw;
          if (cred == null && raw.toLowerCase().startsWith('zvcomm:cred:')) {
            try {
              cred = PublicCredential.parse(raw);
            } catch (_) {}
          }
        }
      } catch (_) {}
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
      uriPayload: uri,
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
          if (uriPayload != null) 'uri': uriPayload!,
        },
      );
}

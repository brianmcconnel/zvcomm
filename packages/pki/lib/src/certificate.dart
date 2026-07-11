import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Mesh certificate signed with Ed25519 (not X.509; compact for short-range).
final class MeshCertificate {
  final String subjectId;
  final String issuerId;
  final DateTime notBefore;
  final DateTime notAfter;
  final Uint8List publicKey; // subject Ed25519 public
  final Uint8List? x25519PublicKey; // subject X25519 public (optional)
  final Uint8List signature;
  final List<String> capabilities;
  final int serial;

  const MeshCertificate({
    required this.subjectId,
    required this.issuerId,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
    required this.signature,
    this.x25519PublicKey,
    this.capabilities = const ['mesh'],
    this.serial = 1,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(notAfter);

  bool isValidAt(DateTime instant) =>
      !instant.isBefore(notBefore) && !instant.isAfter(notAfter);

  Map<String, Object?> toJson() => {
        'v': 2,
        'serial': serial,
        'subjectId': subjectId,
        'issuerId': issuerId,
        'notBefore': notBefore.toIso8601String(),
        'notAfter': notAfter.toIso8601String(),
        'publicKey': base64Url.encode(publicKey),
        if (x25519PublicKey != null)
          'x25519PublicKey': base64Url.encode(x25519PublicKey!),
        'signature': base64Url.encode(signature),
        'capabilities': capabilities,
      };

  factory MeshCertificate.fromJson(Map<String, Object?> json) {
    return MeshCertificate(
      subjectId: json['subjectId']! as String,
      issuerId: json['issuerId']! as String,
      notBefore: DateTime.parse(json['notBefore']! as String),
      notAfter: DateTime.parse(json['notAfter']! as String),
      publicKey: Uint8List.fromList(
        base64Url.decode(json['publicKey']! as String),
      ),
      x25519PublicKey: json['x25519PublicKey'] is String
          ? Uint8List.fromList(
              base64Url.decode(json['x25519PublicKey']! as String),
            )
          : null,
      signature: Uint8List.fromList(
        base64Url.decode(json['signature']! as String),
      ),
      capabilities:
          (json['capabilities'] as List<dynamic>? ?? const []).cast<String>(),
      serial: json['serial'] as int? ?? 1,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory MeshCertificate.fromJsonString(String s) => MeshCertificate.fromJson(
        Map<String, Object?>.from(jsonDecode(s) as Map),
      );

  /// To-be-signed payload (excludes signature).
  Uint8List tbsBytes() {
    final payload = jsonEncode({
      'v': 2,
      'serial': serial,
      'subjectId': subjectId,
      'issuerId': issuerId,
      'notBefore': notBefore.toIso8601String(),
      'notAfter': notAfter.toIso8601String(),
      'publicKey': base64Url.encode(publicKey),
      if (x25519PublicKey != null)
        'x25519PublicKey': base64Url.encode(x25519PublicKey!),
      'capabilities': capabilities,
    });
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// Verify Ed25519 signature with [issuerEd25519Public] (32 bytes).
  Future<bool> verifyEd25519(Uint8List issuerEd25519Public) async {
    return Ed25519().verify(
      tbsBytes(),
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(
          issuerEd25519Public,
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  /// Legacy HMAC verify kept for reading v1 certs if needed.
  @Deprecated('Use verifyEd25519')
  bool verifyPlaceholder(Uint8List issuerKey) {
    return false;
  }
}

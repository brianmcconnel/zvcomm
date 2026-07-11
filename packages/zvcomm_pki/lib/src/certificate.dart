import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Minimal certificate-like record for mesh identity (not X.509 yet).
///
/// Phase 3 will align with Noise keys and optionally X.509 / CFSSL output.
final class MeshCertificate {
  final String subjectId;
  final String issuerId;
  final DateTime notBefore;
  final DateTime notAfter;
  final Uint8List publicKey;
  final Uint8List signature;
  final List<String> capabilities;

  const MeshCertificate({
    required this.subjectId,
    required this.issuerId,
    required this.notBefore,
    required this.notAfter,
    required this.publicKey,
    required this.signature,
    this.capabilities = const ['mesh'],
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(notAfter);

  bool isValidAt(DateTime instant) =>
      !instant.isBefore(notBefore) && !instant.isAfter(notAfter);

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'issuerId': issuerId,
        'notBefore': notBefore.toIso8601String(),
        'notAfter': notAfter.toIso8601String(),
        'publicKey': base64Url.encode(publicKey),
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
      signature: Uint8List.fromList(
        base64Url.decode(json['signature']! as String),
      ),
      capabilities: (json['capabilities'] as List<dynamic>? ?? const [])
          .cast<String>(),
    );
  }

  /// TBS (to-be-signed) bytes for placeholder HMAC-style signing.
  Uint8List tbsBytes() {
    final payload = jsonEncode({
      'subjectId': subjectId,
      'issuerId': issuerId,
      'notBefore': notBefore.toIso8601String(),
      'notAfter': notAfter.toIso8601String(),
      'publicKey': base64Url.encode(publicKey),
      'capabilities': capabilities,
    });
    return Uint8List.fromList(utf8.encode(payload));
  }

  /// Placeholder "signature" = HMAC-SHA256 with issuer private material.
  static Uint8List placeholderSign(Uint8List tbs, Uint8List issuerKey) {
    final hmac = Hmac(sha256, issuerKey);
    return Uint8List.fromList(hmac.convert(tbs).bytes);
  }

  bool verifyPlaceholder(Uint8List issuerKey) {
    final expected = placeholderSign(tbsBytes(), issuerKey);
    if (expected.length != signature.length) return false;
    var ok = 0;
    for (var i = 0; i < expected.length; i++) {
      ok |= expected[i] ^ signature[i];
    }
    return ok == 0;
  }
}

import 'dart:typed_data';

import 'package:zvcomm_core/zvcomm_core.dart';

import 'certificate.dart';

/// Minimal local CA for demos and tests (Phase 0).
///
/// Not production-safe: uses placeholder HMAC signatures, not real asymmetric
/// PKI. Phase 3 will integrate pointycastle / platform crypto / CFSSL.
final class LocalCa {
  final DeviceIdentity root;
  final Duration defaultTtl;

  LocalCa({
    required this.root,
    this.defaultTtl = const Duration(days: 30),
  });

  factory LocalCa.generate({String displayName = 'ZVComm Root'}) {
    return LocalCa(
      root: DeviceIdentity.generate(displayName: displayName),
    );
  }

  MeshCertificate issueFor(
    DeviceIdentity subject, {
    Duration? ttl,
    List<String> capabilities = const ['mesh', 'chat'],
  }) {
    final now = DateTime.now().toUtc();
    final notAfter = now.add(ttl ?? defaultTtl);
    final unsigned = MeshCertificate(
      subjectId: subject.id,
      issuerId: root.id,
      notBefore: now,
      notAfter: notAfter,
      publicKey: subject.publicKeyBytes,
      signature: Uint8List(0),
      capabilities: capabilities,
    );
    final sig = MeshCertificate.placeholderSign(
      unsigned.tbsBytes(),
      root.privateKeyBytes,
    );
    return MeshCertificate(
      subjectId: unsigned.subjectId,
      issuerId: unsigned.issuerId,
      notBefore: unsigned.notBefore,
      notAfter: unsigned.notAfter,
      publicKey: unsigned.publicKey,
      signature: sig,
      capabilities: unsigned.capabilities,
    );
  }

  bool verify(MeshCertificate cert) {
    if (cert.issuerId != root.id) return false;
    if (!cert.isValidAt(DateTime.now().toUtc())) return false;
    return cert.verifyPlaceholder(root.privateKeyBytes);
  }
}

import 'dart:typed_data';

import 'package:zvcomm_core/zvcomm_core.dart';

import 'certificate.dart';
import 'revocation.dart';

/// Local certificate authority using Ed25519 signatures.
final class LocalCa {
  final DeviceIdentity root;
  final Duration defaultTtl;
  int _serial = 1;
  final RevocationList _revocations = RevocationList();

  LocalCa({
    required this.root,
    this.defaultTtl = const Duration(days: 30),
  });

  static Future<LocalCa> generate({
    String displayName = 'ZVComm Root',
  }) async {
    final root = await DeviceIdentity.generate(displayName: displayName);
    return LocalCa(root: root);
  }

  RevocationList get revocations => _revocations;

  Future<MeshCertificate> issueFor(
    DeviceIdentity subject, {
    Duration? ttl,
    List<String> capabilities = const ['mesh', 'chat'],
  }) async {
    final now = DateTime.now().toUtc();
    final notAfter = now.add(ttl ?? defaultTtl);
    final serial = _serial++;
    final unsigned = MeshCertificate(
      subjectId: subject.id,
      issuerId: root.id,
      notBefore: now,
      notAfter: notAfter,
      publicKey: subject.ed25519PublicKey,
      x25519PublicKey: subject.x25519PublicKey,
      signature: Uint8List(0),
      capabilities: capabilities,
      serial: serial,
    );
    final sig = await root.sign(unsigned.tbsBytes());
    return MeshCertificate(
      subjectId: unsigned.subjectId,
      issuerId: unsigned.issuerId,
      notBefore: unsigned.notBefore,
      notAfter: unsigned.notAfter,
      publicKey: unsigned.publicKey,
      x25519PublicKey: unsigned.x25519PublicKey,
      signature: sig,
      capabilities: unsigned.capabilities,
      serial: unsigned.serial,
    );
  }

  /// Issue from an enrollment request after verifying self-signature.
  Future<MeshCertificate> issueEnrollment(
    EnrollmentRequest request, {
    Duration? ttl,
    List<String> capabilities = const ['mesh', 'chat'],
  }) async {
    if (!await request.verifySelf()) {
      throw StateError('enrollment request signature invalid');
    }
    final subject = DeviceIdentity(
      id: request.subjectId,
      displayName: request.displayName,
      x25519PublicKey: request.x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: request.ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    return issueFor(subject, ttl: ttl, capabilities: capabilities);
  }

  Future<bool> verify(MeshCertificate cert) async {
    if (cert.issuerId != root.id) return false;
    if (!cert.isValidAt(DateTime.now().toUtc())) return false;
    if (_revocations.isRevoked(cert.subjectId)) return false;
    return cert.verifyEd25519(root.ed25519PublicKey);
  }

  void revoke(String subjectId, {String reason = 'unspecified'}) {
    _revocations.revoke(subjectId, reason: reason);
  }

  Future<SignedRevocationList> exportRevocationList() =>
      SignedRevocationList.sign(_revocations, root);
}

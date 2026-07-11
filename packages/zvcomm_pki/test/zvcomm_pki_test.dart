import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_pki/zvcomm_pki.dart';

void main() {
  test('LocalCa issues and verifies Ed25519 certificates', () async {
    final ca = await LocalCa.generate();
    final device =
        await DeviceIdentity.fromSeed('device-1', displayName: 'Phone');
    final cert = await ca.issueFor(device);
    expect(await ca.verify(cert), isTrue);
    expect(cert.subjectId, device.id);
    expect(cert.isExpired, isFalse);
    expect(cert.x25519PublicKey, isNotNull);
  });

  test('certificate JSON round-trip', () async {
    final ca = await LocalCa.generate();
    final device = await DeviceIdentity.fromSeed('device-2');
    final cert = await ca.issueFor(device);
    final restored = MeshCertificate.fromJson(cert.toJson());
    expect(restored.subjectId, cert.subjectId);
    expect(await ca.verify(restored), isTrue);
  });

  test('enrollment request → CA → accept', () async {
    final ca = await LocalCa.generate();
    final device =
        await DeviceIdentity.fromSeed('enroll-me', displayName: 'Watch');
    final req = await EnrollmentService.createRequest(device);
    expect(await req.verifySelf(), isTrue);

    final svc = EnrollmentService(ca);
    final resp = await svc.processRequest(req);
    final caPub = DeviceIdentity(
      id: ca.root.id,
      displayName: ca.root.displayName,
      x25519PublicKey: ca.root.x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: ca.root.ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    final cert = await EnrollmentService.acceptResponse(
      resp,
      caPublic: caPub,
    );
    expect(cert, isNotNull);
    expect(cert!.subjectId, device.id);
    expect(await ca.verify(cert), isTrue);
  });

  test('revocation list sign and detect', () async {
    final ca = await LocalCa.generate();
    final device = await DeviceIdentity.fromSeed('revoked');
    final cert = await ca.issueFor(device);
    expect(await ca.verify(cert), isTrue);
    ca.revoke(device.id, reason: 'lost');
    expect(await ca.verify(cert), isFalse);
    final crl = await ca.exportRevocationList();
    expect(await crl.verify(ca.root), isTrue);
    expect(crl.list.isRevoked(device.id), isTrue);
  });
}

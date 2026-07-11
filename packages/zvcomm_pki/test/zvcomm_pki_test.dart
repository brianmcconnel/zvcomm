import 'package:test/test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_pki/zvcomm_pki.dart';

void main() {
  test('LocalCa issues and verifies placeholder certificates', () {
    final ca = LocalCa.generate();
    final device = DeviceIdentity.fromSeed('device-1', displayName: 'Phone');
    final cert = ca.issueFor(device);
    expect(ca.verify(cert), isTrue);
    expect(cert.subjectId, device.id);
    expect(cert.isExpired, isFalse);
  });

  test('certificate JSON round-trip', () {
    final ca = LocalCa.generate();
    final device = DeviceIdentity.fromSeed('device-2');
    final cert = ca.issueFor(device);
    final restored = MeshCertificate.fromJson(cert.toJson());
    expect(restored.subjectId, cert.subjectId);
    expect(ca.verify(restored), isTrue);
  });
}

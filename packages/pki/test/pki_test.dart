import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:core/core.dart';
import 'package:pki/pki.dart';

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

  test('organization trust accepts org-issued external certs', () async {
    final ca = await LocalCa.generate(displayName: 'Acme Corp');
    final org = Organization.fromCaRoot(
      ca.root,
      description: 'Acme mesh CA',
      category: OrganizationCategory.companies,
    );
    expect(org.shortCode, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
    expect(org.category, OrganizationCategory.companies);
    expect(org.category.label, 'Companies');

    final payload = org.toQrPayload();
    expect(payload, startsWith('zvcomm:org:v1:'));
    final restored = Organization.parse(payload);
    expect(restored.id, org.id);
    expect(restored.name, 'Acme Corp');
    expect(restored.category, OrganizationCategory.companies);

    final store = TrustStore()..trustOrganization(org);

    final external =
        await DeviceIdentity.fromSeed('contractor', displayName: 'Ext');
    final cert = await ca.issueFor(external);

    // Unknown issuer → not trusted.
    final empty = TrustStore();
    final denied = await empty.trustExternalCertificate(cert);
    expect(denied.isTrusted, isFalse);

    // Trusted org → external accepted.
    final decision = await store.trustExternalCertificate(cert);
    expect(decision.isTrusted, isTrue);
    expect(decision.basis, TrustBasis.organization);
    expect(decision.organizationName, 'Acme Corp');
    expect(store.isTrustedSubject(external.id), isTrue);

    final eval = await store.evaluate(subjectId: external.id);
    expect(eval.basis, TrustBasis.organization);
  });

  test('organizations group by category', () async {
    final store = TrustStore();
    final gov = await LocalCa.generate(displayName: 'City Hall');
    final church = await LocalCa.generate(displayName: 'First Church');
    final family = await LocalCa.generate(displayName: 'Smith Family');
    store.trustOrganization(
      Organization.fromCaRoot(gov.root,
          category: OrganizationCategory.government),
    );
    store.trustOrganization(
      Organization.fromCaRoot(
        church.root,
        category: OrganizationCategory.churches,
      ),
    );
    store.trustOrganization(
      Organization.fromCaRoot(
        family.root,
        category: OrganizationCategory.families,
      ),
    );
    final grouped = store.organizationsByCategory();
    expect(grouped.keys.toList(), [
      OrganizationCategory.government,
      OrganizationCategory.churches,
      OrganizationCategory.families,
    ]);
    expect(grouped[OrganizationCategory.government]!.single.name, 'City Hall');
    expect(
      OrganizationCategory.parse('non-profit'),
      OrganizationCategory.nonProfits,
    );
  });

  test('direct peer trust still works alongside orgs', () async {
    final store = TrustStore();
    final alice =
        await DeviceIdentity.fromSeed('alice-org', displayName: 'Alice');
    final cred = await PublicCredential.fromIdentity(alice);
    store.trustDirect(cred);
    final d = await store.evaluate(credential: cred);
    expect(d.basis, TrustBasis.direct);
  });
}

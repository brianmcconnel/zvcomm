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

  test('organization QR / short-code / mesh wire share and import', () async {
    final ca = await LocalCa.generate(displayName: 'Share Corp');
    final org = Organization.fromCaRoot(
      ca.root,
      category: OrganizationCategory.companies,
      description: 'shared via QR',
    );

    // QR payload round-trip.
    final qr = org.toQrPayload();
    expect(qr, startsWith('zvcomm:org:v1:'));
    final fromQr = Organization.parse(qr);
    expect(fromQr.id, org.id);
    expect(fromQr.category, OrganizationCategory.companies);

    // Mesh control frame (org_offer) for short-code publish.
    final wire = OrganizationWire.encodeOffer(org);
    final fromMesh = OrganizationWire.tryDecodeOffer(wire);
    expect(fromMesh, isNotNull);
    expect(fromMesh!.shortCode, org.shortCode);

    // Short-code lookup via offer cache (after publish / NFC).
    final cache = OrganizationOfferCache();
    expect(cache.byShortCode(org.shortCode), isNull);
    cache.put(fromMesh);
    expect(cache.byShortCode(org.shortCode)!.id, org.id);
    expect(cache.byShortCode(org.shortCode.toLowerCase())!.name, 'Share Corp');
    // Mismatched code fails.
    expect(cache.byShortCode('ZZZZ-ZZZZ'), isNull);

    // Import path: parse QR then trust.
    final store = TrustStore()..trustOrganization(fromQr);
    expect(store.organizations[org.id]?.name, 'Share Corp');
  });

  test('organization can be built from CA public credential', () async {
    final ca = await LocalCa.generate(displayName: 'Cred Root');
    final cred = await PublicCredential.fromIdentity(ca.root);
    final org = Organization.fromPublicCredential(
      cred,
      category: OrganizationCategory.government,
    );
    expect(org.id, ca.root.id);
    expect(org.category, OrganizationCategory.government);
    final viaCredUri = Organization.parse(cred.toQrPayload());
    expect(viaCredUri.id, org.id);
  });

  test('delegated issuer can issue member certs under existing org CA',
      () async {
    // Founding org (rare path).
    final rootCa = await LocalCa.generate(displayName: 'City Hall');
    final org = Organization.fromCaRoot(
      rootCa.root,
      category: OrganizationCategory.government,
    );

    // Admin device that will become a delegated issuer.
    final admin =
        await DeviceIdentity.fromSeed('admin-issuer', displayName: 'Admin');
    final adminCred = await PublicCredential.fromIdentity(admin);

    // Root grants issuer authority to admin.
    final adminSubject = DeviceIdentity(
      id: adminCred.subjectId,
      displayName: adminCred.displayName,
      x25519PublicKey: adminCred.x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: adminCred.ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    final authority = await rootCa.issueIssuerFor(adminSubject);
    expect(authority.capabilities, contains(orgIssueCapability));
    expect(await org.verifyIssuerAuthority(authority), isTrue);

    final grant = IssuerAuthority(organization: org, certificate: authority);
    expect(await grant.verify(), isTrue);
    final wire = grant.toQrPayload();
    expect(wire, startsWith('zvcomm:issuer:v1:'));
    final restored = IssuerAuthority.parse(wire);
    expect(restored.certificate.subjectId, admin.id);
    expect(await restored.verify(), isTrue);

    // Admin issues member cert with their own key.
    final delegatedCa = LocalCa(root: admin);
    final member =
        await DeviceIdentity.fromSeed('contractor-1', displayName: 'Bob');
    final memberCert = await delegatedCa.issueFor(
      member,
      capabilities: orgMemberCapabilities,
    );
    expect(memberCert.issuerId, admin.id);
    expect(memberCert.issuerId, isNot(org.id));

    // Third party trusts org root + package chain.
    final store = TrustStore()..trustOrganization(org);
    final pack = OrgMemberPackage(
      certificate: memberCert,
      issuerAuthority: authority,
      organization: org,
    );
    final decision = await store.trustExternalCertificate(
      pack.certificate,
      issuerAuthority: pack.issuerAuthority,
    );
    expect(decision.isTrusted, isTrue);
    expect(decision.organizationId, org.id);
    expect(decision.organizationName, 'City Hall');
    expect(store.isTrustedSubject(member.id), isTrue);

    // Without issuer authority, member cert alone is rejected.
    final empty = TrustStore()..trustOrganization(org);
    final denied = await empty.trustExternalCertificate(memberCert);
    expect(denied.isTrusted, isFalse);
  });
}

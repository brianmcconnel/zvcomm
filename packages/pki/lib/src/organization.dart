import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

import 'certificate.dart';

/// A trusted organization (external trust root).
///
/// When you trust an [Organization], you accept [MeshCertificate]s it issues
/// for external devices — without exchanging credentials with each device.
final class Organization {
  static const int version = 1;
  static const String qrScheme = 'zvcomm';
  static const String qrPath = 'org';

  /// Organization id (fingerprint of the CA Ed25519 public key).
  final String id;

  /// Human-readable organization name.
  final String name;

  /// CA Ed25519 public key used to verify issued certificates.
  final Uint8List ed25519PublicKey;

  /// Optional CA X25519 public key (for future org-level handshake).
  final Uint8List? x25519PublicKey;

  final String? description;

  /// When this org was added to the local trust store.
  final DateTime trustedAt;

  /// Capabilities we accept from this org's members (empty = any).
  final List<String> allowCapabilities;

  const Organization({
    required this.id,
    required this.name,
    required this.ed25519PublicKey,
    this.x25519PublicKey,
    this.description,
    required this.trustedAt,
    this.allowCapabilities = const ['mesh', 'chat'],
  });

  String get shortCode => ShortCode.fromSubjectId(id);

  /// Build from a local CA root (export as public org trust anchor).
  factory Organization.fromCaRoot(
    DeviceIdentity root, {
    String? description,
    List<String> allowCapabilities = const ['mesh', 'chat'],
    DateTime? trustedAt,
  }) {
    return Organization(
      id: root.id,
      name: root.displayName.isEmpty ? 'Organization' : root.displayName,
      ed25519PublicKey: root.ed25519PublicKey,
      x25519PublicKey: root.x25519PublicKey,
      description: description,
      trustedAt: trustedAt ?? DateTime.now().toUtc(),
      allowCapabilities: allowCapabilities,
    );
  }

  /// Build from a self-signed [PublicCredential] that represents an org CA.
  factory Organization.fromPublicCredential(
    PublicCredential cred, {
    String? description,
    List<String> allowCapabilities = const ['mesh', 'chat'],
    DateTime? trustedAt,
  }) {
    return Organization(
      id: cred.subjectId,
      name: cred.displayName.isEmpty ? 'Organization' : cred.displayName,
      ed25519PublicKey: cred.ed25519PublicKey,
      x25519PublicKey: cred.x25519PublicKey,
      description: description,
      trustedAt: trustedAt ?? DateTime.now().toUtc(),
      allowCapabilities: allowCapabilities,
    );
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'kind': 'organization',
        'id': id,
        'name': name,
        'ed25519PublicKey': base64Url.encode(ed25519PublicKey),
        if (x25519PublicKey != null)
          'x25519PublicKey': base64Url.encode(x25519PublicKey!),
        if (description != null && description!.isNotEmpty)
          'description': description,
        'trustedAt': trustedAt.toIso8601String(),
        'allowCapabilities': allowCapabilities,
      };

  factory Organization.fromJson(Map<String, Object?> json) {
    final id = (json['id'] ?? json['i']) as String?;
    final name = (json['name'] ?? json['n']) as String? ?? 'Organization';
    final ed = (json['ed25519PublicKey'] ?? json['e']) as String?;
    if (id == null || ed == null) {
      throw const FormatException('organization missing id or public key');
    }
    final x = json['x25519PublicKey'] ?? json['x'];
    final caps = json['allowCapabilities'];
    return Organization(
      id: id,
      name: name,
      ed25519PublicKey: Uint8List.fromList(base64Url.decode(ed)),
      x25519PublicKey:
          x is String ? Uint8List.fromList(base64Url.decode(x)) : null,
      description: json['description'] as String?,
      trustedAt: json['trustedAt'] is String
          ? DateTime.parse(json['trustedAt']! as String)
          : DateTime.now().toUtc(),
      allowCapabilities: caps is List
          ? caps.map((e) => e.toString()).toList()
          : const ['mesh', 'chat'],
    );
  }

  /// QR / clipboard: `zvcomm:org:v1:<base64url(json)>`.
  String toQrPayload() {
    final body = base64Url.encode(utf8.encode(jsonEncode(toJson())));
    return '$qrScheme:$qrPath:v$version:$body';
  }

  /// Parse org QR, JSON, or bare base64url JSON.
  static Organization parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('empty organization payload');
    }

    Map<String, Object?> mapFromB64(String b64) => Map<String, Object?>.from(
          jsonDecode(utf8.decode(base64Url.decode(b64))) as Map,
        );

    final prefix = '$qrScheme:$qrPath:v$version:';
    if (input.toLowerCase().startsWith(prefix)) {
      return Organization.fromJson(mapFromB64(input.substring(prefix.length)));
    }
    if (input.toLowerCase().startsWith('zvcomm:org:')) {
      final parts = input.split(':');
      if (parts.length >= 4) {
        return Organization.fromJson(mapFromB64(parts.sublist(3).join(':')));
      }
    }
    if (input.startsWith('{')) {
      return Organization.fromJson(
        Map<String, Object?>.from(jsonDecode(input) as Map),
      );
    }
    // Allow treating a public device credential as an org CA root.
    if (input.toLowerCase().startsWith('zvcomm:cred:')) {
      final cred = PublicCredential.parse(input);
      return Organization.fromPublicCredential(cred);
    }
    try {
      final decoded = utf8.decode(base64Url.decode(input));
      if (decoded.startsWith('{')) {
        return Organization.fromJson(
          Map<String, Object?>.from(jsonDecode(decoded) as Map),
        );
      }
    } catch (_) {}
    throw const FormatException(
      'unrecognized organization payload (expect zvcomm:org:v1:… or JSON)',
    );
  }

  /// Verify that [cert] was issued by this organization and is currently valid.
  Future<bool> verifyMemberCertificate(MeshCertificate cert) async {
    if (cert.issuerId != id) return false;
    if (!cert.isValidAt(DateTime.now().toUtc())) return false;
    if (allowCapabilities.isNotEmpty) {
      final ok = cert.capabilities.any(allowCapabilities.contains);
      if (!ok && cert.capabilities.isNotEmpty) return false;
    }
    return cert.verifyEd25519(ed25519PublicKey);
  }
}

/// Why a peer is trusted.
enum TrustBasis {
  /// Not trusted.
  none,

  /// Direct peer credential exchange (QR / NFC / short code).
  direct,

  /// Certificate issued by a trusted organization.
  organization,
}

/// Result of a trust evaluation.
final class TrustDecision {
  final TrustBasis basis;
  final String? organizationId;
  final String? organizationName;
  final String? subjectId;
  final String? detail;

  const TrustDecision.none([this.detail])
      : basis = TrustBasis.none,
        organizationId = null,
        organizationName = null,
        subjectId = null;

  const TrustDecision.direct({required this.subjectId, this.detail})
      : basis = TrustBasis.direct,
        organizationId = null,
        organizationName = null;

  const TrustDecision.organization({
    required this.subjectId,
    required this.organizationId,
    required this.organizationName,
    this.detail,
  }) : basis = TrustBasis.organization;

  bool get isTrusted => basis != TrustBasis.none;

  Map<String, Object?> toJson() => {
        'basis': basis.name,
        if (subjectId != null) 'subjectId': subjectId,
        if (organizationId != null) 'organizationId': organizationId,
        if (organizationName != null) 'organizationName': organizationName,
        if (detail != null) 'detail': detail,
      };
}

/// Local trust store: organizations + direct peers + org-issued externals.
final class TrustStore {
  TrustStore();

  final Map<String, Organization> organizations = {};
  final Map<String, PublicCredential> directPeers = {};
  final Map<String, MeshCertificate> externalCerts = {};
  final Map<String, String> externalOrgBySubject = {};

  /// Trust an organization as a root for external certificates.
  void trustOrganization(Organization org) {
    organizations[org.id] = org;
  }

  void untrustOrganization(String orgId) {
    organizations.remove(orgId);
    final subjects = externalOrgBySubject.entries
        .where((e) => e.value == orgId)
        .map((e) => e.key)
        .toList();
    for (final s in subjects) {
      externalCerts.remove(s);
      externalOrgBySubject.remove(s);
    }
  }

  /// Trust a peer from direct credential exchange.
  void trustDirect(PublicCredential cred) {
    directPeers[cred.subjectId] = cred;
  }

  void untrustDirect(String subjectId) {
    directPeers.remove(subjectId);
  }

  /// Accept an external member certificate if its issuer org is trusted.
  Future<TrustDecision> trustExternalCertificate(MeshCertificate cert) async {
    final org = organizations[cert.issuerId];
    if (org == null) {
      return TrustDecision.none(
        'issuer ${cert.issuerId} is not a trusted organization',
      );
    }
    if (!await org.verifyMemberCertificate(cert)) {
      return const TrustDecision.none(
          'certificate signature or validity failed');
    }
    externalCerts[cert.subjectId] = cert;
    externalOrgBySubject[cert.subjectId] = org.id;
    return TrustDecision.organization(
      subjectId: cert.subjectId,
      organizationId: org.id,
      organizationName: org.name,
      detail: 'org-issued cert serial ${cert.serial}',
    );
  }

  /// Evaluate trust for a subject with optional credential/certificate proof.
  Future<TrustDecision> evaluate({
    String? subjectId,
    PublicCredential? credential,
    MeshCertificate? certificate,
  }) async {
    final id = subjectId ?? credential?.subjectId ?? certificate?.subjectId;
    if (id == null) return const TrustDecision.none('no subject');

    if (directPeers.containsKey(id)) {
      return TrustDecision.direct(subjectId: id, detail: 'direct credential');
    }

    if (certificate != null) {
      final d = await trustExternalCertificate(certificate);
      if (d.isTrusted) return d;
    }

    final cached = externalCerts[id];
    if (cached != null) {
      final orgId = externalOrgBySubject[id];
      final org = orgId != null ? organizations[orgId] : null;
      if (org != null && await org.verifyMemberCertificate(cached)) {
        return TrustDecision.organization(
          subjectId: id,
          organizationId: org.id,
          organizationName: org.name,
        );
      }
    }

    // Credential that is itself a trusted org root.
    if (credential != null && organizations.containsKey(credential.subjectId)) {
      final org = organizations[credential.subjectId]!;
      return TrustDecision.organization(
        subjectId: id,
        organizationId: org.id,
        organizationName: org.name,
        detail: 'organization root credential',
      );
    }

    return const TrustDecision.none('not trusted');
  }

  bool isTrustedSubject(String subjectId) =>
      directPeers.containsKey(subjectId) ||
      externalCerts.containsKey(subjectId) ||
      organizations.containsKey(subjectId);

  List<Organization> get organizationList =>
      organizations.values.toList(growable: false);

  Map<String, Object?> toJson() => {
        'organizations': organizations.values.map((o) => o.toJson()).toList(),
        'directPeers': directPeers.values.map((c) => c.toJson()).toList(),
        'externalCerts': externalCerts.values.map((c) => c.toJson()).toList(),
      };

  factory TrustStore.fromJson(Map<String, Object?> json) {
    final store = TrustStore();
    final orgs = json['organizations'];
    if (orgs is List) {
      for (final o in orgs) {
        if (o is Map) {
          final org = Organization.fromJson(Map<String, Object?>.from(o));
          store.trustOrganization(org);
        }
      }
    }
    final peers = json['directPeers'];
    if (peers is List) {
      for (final p in peers) {
        if (p is Map) {
          store.trustDirect(
            PublicCredential.fromJson(Map<String, Object?>.from(p)),
          );
        }
      }
    }
    final certs = json['externalCerts'];
    if (certs is List) {
      for (final c in certs) {
        if (c is Map) {
          final cert = MeshCertificate.fromJson(Map<String, Object?>.from(c));
          store.externalCerts[cert.subjectId] = cert;
          store.externalOrgBySubject[cert.subjectId] = cert.issuerId;
        }
      }
    }
    return store;
  }
}

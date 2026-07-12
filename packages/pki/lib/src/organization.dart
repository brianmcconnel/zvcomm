import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

import 'certificate.dart';

/// Classification for trusted organizations (UI grouping + policy).
enum OrganizationCategory {
  government,
  churches,
  families,
  companies,
  nonProfits,
  other;

  /// Display label for UI.
  String get label => switch (this) {
        OrganizationCategory.government => 'Government',
        OrganizationCategory.churches => 'Churches',
        OrganizationCategory.families => 'Families',
        OrganizationCategory.companies => 'Companies',
        OrganizationCategory.nonProfits => 'Non-Profits',
        OrganizationCategory.other => 'Other',
      };

  /// Stable wire/JSON id.
  String get id => switch (this) {
        OrganizationCategory.government => 'government',
        OrganizationCategory.churches => 'churches',
        OrganizationCategory.families => 'families',
        OrganizationCategory.companies => 'companies',
        OrganizationCategory.nonProfits => 'non_profits',
        OrganizationCategory.other => 'other',
      };

  /// All categories in display order.
  static const List<OrganizationCategory> displayOrder = [
    OrganizationCategory.government,
    OrganizationCategory.churches,
    OrganizationCategory.families,
    OrganizationCategory.companies,
    OrganizationCategory.nonProfits,
    OrganizationCategory.other,
  ];

  static OrganizationCategory parse(String? raw) {
    if (raw == null || raw.isEmpty) return OrganizationCategory.other;
    final s =
        raw.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
    return switch (s) {
      'government' || 'gov' || 'govt' => OrganizationCategory.government,
      'churches' ||
      'church' ||
      'religious' ||
      'faith' =>
        OrganizationCategory.churches,
      'families' || 'family' || 'household' => OrganizationCategory.families,
      'companies' ||
      'company' ||
      'corp' ||
      'business' ||
      'enterprise' =>
        OrganizationCategory.companies,
      'non_profits' ||
      'non_profit' ||
      'nonprofit' ||
      'nonprofits' ||
      'ngo' ||
      'charity' =>
        OrganizationCategory.nonProfits,
      _ => OrganizationCategory.other,
    };
  }
}

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

  /// Category for grouping (Government, Churches, Families, …).
  final OrganizationCategory category;

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
    this.category = OrganizationCategory.other,
    required this.trustedAt,
    this.allowCapabilities = const ['mesh', 'chat'],
  });

  String get shortCode => ShortCode.fromSubjectId(id);

  Organization copyWith({
    String? name,
    String? description,
    OrganizationCategory? category,
    DateTime? trustedAt,
    List<String>? allowCapabilities,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      ed25519PublicKey: ed25519PublicKey,
      x25519PublicKey: x25519PublicKey,
      description: description ?? this.description,
      category: category ?? this.category,
      trustedAt: trustedAt ?? this.trustedAt,
      allowCapabilities: allowCapabilities ?? this.allowCapabilities,
    );
  }

  /// Build from a local CA root (export as public org trust anchor).
  factory Organization.fromCaRoot(
    DeviceIdentity root, {
    String? description,
    OrganizationCategory category = OrganizationCategory.other,
    List<String> allowCapabilities = const ['mesh', 'chat'],
    DateTime? trustedAt,
  }) {
    return Organization(
      id: root.id,
      name: root.displayName.isEmpty ? 'Organization' : root.displayName,
      ed25519PublicKey: root.ed25519PublicKey,
      x25519PublicKey: root.x25519PublicKey,
      description: description,
      category: category,
      trustedAt: trustedAt ?? DateTime.now().toUtc(),
      allowCapabilities: allowCapabilities,
    );
  }

  /// Build from a self-signed [PublicCredential] that represents an org CA.
  factory Organization.fromPublicCredential(
    PublicCredential cred, {
    String? description,
    OrganizationCategory category = OrganizationCategory.other,
    List<String> allowCapabilities = const ['mesh', 'chat'],
    DateTime? trustedAt,
  }) {
    return Organization(
      id: cred.subjectId,
      name: cred.displayName.isEmpty ? 'Organization' : cred.displayName,
      ed25519PublicKey: cred.ed25519PublicKey,
      x25519PublicKey: cred.x25519PublicKey,
      description: description,
      category: category,
      trustedAt: trustedAt ?? DateTime.now().toUtc(),
      allowCapabilities: allowCapabilities,
    );
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'kind': 'organization',
        'id': id,
        'name': name,
        'category': category.id,
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
      category: OrganizationCategory.parse(
        (json['category'] ?? json['cat']) as String?,
      ),
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
      return Organization.fromPublicCredential(
        cred,
        category: OrganizationCategory.other,
      );
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

  /// Verify a delegated-issuer grant (must include `org_issue` capability).
  Future<bool> verifyIssuerAuthority(MeshCertificate cert) async {
    if (cert.issuerId != id) return false;
    if (!cert.isValidAt(DateTime.now().toUtc())) return false;
    if (!cert.capabilities.contains('org_issue')) return false;
    return cert.verifyEd25519(ed25519PublicKey);
  }
}

/// In-memory TTL cache of organization offers (mesh / NFC / short-code lookup).
final class OrganizationOfferCache {
  final Map<String, _CachedOrg> _byCode = {};
  final Map<String, _CachedOrg> _byId = {};
  Duration defaultTtl;

  OrganizationOfferCache({this.defaultTtl = const Duration(minutes: 30)});

  void put(Organization org, {Duration? ttl}) {
    final entry = _CachedOrg(
      org,
      DateTime.now().toUtc().add(ttl ?? defaultTtl),
    );
    _byCode[ShortCode.normalize(org.shortCode)] = entry;
    _byId[org.id] = entry;
  }

  Organization? byShortCode(String code) {
    _purge();
    return _byCode[ShortCode.normalize(code)]?.org;
  }

  Organization? byId(String id) {
    _purge();
    return _byId[id]?.org;
  }

  List<Organization> get all {
    _purge();
    return _byId.values.map((e) => e.org).toList(growable: false);
  }

  void clear() {
    _byCode.clear();
    _byId.clear();
  }

  void _purge() {
    final now = DateTime.now().toUtc();
    final expired = <String>[];
    _byId.forEach((id, e) {
      if (e.expiresAt.isBefore(now)) expired.add(id);
    });
    for (final id in expired) {
      final e = _byId.remove(id);
      if (e != null) {
        _byCode.remove(ShortCode.normalize(e.org.shortCode));
      }
    }
  }
}

final class _CachedOrg {
  final Organization org;
  final DateTime expiresAt;
  _CachedOrg(this.org, this.expiresAt);
}

/// Mesh control payload for organization trust anchors.
abstract final class OrganizationWire {
  static const typeKey = 'type';
  static const offerType = 'org_offer';

  static Uint8List encodeOffer(Organization org) {
    final body = {
      typeKey: offerType,
      'org': org.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  static Organization? tryDecodeOffer(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      if (map[typeKey] != offerType) return null;
      final raw = map['org'];
      if (raw is! Map) return null;
      return Organization.fromJson(Map<String, Object?>.from(raw));
    } catch (_) {
      return null;
    }
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

/// Local trust store: organizations + direct peers + org-issued externals
/// + delegated issuers authorized by org roots.
final class TrustStore {
  TrustStore();

  final Map<String, Organization> organizations = {};
  final Map<String, PublicCredential> directPeers = {};
  final Map<String, MeshCertificate> externalCerts = {};
  final Map<String, String> externalOrgBySubject = {};

  /// Delegated issuers: issuer subject id → authority cert (from org root).
  final Map<String, MeshCertificate> authorizedIssuers = {};

  /// issuer subject id → org root id.
  final Map<String, String> issuerOrgBySubject = {};

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
    final issuers = issuerOrgBySubject.entries
        .where((e) => e.value == orgId)
        .map((e) => e.key)
        .toList();
    for (final s in issuers) {
      authorizedIssuers.remove(s);
      issuerOrgBySubject.remove(s);
    }
  }

  /// Trust a peer from direct credential exchange.
  void trustDirect(PublicCredential cred) {
    directPeers[cred.subjectId] = cred;
  }

  void untrustDirect(String subjectId) {
    directPeers.remove(subjectId);
  }

  /// Register a delegated issuer after verifying against a trusted org root.
  Future<TrustDecision> trustIssuerAuthority(MeshCertificate authority) async {
    final org = organizations[authority.issuerId];
    if (org == null) {
      return TrustDecision.none(
        'issuer authority org ${authority.issuerId} is not trusted — import org first',
      );
    }
    if (!await org.verifyIssuerAuthority(authority)) {
      return const TrustDecision.none(
        'issuer authority signature, validity, or org_issue capability failed',
      );
    }
    authorizedIssuers[authority.subjectId] = authority;
    issuerOrgBySubject[authority.subjectId] = org.id;
    return TrustDecision.organization(
      subjectId: authority.subjectId,
      organizationId: org.id,
      organizationName: org.name,
      detail: 'authorized issuer serial ${authority.serial}',
    );
  }

  /// Accept an external member certificate if signed by a trusted org root
  /// or by a registered delegated issuer for that org.
  Future<TrustDecision> trustExternalCertificate(
    MeshCertificate cert, {
    MeshCertificate? issuerAuthority,
  }) async {
    // Optional: register delegated issuer from package chain first.
    if (issuerAuthority != null) {
      final auth = await trustIssuerAuthority(issuerAuthority);
      if (!auth.isTrusted) {
        return TrustDecision.none(
          auth.detail ?? 'bundled issuer authority rejected',
        );
      }
    }

    // Path 1: signed directly by org root.
    final rootOrg = organizations[cert.issuerId];
    if (rootOrg != null) {
      if (!await rootOrg.verifyMemberCertificate(cert)) {
        return const TrustDecision.none(
          'certificate signature or validity failed',
        );
      }
      externalCerts[cert.subjectId] = cert;
      externalOrgBySubject[cert.subjectId] = rootOrg.id;
      return TrustDecision.organization(
        subjectId: cert.subjectId,
        organizationId: rootOrg.id,
        organizationName: rootOrg.name,
        detail: 'org-root cert serial ${cert.serial}',
      );
    }

    // Path 2: signed by delegated issuer authorized under a trusted org.
    final authority = authorizedIssuers[cert.issuerId];
    final orgId = issuerOrgBySubject[cert.issuerId];
    final org = orgId != null ? organizations[orgId] : null;
    if (authority == null || org == null) {
      return TrustDecision.none(
        'issuer ${cert.issuerId} is not a trusted org or delegated issuer',
      );
    }
    if (!cert.isValidAt(DateTime.now().toUtc())) {
      return const TrustDecision.none('certificate expired or not yet valid');
    }
    if (!await cert.verifyEd25519(authority.publicKey)) {
      return const TrustDecision.none(
        'delegated-issuer signature verification failed',
      );
    }
    // Re-check authority still valid under org root.
    if (!await org.verifyIssuerAuthority(authority)) {
      return const TrustDecision.none('issuer authority no longer valid');
    }
    externalCerts[cert.subjectId] = cert;
    externalOrgBySubject[cert.subjectId] = org.id;
    return TrustDecision.organization(
      subjectId: cert.subjectId,
      organizationId: org.id,
      organizationName: org.name,
      detail: 'delegated-issuer cert serial ${cert.serial}',
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

  /// Known subject ids tied to [orgId] (root, members, delegated issuers).
  ///
  /// Used for org calendar fan-out so events reach trusted org participants.
  List<String> subjectsForOrganization(String orgId) {
    final out = <String>{};
    if (organizations.containsKey(orgId)) out.add(orgId);
    for (final e in externalOrgBySubject.entries) {
      if (e.value == orgId) out.add(e.key);
    }
    for (final e in issuerOrgBySubject.entries) {
      if (e.value == orgId) out.add(e.key);
    }
    return out.toList();
  }

  /// Whether [subjectId] is known under trusted org [orgId].
  bool isOrgSubject(String orgId, String subjectId) {
    if (subjectId == orgId && organizations.containsKey(orgId)) return true;
    if (externalOrgBySubject[subjectId] == orgId) return true;
    if (issuerOrgBySubject[subjectId] == orgId) return true;
    return false;
  }

  List<Organization> get organizationList {
    final list = organizations.values.toList();
    list.sort((a, b) {
      final c = a.category.index.compareTo(b.category.index);
      if (c != 0) return c;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Orgs grouped by [OrganizationCategory] (display order; empty groups omitted
  /// when [includeEmpty] is false).
  Map<OrganizationCategory, List<Organization>> organizationsByCategory({
    bool includeEmpty = false,
  }) {
    final map = <OrganizationCategory, List<Organization>>{
      for (final c in OrganizationCategory.displayOrder) c: <Organization>[],
    };
    for (final o in organizationList) {
      map[o.category]!.add(o);
    }
    if (!includeEmpty) {
      map.removeWhere((_, list) => list.isEmpty);
    }
    return map;
  }

  /// Update category (or other fields) of an already-trusted org.
  void updateOrganization(Organization org) {
    if (!organizations.containsKey(org.id)) return;
    organizations[org.id] = org;
  }

  Map<String, Object?> toJson() => {
        'organizations': organizations.values.map((o) => o.toJson()).toList(),
        'directPeers': directPeers.values.map((c) => c.toJson()).toList(),
        'externalCerts': externalCerts.values.map((c) => c.toJson()).toList(),
        'authorizedIssuers':
            authorizedIssuers.values.map((c) => c.toJson()).toList(),
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
    final issuers = json['authorizedIssuers'];
    if (issuers is List) {
      for (final c in issuers) {
        if (c is Map) {
          final cert = MeshCertificate.fromJson(Map<String, Object?>.from(c));
          store.authorizedIssuers[cert.subjectId] = cert;
          store.issuerOrgBySubject[cert.subjectId] = cert.issuerId;
        }
      }
    }
    final certs = json['externalCerts'];
    if (certs is List) {
      for (final c in certs) {
        if (c is Map) {
          final cert = MeshCertificate.fromJson(Map<String, Object?>.from(c));
          store.externalCerts[cert.subjectId] = cert;
          // Prefer org mapping via delegated issuer when present.
          final viaIssuer = store.issuerOrgBySubject[cert.issuerId];
          store.externalOrgBySubject[cert.subjectId] =
              viaIssuer ?? cert.issuerId;
        }
      }
    }
    return store;
  }
}

import 'dart:convert';

import 'package:core/core.dart';

import 'ca.dart';
import 'certificate.dart';
import 'organization.dart';

/// Capability on a [MeshCertificate] that authorizes the subject to issue
/// member certificates under the issuing organization root.
const String orgIssueCapability = 'org_issue';

/// Default capabilities for ordinary org members.
const List<String> orgMemberCapabilities = ['mesh', 'chat'];

/// Capabilities granted to delegated issuers (member access + issue right).
const List<String> orgIssuerCapabilities = [
  'mesh',
  'chat',
  orgIssueCapability,
];

/// Grant from an org root CA allowing a device to issue member certs.
///
/// Wire: `zvcomm:issuer:v1:<base64url(json)>` for QR / clipboard / NFC.
final class IssuerAuthority {
  static const int version = 1;
  static const String qrScheme = 'zvcomm';
  static const String qrPath = 'issuer';

  /// Public organization trust root (same as [Organization] QR).
  final Organization organization;

  /// Certificate issued by [organization] to the delegated issuer subject.
  /// Must include [orgIssueCapability].
  final MeshCertificate certificate;

  const IssuerAuthority({
    required this.organization,
    required this.certificate,
  });

  String get shortCode => ShortCode.fromSubjectId(certificate.subjectId);

  bool get grantsIssue => certificate.capabilities.contains(orgIssueCapability);

  /// Verify grant: org root signed cert, valid, and includes issue capability.
  Future<bool> verify() async {
    if (!grantsIssue) return false;
    if (certificate.issuerId != organization.id) return false;
    if (!certificate.isValidAt(DateTime.now().toUtc())) return false;
    return certificate.verifyEd25519(organization.ed25519PublicKey);
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'kind': 'issuer_authority',
        'org': organization.toJson(),
        'cert': certificate.toJson(),
      };

  factory IssuerAuthority.fromJson(Map<String, Object?> json) {
    final orgRaw = json['org'] ?? json['organization'];
    final certRaw = json['cert'] ?? json['certificate'];
    if (orgRaw is! Map || certRaw is! Map) {
      throw const FormatException('issuer authority missing org or cert');
    }
    return IssuerAuthority(
      organization: Organization.fromJson(Map<String, Object?>.from(orgRaw)),
      certificate: MeshCertificate.fromJson(Map<String, Object?>.from(certRaw)),
    );
  }

  String toQrPayload() {
    final body = base64Url.encode(utf8.encode(jsonEncode(toJson())));
    return '$qrScheme:$qrPath:v$version:$body';
  }

  static IssuerAuthority parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('empty issuer authority payload');
    }

    Map<String, Object?> mapFromB64(String b64) => Map<String, Object?>.from(
          jsonDecode(utf8.decode(base64Url.decode(b64))) as Map,
        );

    final prefix = '$qrScheme:$qrPath:v$version:';
    if (input.toLowerCase().startsWith(prefix)) {
      return IssuerAuthority.fromJson(
          mapFromB64(input.substring(prefix.length)));
    }
    if (input.toLowerCase().startsWith('zvcomm:issuer:')) {
      final parts = input.split(':');
      if (parts.length >= 4) {
        return IssuerAuthority.fromJson(mapFromB64(parts.sublist(3).join(':')));
      }
    }
    if (input.startsWith('{')) {
      return IssuerAuthority.fromJson(
        Map<String, Object?>.from(jsonDecode(input) as Map),
      );
    }
    throw const FormatException(
      'unrecognized issuer authority (expect zvcomm:issuer:v1:… or JSON)',
    );
  }
}

/// Shareable member certificate package (includes chain for delegated issuers).
final class OrgMemberPackage {
  final MeshCertificate certificate;

  /// Present when [certificate] was signed by a delegated issuer (not root).
  final MeshCertificate? issuerAuthority;

  /// Optional org root for bootstrap trust.
  final Organization? organization;

  const OrgMemberPackage({
    required this.certificate,
    this.issuerAuthority,
    this.organization,
  });

  Map<String, Object?> toJson() => {
        'v': 1,
        'kind': 'org_member',
        'cert': certificate.toJson(),
        if (issuerAuthority != null)
          'issuerAuthority': issuerAuthority!.toJson(),
        if (organization != null) 'org': organization!.toJson(),
      };

  String toJsonString() => const JsonEncoder.withIndent('  ').convert(toJson());

  factory OrgMemberPackage.fromJson(Map<String, Object?> json) {
    final certRaw = json['cert'] ?? json['certificate'];
    if (certRaw is! Map) {
      // Bare MeshCertificate JSON (root-issued).
      return OrgMemberPackage(
        certificate: MeshCertificate.fromJson(json),
      );
    }
    MeshCertificate? auth;
    final authRaw = json['issuerAuthority'] ?? json['authority'];
    if (authRaw is Map) {
      auth = MeshCertificate.fromJson(Map<String, Object?>.from(authRaw));
    }
    Organization? org;
    final orgRaw = json['org'] ?? json['organization'];
    if (orgRaw is Map) {
      org = Organization.fromJson(Map<String, Object?>.from(orgRaw));
    }
    return OrgMemberPackage(
      certificate: MeshCertificate.fromJson(Map<String, Object?>.from(certRaw)),
      issuerAuthority: auth,
      organization: org,
    );
  }

  static OrgMemberPackage parse(String raw) {
    final text = raw.trim();
    if (!text.startsWith('{')) {
      throw const FormatException('org member package JSON required');
    }
    return OrgMemberPackage.fromJson(
      Map<String, Object?>.from(jsonDecode(text) as Map),
    );
  }
}

/// Helpers for org root CAs that grant issuer authority.
extension LocalCaIssuerGrant on LocalCa {
  /// Issue an [org_issue] certificate for [subject] (device or peer keys).
  Future<MeshCertificate> issueIssuerFor(
    DeviceIdentity subject, {
    Duration? ttl,
  }) {
    return issueFor(
      subject,
      ttl: ttl ?? const Duration(days: 365),
      capabilities: orgIssuerCapabilities,
    );
  }
}

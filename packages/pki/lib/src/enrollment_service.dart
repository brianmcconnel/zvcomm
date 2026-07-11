import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

import 'ca.dart';
import 'certificate.dart';

/// High-level enrollment helper (CA side + device side).
final class EnrollmentService {
  final LocalCa ca;

  EnrollmentService(this.ca);

  /// Device builds a signed enrollment request (for NFC/QR/BLE bootstrap).
  static Future<EnrollmentRequest> createRequest(DeviceIdentity device) =>
      EnrollmentRequest.create(device);

  /// CA issues a certificate after verifying the request.
  Future<EnrollmentResponse> processRequest(
    EnrollmentRequest request, {
    Duration? ttl,
  }) async {
    final cert = await ca.issueEnrollment(request, ttl: ttl);
    final certJson = cert.toJsonString();
    final sig = await ca.root.sign(
      Uint8List.fromList(utf8.encode(certJson)),
    );
    return EnrollmentResponse(
      subjectId: cert.subjectId,
      certificateJson: certJson,
      caSignature: sig,
    );
  }

  /// Device verifies CA signature over the certificate JSON using CA public key.
  static Future<MeshCertificate?> acceptResponse(
    EnrollmentResponse response, {
    required DeviceIdentity caPublic,
  }) async {
    final ok = await caPublic.verify(
      Uint8List.fromList(utf8.encode(response.certificateJson)),
      response.caSignature,
    );
    if (!ok) return null;
    final cert = MeshCertificate.fromJsonString(response.certificateJson);
    if (cert.subjectId != response.subjectId) return null;
    return cert;
  }
}

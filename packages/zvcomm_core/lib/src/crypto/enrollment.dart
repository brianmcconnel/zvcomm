import 'dart:convert';
import 'dart:typed_data';

import 'identity.dart';

/// Bootstrap / enrollment request (NFC, QR, BLE advertisement).
final class EnrollmentRequest {
  final String subjectId;
  final String displayName;
  final Uint8List ed25519PublicKey;
  final Uint8List x25519PublicKey;
  final Uint8List nonce;
  final Uint8List signature;

  const EnrollmentRequest({
    required this.subjectId,
    required this.displayName,
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
    required this.nonce,
    required this.signature,
  });

  static Future<EnrollmentRequest> create(
    DeviceIdentity identity, {
    Uint8List? nonce,
  }) async {
    final n = nonce ??
        Uint8List.fromList(
          List<int>.generate(16, (i) => (i * 17 + 3) & 0xff),
        );
    final tbs = _tbs(
      subjectId: identity.id,
      displayName: identity.displayName,
      ed25519PublicKey: identity.ed25519PublicKey,
      x25519PublicKey: identity.x25519PublicKey,
      nonce: n,
    );
    final sig = await identity.sign(tbs);
    return EnrollmentRequest(
      subjectId: identity.id,
      displayName: identity.displayName,
      ed25519PublicKey: identity.ed25519PublicKey,
      x25519PublicKey: identity.x25519PublicKey,
      nonce: n,
      signature: sig,
    );
  }

  Future<bool> verifySelf() async {
    final tbs = _tbs(
      subjectId: subjectId,
      displayName: displayName,
      ed25519PublicKey: ed25519PublicKey,
      x25519PublicKey: x25519PublicKey,
      nonce: nonce,
    );
    final temp = DeviceIdentity(
      id: subjectId,
      displayName: displayName,
      x25519PublicKey: x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    return temp.verify(tbs, signature);
  }

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'displayName': displayName,
        'ed25519PublicKey': base64Url.encode(ed25519PublicKey),
        'x25519PublicKey': base64Url.encode(x25519PublicKey),
        'nonce': base64Url.encode(nonce),
        'signature': base64Url.encode(signature),
      };

  factory EnrollmentRequest.fromJson(Map<String, Object?> json) {
    return EnrollmentRequest(
      subjectId: json['subjectId']! as String,
      displayName: json['displayName'] as String? ?? '',
      ed25519PublicKey: Uint8List.fromList(
        base64Url.decode(json['ed25519PublicKey']! as String),
      ),
      x25519PublicKey: Uint8List.fromList(
        base64Url.decode(json['x25519PublicKey']! as String),
      ),
      nonce: Uint8List.fromList(base64Url.decode(json['nonce']! as String)),
      signature:
          Uint8List.fromList(base64Url.decode(json['signature']! as String)),
    );
  }

  Uint8List toBytes() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory EnrollmentRequest.fromBytes(Uint8List bytes) =>
      EnrollmentRequest.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
      );

  static Uint8List _tbs({
    required String subjectId,
    required String displayName,
    required Uint8List ed25519PublicKey,
    required Uint8List x25519PublicKey,
    required Uint8List nonce,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'subjectId': subjectId,
          'displayName': displayName,
          'ed25519PublicKey': base64Url.encode(ed25519PublicKey),
          'x25519PublicKey': base64Url.encode(x25519PublicKey),
          'nonce': base64Url.encode(nonce),
        }),
      ),
    );
  }
}

/// CA response carrying an issued certificate JSON blob.
final class EnrollmentResponse {
  final String subjectId;
  final String certificateJson;
  final Uint8List caSignature;

  const EnrollmentResponse({
    required this.subjectId,
    required this.certificateJson,
    required this.caSignature,
  });

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        'certificateJson': certificateJson,
        'caSignature': base64Url.encode(caSignature),
      };

  factory EnrollmentResponse.fromJson(Map<String, Object?> json) {
    return EnrollmentResponse(
      subjectId: json['subjectId']! as String,
      certificateJson: json['certificateJson']! as String,
      caSignature: Uint8List.fromList(
        base64Url.decode(json['caSignature']! as String),
      ),
    );
  }

  Uint8List toBytes() =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  factory EnrollmentResponse.fromBytes(Uint8List bytes) =>
      EnrollmentResponse.fromJson(
        Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map),
      );
}

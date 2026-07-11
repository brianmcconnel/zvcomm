import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';

/// In-memory set of revoked subject ids (gossiped as short CRLs).
final class RevocationList {
  final Map<String, String> _revoked = {}; // id -> reason
  DateTime updatedAt = DateTime.now().toUtc();

  RevocationList();

  bool isRevoked(String subjectId) => _revoked.containsKey(subjectId);

  void revoke(String subjectId, {String reason = 'unspecified'}) {
    _revoked[subjectId] = reason;
    updatedAt = DateTime.now().toUtc();
  }

  Map<String, String> get entries => Map.unmodifiable(_revoked);

  Map<String, Object?> toJson() => {
        'updatedAt': updatedAt.toIso8601String(),
        'revoked': _revoked,
      };

  factory RevocationList.fromJson(Map<String, Object?> json) {
    final list = RevocationList();
    list.updatedAt = DateTime.parse(json['updatedAt']! as String);
    final map = json['revoked'] as Map<String, dynamic>? ?? {};
    map.forEach((k, v) => list._revoked[k] = v.toString());
    return list;
  }
}

/// CA-signed snapshot for mesh PKI gossip (`MessageKind.pki`).
final class SignedRevocationList {
  final RevocationList list;
  final String issuerId;
  final Uint8List signature;

  const SignedRevocationList({
    required this.list,
    required this.issuerId,
    required this.signature,
  });

  static Future<SignedRevocationList> sign(
    RevocationList list,
    DeviceIdentity ca,
  ) async {
    final tbs = Uint8List.fromList(utf8.encode(jsonEncode(list.toJson())));
    final sig = await ca.sign(tbs);
    return SignedRevocationList(
      list: list,
      issuerId: ca.id,
      signature: sig,
    );
  }

  Future<bool> verify(DeviceIdentity caPublic) async {
    if (issuerId != caPublic.id) return false;
    final tbs = Uint8List.fromList(utf8.encode(jsonEncode(list.toJson())));
    return caPublic.verify(tbs, signature);
  }

  Map<String, Object?> toJson() => {
        'issuerId': issuerId,
        'list': list.toJson(),
        'signature': base64Url.encode(signature),
      };

  factory SignedRevocationList.fromJson(Map<String, Object?> json) {
    return SignedRevocationList(
      issuerId: json['issuerId']! as String,
      list: RevocationList.fromJson(
        Map<String, Object?>.from(json['list'] as Map),
      ),
      signature:
          Uint8List.fromList(base64Url.decode(json['signature']! as String)),
    );
  }
}

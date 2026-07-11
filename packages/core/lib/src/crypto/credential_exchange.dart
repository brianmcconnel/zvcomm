import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;

import 'identity.dart';

/// Human-friendly short code alphabet (Crockford Base32, no I/L/O/U).
const String kShortCodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Public credential for QR / short-code exchange (no private keys).
///
/// Self-signed under the device's Ed25519 key so the peer can verify integrity
/// before adding the contact to their trust store.
final class PublicCredential {
  static const int version = 1;
  static const String qrScheme = 'zvcomm';
  static const String qrPath = 'cred';

  final String subjectId;
  final String displayName;
  final Uint8List ed25519PublicKey;
  final Uint8List x25519PublicKey;
  final int issuedAtMs;
  final Uint8List signature;

  const PublicCredential({
    required this.subjectId,
    required this.displayName,
    required this.ed25519PublicKey,
    required this.x25519PublicKey,
    required this.issuedAtMs,
    required this.signature,
  });

  /// Typable short code derived from the subject fingerprint (`XXXX-XXXX`).
  String get shortCode => ShortCode.fromSubjectId(subjectId);

  DateTime get issuedAt =>
      DateTime.fromMillisecondsSinceEpoch(issuedAtMs, isUtc: true);

  /// Build a self-signed public credential from a local identity.
  static Future<PublicCredential> fromIdentity(
    DeviceIdentity identity, {
    DateTime? issuedAt,
  }) async {
    final issuedAtMs =
        (issuedAt ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    final tbs = _tbs(
      subjectId: identity.id,
      displayName: identity.displayName,
      ed25519PublicKey: identity.ed25519PublicKey,
      x25519PublicKey: identity.x25519PublicKey,
      issuedAtMs: issuedAtMs,
    );
    final sig = await identity.sign(tbs);
    return PublicCredential(
      subjectId: identity.id,
      displayName: identity.displayName,
      ed25519PublicKey: identity.ed25519PublicKey,
      x25519PublicKey: identity.x25519PublicKey,
      issuedAtMs: issuedAtMs,
      signature: sig,
    );
  }

  /// Verify self-signature over the public material.
  Future<bool> verify() async {
    final tbs = _tbs(
      subjectId: subjectId,
      displayName: displayName,
      ed25519PublicKey: ed25519PublicKey,
      x25519PublicKey: x25519PublicKey,
      issuedAtMs: issuedAtMs,
    );
    final probe = DeviceIdentity(
      id: subjectId,
      displayName: displayName,
      x25519PublicKey: x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    return probe.verify(tbs, signature);
  }

  Map<String, Object?> toJson() => {
        'v': version,
        'i': subjectId,
        'n': displayName,
        'e': base64Url.encode(ed25519PublicKey),
        'x': base64Url.encode(x25519PublicKey),
        't': issuedAtMs,
        's': base64Url.encode(signature),
      };

  factory PublicCredential.fromJson(Map<String, Object?> json) {
    // Support compact keys and verbose EnrollmentRequest-ish keys.
    final subjectId = (json['i'] ?? json['subjectId']) as String?;
    final ed = (json['e'] ?? json['ed25519PublicKey']) as String?;
    final x = (json['x'] ?? json['x25519PublicKey']) as String?;
    final sig = (json['s'] ?? json['signature']) as String?;
    if (subjectId == null || ed == null || x == null || sig == null) {
      throw const FormatException('credential missing required fields');
    }
    final issued = json['t'] ?? json['issuedAtMs'];
    final nameRaw = json['n'] ?? json['displayName'];
    return PublicCredential(
      subjectId: subjectId,
      displayName: nameRaw is String ? nameRaw : '',
      ed25519PublicKey: Uint8List.fromList(base64Url.decode(ed)),
      x25519PublicKey: Uint8List.fromList(base64Url.decode(x)),
      issuedAtMs: issued is int
          ? issued
          : DateTime.now().toUtc().millisecondsSinceEpoch,
      signature: Uint8List.fromList(base64Url.decode(sig)),
    );
  }

  /// Compact QR / clipboard payload: `zvcomm:cred:v1:<base64url(json)>`.
  String toQrPayload() {
    final body = base64Url.encode(utf8.encode(jsonEncode(toJson())));
    return '$qrScheme:$qrPath:v$version:$body';
  }

  /// Parse QR payload, URI, JSON, or bare base64url JSON body.
  static PublicCredential parse(String raw) {
    final input = raw.trim();
    if (input.isEmpty) {
      throw const FormatException('empty credential');
    }

    Map<String, Object?> mapFromB64(String b64) {
      return Map<String, Object?>.from(
        jsonDecode(utf8.decode(base64Url.decode(b64))) as Map,
      );
    }

    // Full scheme form.
    final schemePrefix = '$qrScheme:$qrPath:v$version:';
    if (input.toLowerCase().startsWith(schemePrefix)) {
      final b64 = input.substring(schemePrefix.length);
      return PublicCredential.fromJson(mapFromB64(b64));
    }

    // Case-insensitive scheme variants.
    if (input.toLowerCase().startsWith('zvcomm:cred:')) {
      final parts = input.split(':');
      // zvcomm : cred : v1 : body
      if (parts.length >= 4) {
        final body = parts.sublist(3).join(':');
        return PublicCredential.fromJson(mapFromB64(body));
      }
    }

    // Raw JSON object.
    if (input.startsWith('{')) {
      return PublicCredential.fromJson(
        Map<String, Object?>.from(jsonDecode(input) as Map),
      );
    }

    // Bare base64url JSON.
    try {
      final decoded = utf8.decode(base64Url.decode(input));
      if (decoded.startsWith('{')) {
        return PublicCredential.fromJson(
          Map<String, Object?>.from(jsonDecode(decoded) as Map),
        );
      }
    } catch (_) {
      // fall through
    }

    throw const FormatException(
      'unrecognized credential payload (expect zvcomm:cred:v1:… or JSON)',
    );
  }

  static Uint8List _tbs({
    required String subjectId,
    required String displayName,
    required Uint8List ed25519PublicKey,
    required Uint8List x25519PublicKey,
    required int issuedAtMs,
  }) {
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'v': version,
          'i': subjectId,
          'n': displayName,
          'e': base64Url.encode(ed25519PublicKey),
          'x': base64Url.encode(x25519PublicKey),
          't': issuedAtMs,
        }),
      ),
    );
  }
}

/// Short codes for verbal / typed credential matching.
abstract final class ShortCode {
  /// 8 Crockford characters as `XXXX-XXXX` from subject id fingerprint.
  static String fromSubjectId(String subjectId) {
    final hex = subjectId.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    final bytes = <int>[];
    for (var i = 0; i + 1 < hex.length && bytes.length < 5; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    while (bytes.length < 5) {
      bytes.add(0);
    }
    // Mix with full id hash so non-hex ids still work.
    final digest = crypto_pkg.sha256.convert(utf8.encode(subjectId)).bytes;
    for (var i = 0; i < 5; i++) {
      bytes[i] ^= digest[i];
    }
    final encoded =
        _encodeCrockford(Uint8List.fromList(bytes.take(5).toList()));
    // 8 chars from 40 bits.
    final code = encoded.padRight(8, '0').substring(0, 8);
    return '${code.substring(0, 4)}-${code.substring(4, 8)}';
  }

  static String normalize(String raw) {
    final cleaned = raw
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-_]'), '')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1');
    return cleaned;
  }

  static bool matches(String code, String subjectId) {
    final a = normalize(code);
    final b = normalize(fromSubjectId(subjectId));
    return a == b;
  }

  /// Encode bytes to Crockford Base32 (no padding).
  static String _encodeCrockford(Uint8List data) {
    var buffer = 0;
    var bitsLeft = 0;
    final out = StringBuffer();
    for (final b in data) {
      buffer = (buffer << 8) | b;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        final index = (buffer >> (bitsLeft - 5)) & 0x1f;
        bitsLeft -= 5;
        out.write(kShortCodeAlphabet[index]);
      }
    }
    if (bitsLeft > 0) {
      final index = (buffer << (5 - bitsLeft)) & 0x1f;
      out.write(kShortCodeAlphabet[index]);
    }
    return out.toString();
  }
}

/// In-memory TTL cache of credential offers (mesh broadcast or local share).
final class CredentialOfferCache {
  final Map<String, _CachedCred> _byCode = {};
  final Map<String, _CachedCred> _bySubject = {};

  Duration defaultTtl;

  CredentialOfferCache({this.defaultTtl = const Duration(minutes: 15)});

  void put(PublicCredential cred, {Duration? ttl}) {
    final entry = _CachedCred(
      cred,
      DateTime.now().toUtc().add(ttl ?? defaultTtl),
    );
    _byCode[ShortCode.normalize(cred.shortCode)] = entry;
    _bySubject[cred.subjectId] = entry;
  }

  PublicCredential? byShortCode(String code) {
    _purge();
    return _byCode[ShortCode.normalize(code)]?.cred;
  }

  PublicCredential? bySubjectId(String id) {
    _purge();
    return _bySubject[id]?.cred;
  }

  List<PublicCredential> get all {
    _purge();
    return _bySubject.values.map((e) => e.cred).toList(growable: false);
  }

  void remove(String subjectId) {
    final e = _bySubject.remove(subjectId);
    if (e != null) {
      _byCode.remove(ShortCode.normalize(e.cred.shortCode));
    }
  }

  void clear() {
    _byCode.clear();
    _bySubject.clear();
  }

  void _purge() {
    final now = DateTime.now().toUtc();
    final expired = <String>[];
    _bySubject.forEach((id, e) {
      if (e.expiresAt.isBefore(now)) expired.add(id);
    });
    for (final id in expired) {
      remove(id);
    }
  }
}

final class _CachedCred {
  final PublicCredential cred;
  final DateTime expiresAt;
  _CachedCred(this.cred, this.expiresAt);
}

/// Mesh control payload for credential offers (type is in the body — wire
/// [MeshPacket] does not carry app headers).
abstract final class CredentialWire {
  static const typeKey = 'type';
  static const offerType = 'cred_offer';
  static const headerKey = 'cred'; // local MeshMessage only
  static const headerOffer = 'offer';

  static Uint8List encodeOffer(PublicCredential cred) {
    final body = {
      typeKey: offerType,
      'cred': cred.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  static PublicCredential? tryDecodeOffer(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      if (map[typeKey] != offerType) return null;
      final credRaw = map['cred'];
      if (credRaw is! Map) return null;
      return PublicCredential.fromJson(Map<String, Object?>.from(credRaw));
    } catch (_) {
      return null;
    }
  }
}

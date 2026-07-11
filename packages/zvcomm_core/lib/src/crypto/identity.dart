import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto_pkg;
import 'package:cryptography/cryptography.dart';

/// Device identity with X25519 (DH) + Ed25519 (sign) key material.
///
/// [id] is a stable fingerprint of the Ed25519 public key (first 8 bytes hex).
final class DeviceIdentity {
  /// Stable device id (routing / PKI subject).
  final String id;

  /// Optional display name.
  final String displayName;

  /// X25519 public key (32 bytes).
  final Uint8List x25519PublicKey;

  /// X25519 private seed (32 bytes) — protect in secure storage.
  final Uint8List x25519PrivateKey;

  /// Ed25519 public key (32 bytes).
  final Uint8List ed25519PublicKey;

  /// Ed25519 private seed (32 bytes) — protect in secure storage.
  final Uint8List ed25519PrivateKey;

  const DeviceIdentity({
    required this.id,
    this.displayName = '',
    required this.x25519PublicKey,
    required this.x25519PrivateKey,
    required this.ed25519PublicKey,
    required this.ed25519PrivateKey,
  });

  /// Back-compat alias used by older PKI code paths.
  Uint8List get publicKeyBytes => ed25519PublicKey;

  /// Back-compat alias (Ed25519 seed). Prefer typed fields for new code.
  Uint8List get privateKeyBytes => ed25519PrivateKey;

  /// Generate a fresh identity.
  static Future<DeviceIdentity> generate({
    String displayName = '',
    Random? random,
  }) async {
    final seed = _randomBytes(32, random);
    return fromSeedBytes(seed, displayName: displayName);
  }

  /// Deterministic identity from a UTF-8 passphrase (tests / demos only).
  static Future<DeviceIdentity> fromSeed(
    String seed, {
    String displayName = '',
  }) {
    final bytes = Uint8List.fromList(
      crypto_pkg.sha256.convert(utf8.encode(seed)).bytes,
    );
    return fromSeedBytes(bytes, displayName: displayName);
  }

  /// Deterministic identity from 32-byte seed material.
  static Future<DeviceIdentity> fromSeedBytes(
    Uint8List seed32, {
    String displayName = '',
  }) async {
    if (seed32.length != 32) {
      throw ArgumentError('seed must be 32 bytes');
    }
    // Domain-separate X25519 / Ed25519 seeds.
    final xSeed = Uint8List.fromList(
      crypto_pkg.sha256.convert([...seed32, ...utf8.encode('x25519')]).bytes,
    );
    final eSeed = Uint8List.fromList(
      crypto_pkg.sha256.convert([...seed32, ...utf8.encode('ed25519')]).bytes,
    );

    final x25519 = X25519();
    final ed25519 = Ed25519();
    final xPair = await x25519.newKeyPairFromSeed(xSeed);
    final ePair = await ed25519.newKeyPairFromSeed(eSeed);

    final xPub = await xPair.extractPublicKey();
    final ePub = await ePair.extractPublicKey();
    final xPriv = await xPair.extractPrivateKeyBytes();
    final ePriv = await ePair.extractPrivateKeyBytes();

    final id = crypto_pkg.sha256
        .convert(ePub.bytes)
        .bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return DeviceIdentity(
      id: id,
      displayName: displayName,
      x25519PublicKey: Uint8List.fromList(xPub.bytes),
      x25519PrivateKey: Uint8List.fromList(xPriv),
      ed25519PublicKey: Uint8List.fromList(ePub.bytes),
      ed25519PrivateKey: Uint8List.fromList(ePriv),
    );
  }

  /// Synchronous factory for call sites that cannot be async yet.
  ///
  /// Uses a blocking-style pattern only in tests: prefer [generate]/[fromSeed].
  @Deprecated('Use DeviceIdentity.generate / fromSeed (async)')
  factory DeviceIdentity.generateSync({
    String displayName = '',
    Random? random,
  }) {
    // Legacy fallback: hash-based keys (not X25519). Prefer async factories.
    final rng = random ?? Random.secure();
    final private = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final public = Uint8List.fromList(
      crypto_pkg.sha256.convert(private).bytes,
    );
    final id = crypto_pkg.sha256
        .convert(public)
        .bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return DeviceIdentity(
      id: id,
      displayName: displayName,
      x25519PublicKey: public,
      x25519PrivateKey: private,
      ed25519PublicKey: public,
      ed25519PrivateKey: private,
    );
  }

  @Deprecated('Use DeviceIdentity.fromSeed (async)')
  factory DeviceIdentity.fromSeedSync(String seed, {String displayName = ''}) {
    final private =
        Uint8List.fromList(crypto_pkg.sha256.convert(utf8.encode(seed)).bytes);
    final public = Uint8List.fromList(
      crypto_pkg.sha256.convert([...private, ...utf8.encode('pub')]).bytes,
    );
    final id = crypto_pkg.sha256
        .convert(public)
        .bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return DeviceIdentity(
      id: id,
      displayName: displayName,
      x25519PublicKey: public,
      x25519PrivateKey: private,
      ed25519PublicKey: public,
      ed25519PrivateKey: private,
    );
  }

  Future<SimpleKeyPair> x25519KeyPair() =>
      X25519().newKeyPairFromSeed(x25519PrivateKey);

  Future<SimpleKeyPair> ed25519KeyPair() =>
      Ed25519().newKeyPairFromSeed(ed25519PrivateKey);

  SimplePublicKey get x25519Public =>
      SimplePublicKey(x25519PublicKey, type: KeyPairType.x25519);

  SimplePublicKey get ed25519Public =>
      SimplePublicKey(ed25519PublicKey, type: KeyPairType.ed25519);

  /// Sign [message] with Ed25519.
  Future<Uint8List> sign(Uint8List message) async {
    final sig = await Ed25519().sign(
      message,
      keyPair: await ed25519KeyPair(),
    );
    return Uint8List.fromList(sig.bytes);
  }

  /// Verify Ed25519 signature under this identity's public key.
  Future<bool> verify(Uint8List message, Uint8List signatureBytes) async {
    return Ed25519().verify(
      message,
      signature: Signature(
        signatureBytes,
        publicKey: ed25519Public,
      ),
    );
  }

  Map<String, String> get advertisementMetadata => {
        'id': id,
        if (displayName.isNotEmpty) 'name': displayName,
      };

  Map<String, Object?> toJson({bool includePrivate = false}) => {
        'id': id,
        'displayName': displayName,
        'x25519PublicKey': base64Url.encode(x25519PublicKey),
        'ed25519PublicKey': base64Url.encode(ed25519PublicKey),
        if (includePrivate) ...{
          'x25519PrivateKey': base64Url.encode(x25519PrivateKey),
          'ed25519PrivateKey': base64Url.encode(ed25519PrivateKey),
        },
      };

  factory DeviceIdentity.fromJson(Map<String, Object?> json) {
    Uint8List req(String k) =>
        Uint8List.fromList(base64Url.decode(json[k]! as String));
    return DeviceIdentity(
      id: json['id']! as String,
      displayName: json['displayName'] as String? ?? '',
      x25519PublicKey: req('x25519PublicKey'),
      x25519PrivateKey: json.containsKey('x25519PrivateKey')
          ? req('x25519PrivateKey')
          : Uint8List(32),
      ed25519PublicKey: req('ed25519PublicKey'),
      ed25519PrivateKey: json.containsKey('ed25519PrivateKey')
          ? req('ed25519PrivateKey')
          : Uint8List(32),
    );
  }

  static Uint8List _randomBytes(int n, Random? random) {
    final rng = random ?? Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }
}

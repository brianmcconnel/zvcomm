import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Local device identity placeholder (Phase 0).
///
/// Phase 3 will replace the random seed with proper key pairs (Noise / PKI).
/// This type still provides a stable [id] for mesh routing and discovery.
final class DeviceIdentity {
  /// Stable device id derived from the public material fingerprint.
  final String id;

  /// Optional display name.
  final String displayName;

  /// Raw public key bytes (placeholder seed hash in Phase 0).
  final Uint8List publicKeyBytes;

  /// Raw private material — keep in secure storage only (Phase 3).
  final Uint8List privateKeyBytes;

  const DeviceIdentity({
    required this.id,
    this.displayName = '',
    required this.publicKeyBytes,
    required this.privateKeyBytes,
  });

  /// Generate an ephemeral identity for demos and tests.
  factory DeviceIdentity.generate({
    String displayName = '',
    Random? random,
  }) {
    final rng = random ?? Random.secure();
    final private = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final public = Uint8List.fromList(sha256.convert(private).bytes);
    final id = sha256.convert(public).bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return DeviceIdentity(
      id: id,
      displayName: displayName,
      publicKeyBytes: public,
      privateKeyBytes: private,
    );
  }

  /// Deterministic identity from a passphrase (tests only — not for production).
  factory DeviceIdentity.fromSeed(String seed, {String displayName = ''}) {
    final private = Uint8List.fromList(sha256.convert(utf8.encode(seed)).bytes);
    final public = Uint8List.fromList(
      sha256.convert([...private, ...utf8.encode('pub')]).bytes,
    );
    final id = sha256
        .convert(public)
        .bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return DeviceIdentity(
      id: id,
      displayName: displayName,
      publicKeyBytes: public,
      privateKeyBytes: private,
    );
  }

  Map<String, String> get advertisementMetadata => {
        'id': id,
        if (displayName.isNotEmpty) 'name': displayName,
      };
}

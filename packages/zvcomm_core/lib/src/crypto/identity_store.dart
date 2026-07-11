import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'identity.dart';

/// Persisted identity + optional certificate blob.
final class StoredIdentity {
  final DeviceIdentity identity;
  final Uint8List? certificateBytes;
  final String? certificateJson;

  const StoredIdentity({
    required this.identity,
    this.certificateBytes,
    this.certificateJson,
  });
}

/// Pluggable secure identity storage.
abstract class IdentityStore {
  Future<void> save(StoredIdentity value);
  Future<StoredIdentity?> load();
  Future<void> clear();
}

/// In-memory store for tests.
final class MemoryIdentityStore implements IdentityStore {
  StoredIdentity? _value;

  @override
  Future<void> save(StoredIdentity value) async => _value = value;

  @override
  Future<StoredIdentity?> load() async => _value;

  @override
  Future<void> clear() async => _value = null;
}

/// File-backed store (CLI / desktop). Protect the file with OS permissions.
///
/// Mobile apps should prefer platform keystores via a Flutter implementation.
final class FileIdentityStore implements IdentityStore {
  final File file;

  FileIdentityStore(this.file);

  factory FileIdentityStore.path(String path) =>
      FileIdentityStore(File(path));

  @override
  Future<void> save(StoredIdentity value) async {
    final map = {
      'identity': value.identity.toJson(includePrivate: true),
      if (value.certificateJson != null) 'certificateJson': value.certificateJson,
      if (value.certificateBytes != null)
        'certificateBytes': base64Url.encode(value.certificateBytes!),
    };
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }

  @override
  Future<StoredIdentity?> load() async {
    if (!await file.exists()) return null;
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final identity = DeviceIdentity.fromJson(
      Map<String, Object?>.from(map['identity'] as Map),
    );
    return StoredIdentity(
      identity: identity,
      certificateJson: map['certificateJson'] as String?,
      certificateBytes: map['certificateBytes'] is String
          ? Uint8List.fromList(
              base64Url.decode(map['certificateBytes'] as String),
            )
          : null,
    );
  }

  @override
  Future<void> clear() async {
    if (await file.exists()) {
      await file.delete();
    }
  }
}

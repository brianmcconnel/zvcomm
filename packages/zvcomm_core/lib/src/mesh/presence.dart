import 'dart:convert';
import 'dart:typed_data';

/// Snapshot of a peer's liveness advertisement.
final class PresenceInfo {
  final String peerId;
  final String displayName;
  final DateTime lastSeen;
  final int sequence;
  final Map<String, String> metadata;

  const PresenceInfo({
    required this.peerId,
    this.displayName = '',
    required this.lastSeen,
    this.sequence = 0,
    this.metadata = const {},
  });

  PresenceInfo copyWith({
    String? displayName,
    DateTime? lastSeen,
    int? sequence,
    Map<String, String>? metadata,
  }) =>
      PresenceInfo(
        peerId: peerId,
        displayName: displayName ?? this.displayName,
        lastSeen: lastSeen ?? this.lastSeen,
        sequence: sequence ?? this.sequence,
        metadata: metadata ?? this.metadata,
      );

  bool isFresh(Duration ttl, {DateTime? now}) {
    final n = now ?? DateTime.now().toUtc();
    return n.difference(lastSeen) <= ttl;
  }
}

/// Encode/decode presence payloads (UTF-8 JSON, compact).
final class PresenceCodec {
  static Uint8List encode({
    required String peerId,
    required String displayName,
    required int sequence,
    Map<String, String> metadata = const {},
  }) {
    final map = <String, Object?>{
      'id': peerId,
      'name': displayName,
      'seq': sequence,
      if (metadata.isNotEmpty) 'meta': metadata,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  static PresenceInfo? decode(Uint8List payload, {DateTime? seenAt}) {
    try {
      final map = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return PresenceInfo(
        peerId: map['id'] as String? ?? '',
        displayName: map['name'] as String? ?? '',
        lastSeen: seenAt ?? DateTime.now().toUtc(),
        sequence: map['seq'] as int? ?? 0,
        metadata: (map['meta'] as Map<String, dynamic>? ?? const {})
            .map((k, v) => MapEntry(k, v.toString())),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Tracks live peers from presence floods.
final class PresenceTable {
  final Duration ttl;
  final Map<String, PresenceInfo> _peers = {};

  PresenceTable({this.ttl = const Duration(seconds: 20)});

  Map<String, PresenceInfo> get all => Map.unmodifiable(_peers);

  List<PresenceInfo> get live {
    final now = DateTime.now().toUtc();
    return _peers.values.where((p) => p.isFresh(ttl, now: now)).toList();
  }

  /// Returns true if this is a new or updated presence (newer seq).
  bool observe(PresenceInfo info) {
    if (info.peerId.isEmpty) return false;
    final existing = _peers[info.peerId];
    if (existing != null && info.sequence < existing.sequence) {
      return false;
    }
    _peers[info.peerId] = info;
    return true;
  }

  void purgeExpired({DateTime? now}) {
    final n = now ?? DateTime.now().toUtc();
    _peers.removeWhere((_, p) => !p.isFresh(ttl, now: n));
  }

  void clear() => _peers.clear();
}

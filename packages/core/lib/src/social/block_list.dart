/// A locally blocked peer (messages and discovery UI are suppressed).
final class BlockEntry {
  final String subjectId;
  final String? displayName;
  final String? reason;
  final DateTime blockedAt;

  const BlockEntry({
    required this.subjectId,
    this.displayName,
    this.reason,
    required this.blockedAt,
  });

  Map<String, Object?> toJson() => {
        'subjectId': subjectId,
        if (displayName != null && displayName!.isNotEmpty)
          'displayName': displayName,
        if (reason != null && reason!.isNotEmpty) 'reason': reason,
        'blockedAt': blockedAt.toIso8601String(),
      };

  factory BlockEntry.fromJson(Map<String, Object?> json) => BlockEntry(
        subjectId: json['subjectId']! as String,
        displayName: json['displayName'] as String?,
        reason: json['reason'] as String?,
        blockedAt: json['blockedAt'] is String
            ? DateTime.parse(json['blockedAt']! as String)
            : DateTime.now().toUtc(),
      );
}

/// Local block list — does not leave the device unless the user exports it.
final class BlockList {
  BlockList();

  final Map<String, BlockEntry> _entries = {};

  int get length => _entries.length;

  List<BlockEntry> get entries {
    final list = _entries.values.toList()
      ..sort((a, b) => b.blockedAt.compareTo(a.blockedAt));
    return List.unmodifiable(list);
  }

  bool isBlocked(String subjectId) => _entries.containsKey(subjectId);

  void block(
    String subjectId, {
    String? displayName,
    String? reason,
  }) {
    if (subjectId.isEmpty) return;
    _entries[subjectId] = BlockEntry(
      subjectId: subjectId,
      displayName: displayName,
      reason: reason,
      blockedAt: DateTime.now().toUtc(),
    );
  }

  void unblock(String subjectId) => _entries.remove(subjectId);

  void clear() => _entries.clear();

  Map<String, Object?> toJson() => {
        'blocked': _entries.values.map((e) => e.toJson()).toList(),
      };

  factory BlockList.fromJson(Map<String, Object?> json) {
    final list = BlockList();
    final raw = json['blocked'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final entry = BlockEntry.fromJson(Map<String, Object?>.from(e));
          list._entries[entry.subjectId] = entry;
        }
      }
    }
    return list;
  }
}

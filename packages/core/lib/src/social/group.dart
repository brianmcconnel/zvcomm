import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// A multi-party chat group on the mesh (membership is app-layer; fan-out unicast).
final class MeshGroup {
  final String id;
  final String name;
  final String ownerId;
  final Set<String> memberIds;
  final Set<String> adminIds;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;

  MeshGroup({
    required this.id,
    required this.name,
    required this.ownerId,
    Set<String>? memberIds,
    Set<String>? adminIds,
    this.description,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : memberIds = {...?memberIds, ownerId},
        adminIds = {...?adminIds, ownerId},
        createdAt = createdAt ?? DateTime.now().toUtc(),
        updatedAt = updatedAt ?? DateTime.now().toUtc();

  int get memberCount => memberIds.length;

  bool isMember(String subjectId) => memberIds.contains(subjectId);

  bool isAdmin(String subjectId) => adminIds.contains(subjectId);

  bool isOwner(String subjectId) => ownerId == subjectId;

  MeshGroup copyWith({
    String? name,
    String? ownerId,
    Set<String>? memberIds,
    Set<String>? adminIds,
    String? description,
    DateTime? updatedAt,
    bool clearDescription = false,
  }) {
    return MeshGroup(
      id: id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      memberIds: memberIds ?? this.memberIds,
      adminIds: adminIds ?? this.adminIds,
      description: clearDescription ? null : (description ?? this.description),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'ownerId': ownerId,
        'memberIds': memberIds.toList()..sort(),
        'adminIds': adminIds.toList()..sort(),
        if (description != null && description!.isNotEmpty)
          'description': description,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MeshGroup.fromJson(Map<String, Object?> json) {
    Set<String> asSet(Object? raw) {
      if (raw is! List) return {};
      return raw.map((e) => e.toString()).toSet();
    }

    return MeshGroup(
      id: json['id']! as String,
      name: json['name'] as String? ?? 'Group',
      ownerId: json['ownerId']! as String,
      memberIds: asSet(json['memberIds']),
      adminIds: asSet(json['adminIds']),
      description: json['description'] as String?,
      createdAt: json['createdAt'] is String
          ? DateTime.parse(json['createdAt']! as String)
          : DateTime.now().toUtc(),
      updatedAt: json['updatedAt'] is String
          ? DateTime.parse(json['updatedAt']! as String)
          : DateTime.now().toUtc(),
    );
  }

  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final n = r.nextInt(0x7fffffff).toRadixString(16);
    return 'g-$t-$n';
  }
}

/// Local group catalog (created + invited).
final class GroupStore {
  GroupStore();

  final Map<String, MeshGroup> _groups = {};

  int get length => _groups.length;

  List<MeshGroup> get all {
    final list = _groups.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return List.unmodifiable(list);
  }

  MeshGroup? operator [](String id) => _groups[id];

  bool contains(String id) => _groups.containsKey(id);

  void put(MeshGroup group) => _groups[group.id] = group;

  void remove(String id) => _groups.remove(id);

  void clear() => _groups.clear();

  /// Create a new group owned by [ownerId].
  MeshGroup create({
    required String name,
    required String ownerId,
    Iterable<String> members = const [],
    String? description,
  }) {
    final group = MeshGroup(
      id: MeshGroup.newId(),
      name: name.trim().isEmpty ? 'Group' : name.trim(),
      ownerId: ownerId,
      memberIds: {ownerId, ...members},
      adminIds: {ownerId},
      description: description,
    );
    put(group);
    return group;
  }

  MeshGroup? addMember(String groupId, String memberId) {
    final g = _groups[groupId];
    if (g == null) return null;
    final next = g.copyWith(memberIds: {...g.memberIds, memberId});
    put(next);
    return next;
  }

  MeshGroup? removeMember(String groupId, String memberId) {
    final g = _groups[groupId];
    if (g == null) return null;
    if (memberId == g.ownerId) return g; // cannot remove owner this way
    final members = {...g.memberIds}..remove(memberId);
    final admins = {...g.adminIds}..remove(memberId);
    final next = g.copyWith(memberIds: members, adminIds: admins);
    put(next);
    return next;
  }

  MeshGroup? rename(String groupId, String name) {
    final g = _groups[groupId];
    if (g == null) return null;
    final next = g.copyWith(name: name.trim().isEmpty ? g.name : name.trim());
    put(next);
    return next;
  }

  Map<String, Object?> toJson() => {
        'groups': _groups.values.map((g) => g.toJson()).toList(),
      };

  factory GroupStore.fromJson(Map<String, Object?> json) {
    final store = GroupStore();
    final raw = json['groups'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final g = MeshGroup.fromJson(Map<String, Object?>.from(e));
          store.put(g);
        }
      }
    }
    return store;
  }
}

/// Control-plane group membership messages.
abstract final class GroupWire {
  static const typeKey = 'type';
  static const inviteType = 'group_invite';
  static const updateType = 'group_update';
  static const leaveType = 'group_leave';
  static const kickType = 'group_kick';

  static Uint8List encodeInvite(MeshGroup group, {String? note}) {
    return _encode(inviteType, {
      'group': group.toJson(),
      if (note != null && note.isNotEmpty) 'note': note,
    });
  }

  static Uint8List encodeUpdate(MeshGroup group) {
    return _encode(updateType, {'group': group.toJson()});
  }

  static Uint8List encodeLeave({
    required String groupId,
    required String memberId,
  }) {
    return _encode(leaveType, {'groupId': groupId, 'memberId': memberId});
  }

  static Uint8List encodeKick({
    required String groupId,
    required String memberId,
    required String byId,
  }) {
    return _encode(kickType, {
      'groupId': groupId,
      'memberId': memberId,
      'byId': byId,
    });
  }

  static Uint8List _encode(String type, Map<String, Object?> body) {
    return Uint8List.fromList(
      utf8.encode(jsonEncode({typeKey: type, ...body})),
    );
  }

  /// Returns a record describing the control action, or null if not group wire.
  static GroupWireEvent? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      final type = map[typeKey] as String?;
      switch (type) {
        case inviteType:
        case updateType:
          final raw = map['group'];
          if (raw is! Map) return null;
          return GroupWireEvent(
            type: type!,
            group: MeshGroup.fromJson(Map<String, Object?>.from(raw)),
            note: map['note'] as String?,
          );
        case leaveType:
          return GroupWireEvent(
            type: leaveType,
            groupId: map['groupId'] as String?,
            memberId: map['memberId'] as String?,
          );
        case kickType:
          return GroupWireEvent(
            type: kickType,
            groupId: map['groupId'] as String?,
            memberId: map['memberId'] as String?,
            byId: map['byId'] as String?,
          );
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

final class GroupWireEvent {
  final String type;
  final MeshGroup? group;
  final String? groupId;
  final String? memberId;
  final String? byId;
  final String? note;

  const GroupWireEvent({
    required this.type,
    this.group,
    this.groupId,
    this.memberId,
    this.byId,
    this.note,
  });
}

/// Structured group chat envelope (carried as [MessageKind.chat] UTF-8 JSON).
abstract final class GroupChatWire {
  static const kind = 'gchat';

  static String encode({required String groupId, required String text}) {
    return jsonEncode({
      'v': 1,
      'kind': kind,
      'gid': groupId,
      'text': text,
    });
  }

  /// Returns (groupId, text) if [raw] is a group chat envelope.
  static ({String groupId, String text})? tryParse(String raw) {
    final t = raw.trim();
    if (!t.startsWith('{')) return null;
    try {
      final map = jsonDecode(t) as Map<String, dynamic>;
      if (map['kind'] != kind) return null;
      final gid = map['gid'] as String?;
      final text = map['text'] as String?;
      if (gid == null || text == null) return null;
      return (groupId: gid, text: text);
    } catch (_) {
      return null;
    }
  }
}

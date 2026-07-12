import 'dart:convert';
import 'dart:typed_data';

/// How a young person's messaging is supervised.
///
/// Kept to two clear base modes parents understand:
/// - [teen]: transparent — parents (and optional teachers) can see messages
/// - [child]: mediated — outbound messages need a parent to approve first
///
/// Either mode can also be [WardProfile.grounded] / [MySafetyPolicy.grounded]
/// (no outbound chat or walkie until a parent lifts it).
///
/// Multiple parents (e.g. Mom and Dad) stay on the same page via co-parent
/// lists and [FamilySafetyWire.statusType] privilege sync.
enum SafetyMode {
  /// Open-ish: messages send immediately; guardians get a copy.
  teen,

  /// Mediated: outbound chat waits for a guardian to approve.
  child;

  String get label => switch (this) {
        SafetyMode.teen => 'Teen · transparent',
        SafetyMode.child => 'Kid · parent approves',
      };

  String get shortLabel => switch (this) {
        SafetyMode.teen => 'Teen',
        SafetyMode.child => 'Kid',
      };

  String get blurb => switch (this) {
        SafetyMode.teen =>
          'They can message freely. You (and shared teachers/leaders) can see it.',
        SafetyMode.child =>
          'Their messages wait for your OK before anyone else sees them.',
      };

  static SafetyMode parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'child' || s == 'kid' || s == 'mediated') return SafetyMode.child;
    return SafetyMode.teen;
  }
}

/// One supervised young person, as stored on a guardian device.
///
/// [parentIds] are co-guardians (Mom, Dad, …) who share the same privilege
/// status and can approve kid messages.
final class WardProfile {
  final String wardId;
  final String displayName;
  final SafetyMode mode;

  /// When true, outbound chat and walkie are blocked until a parent ungrounds.
  final bool grounded;

  /// Co-parents who share full privilege control (includes the parent who set up).
  final List<String> parentIds;
  final Map<String, String> parentNames;

  /// Teachers / coaches / leaders who share visibility (not approvers).
  final List<String> sharedWithIds;
  final Map<String, String> sharedWithNames;
  final DateTime createdAt;

  /// Last privilege change (mode / grounded / parents / share).
  final DateTime statusUpdatedAt;
  final String? statusById;
  final String? statusByName;

  const WardProfile({
    required this.wardId,
    required this.displayName,
    required this.mode,
    this.grounded = false,
    this.parentIds = const [],
    this.parentNames = const {},
    this.sharedWithIds = const [],
    this.sharedWithNames = const {},
    required this.createdAt,
    DateTime? statusUpdatedAt,
    this.statusById,
    this.statusByName,
  }) : statusUpdatedAt = statusUpdatedAt ?? createdAt;

  /// Human privilege line: "Teen", "Kid · Grounded", etc.
  String get privilegeLabel {
    if (grounded) return '${mode.shortLabel} · Grounded';
    return mode.shortLabel;
  }

  String get privilegeDetail {
    if (grounded) {
      return 'Messaging paused · base ${mode.shortLabel}';
    }
    return mode.blurb;
  }

  /// Parent names for UI (optional [selfId] → "You").
  String parentsLabel({String? selfId}) {
    if (parentIds.isEmpty) return 'Parents not set';
    final parts = <String>[];
    for (final id in parentIds) {
      if (selfId != null && id == selfId) {
        parts.add('You');
        continue;
      }
      final n = parentNames[id];
      if (n != null && n.isNotEmpty) {
        parts.add(n);
      } else if (id.length > 8) {
        parts.add('${id.substring(0, 8)}…');
      } else {
        parts.add(id);
      }
    }
    return parts.join(' · ');
  }

  WardProfile copyWith({
    String? displayName,
    SafetyMode? mode,
    bool? grounded,
    List<String>? parentIds,
    Map<String, String>? parentNames,
    List<String>? sharedWithIds,
    Map<String, String>? sharedWithNames,
    DateTime? statusUpdatedAt,
    String? statusById,
    String? statusByName,
    bool clearStatusBy = false,
  }) {
    return WardProfile(
      wardId: wardId,
      displayName: displayName ?? this.displayName,
      mode: mode ?? this.mode,
      grounded: grounded ?? this.grounded,
      parentIds: parentIds ?? this.parentIds,
      parentNames: parentNames ?? this.parentNames,
      sharedWithIds: sharedWithIds ?? this.sharedWithIds,
      sharedWithNames: sharedWithNames ?? this.sharedWithNames,
      createdAt: createdAt,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      statusById: clearStatusBy ? null : (statusById ?? this.statusById),
      statusByName: clearStatusBy ? null : (statusByName ?? this.statusByName),
    );
  }

  /// Stamp who last changed privilege status.
  WardProfile withStatusTouch({
    required String byId,
    required String byName,
    DateTime? at,
  }) {
    return copyWith(
      statusUpdatedAt: at ?? DateTime.now().toUtc(),
      statusById: byId,
      statusByName: byName,
    );
  }

  Map<String, Object?> toJson() => {
        'wardId': wardId,
        'displayName': displayName,
        'mode': mode.name,
        'grounded': grounded,
        'parentIds': parentIds,
        'parentNames': parentNames,
        'sharedWithIds': sharedWithIds,
        'sharedWithNames': sharedWithNames,
        'createdAt': createdAt.toIso8601String(),
        'statusUpdatedAt': statusUpdatedAt.toIso8601String(),
        if (statusById != null) 'statusById': statusById,
        if (statusByName != null) 'statusByName': statusByName,
      };

  factory WardProfile.fromJson(Map<String, Object?> json) {
    Map<String, String> mapFrom(Object? raw) {
      final out = <String, String>{};
      if (raw is Map) {
        raw.forEach((k, v) => out['$k'] = '$v');
      }
      return out;
    }

    List<String> listFrom(Object? raw) {
      if (raw is! List) return const [];
      return raw.map((e) => '$e').toList();
    }

    final created = json['createdAt'] is String
        ? DateTime.parse(json['createdAt']! as String)
        : DateTime.now().toUtc();
    final statusAt = json['statusUpdatedAt'] is String
        ? DateTime.parse(json['statusUpdatedAt']! as String)
        : created;

    // Backward compat: older payloads had no parentIds.
    var parentIds = listFrom(json['parentIds']);
    final parentNames = mapFrom(json['parentNames']);
    if (parentIds.isEmpty) {
      final gId = json['guardianId'] as String?;
      if (gId != null && gId.isNotEmpty) {
        parentIds = [gId];
        final gName = json['guardianName'] as String?;
        if (gName != null && gName.isNotEmpty) {
          parentNames[gId] = gName;
        }
      }
    }

    return WardProfile(
      wardId: json['wardId']! as String,
      displayName: json['displayName'] as String? ?? '',
      mode: SafetyMode.parse(json['mode'] as String?),
      grounded: json['grounded'] == true,
      parentIds: parentIds,
      parentNames: parentNames,
      sharedWithIds: listFrom(json['sharedWithIds']),
      sharedWithNames: mapFrom(json['sharedWithNames']),
      createdAt: created,
      statusUpdatedAt: statusAt,
      statusById: json['statusById'] as String?,
      statusByName: json['statusByName'] as String?,
    );
  }
}

/// Policy installed on a young person's device (set by parents).
final class MySafetyPolicy {
  /// Primary / last-touching parent (for short labels).
  final String guardianId;
  final String guardianName;

  /// All parents who can approve and receive copies (Mom, Dad, …).
  final List<String> parentIds;
  final Map<String, String> parentNames;

  final SafetyMode mode;

  /// When true, this device cannot send chat or walkie.
  final bool grounded;
  final List<String> sharedWithIds;
  final DateTime updatedAt;

  const MySafetyPolicy({
    required this.guardianId,
    required this.guardianName,
    this.parentIds = const [],
    this.parentNames = const {},
    required this.mode,
    this.grounded = false,
    this.sharedWithIds = const [],
    required this.updatedAt,
  });

  /// Every parent who should get mediate requests / teen copies.
  List<String> get allParentIds {
    final ids = <String>{...parentIds};
    if (guardianId.isNotEmpty) ids.add(guardianId);
    return ids.toList();
  }

  String get parentsLabel {
    if (parentIds.isEmpty) {
      return guardianName.isNotEmpty ? guardianName : guardianId;
    }
    final parts = <String>[];
    for (final id in parentIds) {
      final n = parentNames[id];
      parts.add(
        (n != null && n.isNotEmpty)
            ? n
            : (id.length > 8 ? '${id.substring(0, 8)}…' : id),
      );
    }
    return parts.join(' · ');
  }

  String get privilegeLabel {
    if (grounded) return '${mode.shortLabel} · Grounded';
    return mode.shortLabel;
  }

  Map<String, Object?> toJson() => {
        'guardianId': guardianId,
        'guardianName': guardianName,
        'parentIds': parentIds,
        'parentNames': parentNames,
        'mode': mode.name,
        'grounded': grounded,
        'sharedWithIds': sharedWithIds,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory MySafetyPolicy.fromJson(Map<String, Object?> json) {
    final ids = <String>[];
    final raw = json['sharedWithIds'];
    if (raw is List) ids.addAll(raw.map((e) => '$e'));

    final parentIds = <String>[];
    final rawParents = json['parentIds'];
    if (rawParents is List) parentIds.addAll(rawParents.map((e) => '$e'));

    final parentNames = <String, String>{};
    final rawNames = json['parentNames'];
    if (rawNames is Map) {
      rawNames.forEach((k, v) => parentNames['$k'] = '$v');
    }

    final guardianId = json['guardianId']! as String;
    if (parentIds.isEmpty) parentIds.add(guardianId);
    if (!parentNames.containsKey(guardianId)) {
      final gn = json['guardianName'] as String? ?? '';
      if (gn.isNotEmpty) parentNames[guardianId] = gn;
    }

    return MySafetyPolicy(
      guardianId: guardianId,
      guardianName: json['guardianName'] as String? ?? '',
      parentIds: parentIds,
      parentNames: parentNames,
      mode: SafetyMode.parse(json['mode'] as String?),
      grounded: json['grounded'] == true,
      sharedWithIds: ids,
      updatedAt: json['updatedAt'] is String
          ? DateTime.parse(json['updatedAt']! as String)
          : DateTime.now().toUtc(),
    );
  }
}

/// Outbound message waiting for a parent (kid / mediated mode).
final class PendingMediatedMessage {
  final String requestId;
  final String fromId;
  final String fromName;
  final String? toPeerId;
  final String? toGroupId;
  final String toLabel;
  final String text;
  final DateTime createdAt;

  const PendingMediatedMessage({
    required this.requestId,
    required this.fromId,
    required this.fromName,
    this.toPeerId,
    this.toGroupId,
    required this.toLabel,
    required this.text,
    required this.createdAt,
  });

  Map<String, Object?> toJson() => {
        'requestId': requestId,
        'fromId': fromId,
        'fromName': fromName,
        if (toPeerId != null) 'toPeerId': toPeerId,
        if (toGroupId != null) 'toGroupId': toGroupId,
        'toLabel': toLabel,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PendingMediatedMessage.fromJson(Map<String, Object?> json) =>
      PendingMediatedMessage(
        requestId: json['requestId']! as String,
        fromId: json['fromId']! as String,
        fromName: json['fromName'] as String? ?? '',
        toPeerId: json['toPeerId'] as String?,
        toGroupId: json['toGroupId'] as String?,
        toLabel: json['toLabel'] as String? ?? '',
        text: json['text'] as String? ?? '',
        createdAt: json['createdAt'] is String
            ? DateTime.parse(json['createdAt']! as String)
            : DateTime.now().toUtc(),
      );
}

/// A transparent copy of a teen (or shared) message for guardians/teachers.
final class SafetyCopy {
  final String id;
  final String fromId;
  final String fromName;
  final String toLabel;
  final String text;
  final DateTime at;
  final bool mediatedRelease;

  const SafetyCopy({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.toLabel,
    required this.text,
    required this.at,
    this.mediatedRelease = false,
  });
}

/// How widely a teen “want to talk about this first” note is shared.
///
/// Teachers/leaders never receive discuss notes.
enum NoteDiscretion {
  /// Only the primary parent (guardian on the policy).
  private,

  /// All co-parents (Mom & Dad), still not teachers.
  parents,

  /// Co-parents plus optional explicit recipients (still family-only).
  family;

  String get label => switch (this) {
        NoteDiscretion.private => 'Private · one parent',
        NoteDiscretion.parents => 'Parents only',
        NoteDiscretion.family => 'Family parents',
      };

  String get shortLabel => switch (this) {
        NoteDiscretion.private => 'Private',
        NoteDiscretion.parents => 'Parents',
        NoteDiscretion.family => 'Family',
      };

  String get blurb => switch (this) {
        NoteDiscretion.private =>
          'Only your main parent sees this. Teachers never do.',
        NoteDiscretion.parents =>
          'Mom and Dad both see it. Teachers never do.',
        NoteDiscretion.family =>
          'All co-parents on your family setup. Teachers never do.',
      };

  static NoteDiscretion parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'private' || s == 'one' || s == 'guardian') {
      return NoteDiscretion.private;
    }
    if (s == 'family' || s == 'all') return NoteDiscretion.family;
    return NoteDiscretion.parents;
  }
}

enum DiscussNoteStatus {
  open,
  acknowledged,
  closed;

  String get label => switch (this) {
        DiscussNoteStatus.open => 'Open',
        DiscussNoteStatus.acknowledged => 'Seen',
        DiscussNoteStatus.closed => 'Discussed',
      };

  static DiscussNoteStatus parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s == 'acknowledged' || s == 'seen' || s == 'ack') {
      return DiscussNoteStatus.acknowledged;
    }
    if (s == 'closed' || s == 'done' || s == 'discussed') {
      return DiscussNoteStatus.closed;
    }
    return DiscussNoteStatus.open;
  }
}

/// Teen → parent note: “I want to talk about this before I send it.”
final class DiscussNote {
  final String id;
  final String fromId;
  final String fromName;
  final String text;
  final NoteDiscretion discretion;
  final DiscussNoteStatus status;
  final DateTime createdAt;
  final DateTime? acknowledgedAt;
  final String? acknowledgedById;
  final String? acknowledgedByName;

  const DiscussNote({
    required this.id,
    required this.fromId,
    required this.fromName,
    required this.text,
    this.discretion = NoteDiscretion.parents,
    this.status = DiscussNoteStatus.open,
    required this.createdAt,
    this.acknowledgedAt,
    this.acknowledgedById,
    this.acknowledgedByName,
  });

  bool get isOpen => status == DiscussNoteStatus.open;

  DiscussNote copyWith({
    DiscussNoteStatus? status,
    DateTime? acknowledgedAt,
    String? acknowledgedById,
    String? acknowledgedByName,
  }) {
    return DiscussNote(
      id: id,
      fromId: fromId,
      fromName: fromName,
      text: text,
      discretion: discretion,
      status: status ?? this.status,
      createdAt: createdAt,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
      acknowledgedById: acknowledgedById ?? this.acknowledgedById,
      acknowledgedByName: acknowledgedByName ?? this.acknowledgedByName,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'fromId': fromId,
        'fromName': fromName,
        'text': text,
        'discretion': discretion.name,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        if (acknowledgedAt != null)
          'acknowledgedAt': acknowledgedAt!.toIso8601String(),
        if (acknowledgedById != null) 'acknowledgedById': acknowledgedById,
        if (acknowledgedByName != null)
          'acknowledgedByName': acknowledgedByName,
      };

  factory DiscussNote.fromJson(Map<String, Object?> json) => DiscussNote(
        id: json['id']! as String,
        fromId: json['fromId']! as String,
        fromName: json['fromName'] as String? ?? '',
        text: json['text'] as String? ?? '',
        discretion: NoteDiscretion.parse(json['discretion'] as String?),
        status: DiscussNoteStatus.parse(json['status'] as String?),
        createdAt: json['createdAt'] is String
            ? DateTime.parse(json['createdAt']! as String)
            : DateTime.now().toUtc(),
        acknowledgedAt: json['acknowledgedAt'] is String
            ? DateTime.parse(json['acknowledgedAt']! as String)
            : null,
        acknowledgedById: json['acknowledgedById'] as String?,
        acknowledgedByName: json['acknowledgedByName'] as String?,
      );
}

/// Local family-safety state (guardian and/or ward).
final class FamilySafetyStore {
  FamilySafetyStore();

  final Map<String, WardProfile> wards = {};
  MySafetyPolicy? myPolicy;
  final List<PendingMediatedMessage> pendingApprovals = [];
  final List<SafetyCopy> activityFeed = [];

  /// Discuss-first notes (teen → parent), both sides keep a copy.
  final List<DiscussNote> discussNotes = [];
  static const int maxFeed = 50;
  static const int maxDiscussNotes = 40;

  bool get isGuardian => wards.isNotEmpty;
  bool get isWard => myPolicy != null;
  bool get hasPending => pendingApprovals.isNotEmpty;
  bool get hasOpenDiscussNotes =>
      discussNotes.any((n) => n.status == DiscussNoteStatus.open);

  List<DiscussNote> get openDiscussNotes =>
      discussNotes.where((n) => n.status == DiscussNoteStatus.open).toList();

  /// True when this device is under a grounded policy (cannot send).
  bool get iAmGrounded => myPolicy?.grounded == true;

  /// Drop held kid messages from [wardId] (e.g. when grounding).
  void clearPendingForWard(String wardId) {
    pendingApprovals.removeWhere((e) => e.fromId == wardId);
  }

  void putWard(WardProfile w) => wards[w.wardId] = w;

  void removeWard(String wardId) => wards.remove(wardId);

  void setMyPolicy(MySafetyPolicy? p) => myPolicy = p;

  void addPending(PendingMediatedMessage m) {
    pendingApprovals.removeWhere((e) => e.requestId == m.requestId);
    pendingApprovals.insert(0, m);
  }

  PendingMediatedMessage? takePending(String requestId) {
    final i = pendingApprovals.indexWhere((e) => e.requestId == requestId);
    if (i < 0) return null;
    return pendingApprovals.removeAt(i);
  }

  void removePending(String requestId) {
    pendingApprovals.removeWhere((e) => e.requestId == requestId);
  }

  void addCopy(SafetyCopy c) {
    activityFeed.insert(0, c);
    if (activityFeed.length > maxFeed) {
      activityFeed.removeRange(maxFeed, activityFeed.length);
    }
  }

  void putDiscussNote(DiscussNote n) {
    discussNotes.removeWhere((e) => e.id == n.id);
    discussNotes.insert(0, n);
    if (discussNotes.length > maxDiscussNotes) {
      discussNotes.removeRange(maxDiscussNotes, discussNotes.length);
    }
  }

  DiscussNote? discussNote(String id) {
    for (final n in discussNotes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// Apply a co-parent status snapshot if it is as new or newer.
  ///
  /// Returns true when local state changed.
  bool applyRemoteWardStatus(WardProfile remote) {
    final local = wards[remote.wardId];
    if (local != null &&
        remote.statusUpdatedAt.isBefore(local.statusUpdatedAt)) {
      return false;
    }
    // Keep earlier createdAt when we already know the ward.
    final merged = local == null
        ? remote
        : remote.copyWith(
            // Prefer non-empty display name.
            displayName: remote.displayName.isNotEmpty
                ? remote.displayName
                : local.displayName,
          );
    // Preserve createdAt from first sighting.
    if (local != null) {
      wards[remote.wardId] = WardProfile(
        wardId: merged.wardId,
        displayName: merged.displayName,
        mode: merged.mode,
        grounded: merged.grounded,
        parentIds: merged.parentIds,
        parentNames: merged.parentNames,
        sharedWithIds: merged.sharedWithIds,
        sharedWithNames: merged.sharedWithNames,
        createdAt: local.createdAt,
        statusUpdatedAt: merged.statusUpdatedAt,
        statusById: merged.statusById,
        statusByName: merged.statusByName,
      );
    } else {
      wards[remote.wardId] = merged;
    }
    return true;
  }

  Map<String, Object?> toJson() => {
        'wards': wards.values.map((w) => w.toJson()).toList(),
        if (myPolicy != null) 'myPolicy': myPolicy!.toJson(),
        'pending': pendingApprovals.map((p) => p.toJson()).toList(),
        'discussNotes': discussNotes.map((n) => n.toJson()).toList(),
      };

  factory FamilySafetyStore.fromJson(Map<String, Object?> json) {
    final s = FamilySafetyStore();
    final wards = json['wards'];
    if (wards is List) {
      for (final w in wards) {
        if (w is Map) {
          final p = WardProfile.fromJson(Map<String, Object?>.from(w));
          s.wards[p.wardId] = p;
        }
      }
    }
    final pol = json['myPolicy'];
    if (pol is Map) {
      s.myPolicy = MySafetyPolicy.fromJson(Map<String, Object?>.from(pol));
    }
    final pending = json['pending'];
    if (pending is List) {
      for (final p in pending) {
        if (p is Map) {
          s.pendingApprovals.add(
            PendingMediatedMessage.fromJson(Map<String, Object?>.from(p)),
          );
        }
      }
    }
    final notes = json['discussNotes'];
    if (notes is List) {
      for (final n in notes) {
        if (n is Map) {
          s.discussNotes.add(
            DiscussNote.fromJson(Map<String, Object?>.from(n)),
          );
        }
      }
    }
    return s;
  }
}

/// Mesh control frames for family safety.
abstract final class FamilySafetyWire {
  static const typeKey = 'type';
  static const linkType = 'family_link';
  static const copyType = 'family_copy';
  static const mediateReqType = 'family_mediate_req';
  static const mediateDecisionType = 'family_mediate_decision';

  /// Co-parent privilege snapshot (mode, grounded, parents, share).
  static const statusType = 'family_status';

  /// One parent settled a kid message — other parents drop the pending card.
  static const settleType = 'family_mediate_settle';

  /// Teen discuss-first note (before sending a real message).
  static const discussNoteType = 'family_discuss_note';

  /// Parent ack / close on a discuss note.
  static const discussAckType = 'family_discuss_ack';

  static Uint8List encodeLink({
    required String guardianId,
    required String guardianName,
    required SafetyMode mode,
    required List<String> sharedWithIds,
    bool grounded = false,
    List<String> parentIds = const [],
    Map<String, String> parentNames = const {},
  }) {
    final parents = parentIds.isEmpty ? [guardianId] : parentIds;
    final names = Map<String, String>.from(parentNames);
    if (guardianName.isNotEmpty) {
      names.putIfAbsent(guardianId, () => guardianName);
    }
    return _enc(linkType, {
      'guardianId': guardianId,
      'guardianName': guardianName,
      'mode': mode.name,
      'sharedWithIds': sharedWithIds,
      'grounded': grounded,
      'parentIds': parents,
      'parentNames': names,
    });
  }

  static Uint8List encodeStatus({
    required WardProfile ward,
    required String updatedById,
    required String updatedByName,
  }) {
    return _enc(statusType, {
      'ward': ward.toJson(),
      'updatedById': updatedById,
      'updatedByName': updatedByName,
    });
  }

  static Uint8List encodeSettle({
    required String requestId,
    required bool approved,
    required String byId,
    required String byName,
    required String fromId,
    String? fromName,
    String? toLabel,
    String? text,
  }) {
    return _enc(settleType, {
      'requestId': requestId,
      'approved': approved,
      'byId': byId,
      'byName': byName,
      'fromId': fromId,
      if (fromName != null) 'fromName': fromName,
      if (toLabel != null) 'toLabel': toLabel,
      if (text != null) 'text': text,
    });
  }

  static Uint8List encodeCopy({
    required String fromId,
    required String fromName,
    required String toLabel,
    required String text,
    String? toPeerId,
    String? toGroupId,
  }) {
    return _enc(copyType, {
      'fromId': fromId,
      'fromName': fromName,
      'toLabel': toLabel,
      'text': text,
      if (toPeerId != null) 'toPeerId': toPeerId,
      if (toGroupId != null) 'toGroupId': toGroupId,
    });
  }

  static Uint8List encodeMediateRequest(PendingMediatedMessage m) {
    return _enc(mediateReqType, m.toJson());
  }

  static Uint8List encodeMediateDecision({
    required String requestId,
    required bool approved,
    required String guardianId,
    String? toPeerId,
    String? toGroupId,
    String? text,
  }) {
    return _enc(mediateDecisionType, {
      'requestId': requestId,
      'approved': approved,
      'guardianId': guardianId,
      if (toPeerId != null) 'toPeerId': toPeerId,
      if (toGroupId != null) 'toGroupId': toGroupId,
      if (text != null) 'text': text,
    });
  }

  static Uint8List encodeDiscussNote(DiscussNote note) {
    return _enc(discussNoteType, {'note': note.toJson()});
  }

  static Uint8List encodeDiscussAck({
    required String noteId,
    required DiscussNoteStatus status,
    required String byId,
    required String byName,
  }) {
    return _enc(discussAckType, {
      'noteId': noteId,
      'status': status.name,
      'byId': byId,
      'byName': byName,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  static FamilySafetyEvent? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      final type = map[typeKey] as String?;
      if (type == null) return null;
      return FamilySafetyEvent(type: type, body: map);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _enc(String type, Map<String, Object?> body) {
    return Uint8List.fromList(
      utf8.encode(jsonEncode({typeKey: type, ...body})),
    );
  }
}

final class FamilySafetyEvent {
  final String type;
  final Map<String, Object?> body;

  const FamilySafetyEvent({required this.type, required this.body});
}

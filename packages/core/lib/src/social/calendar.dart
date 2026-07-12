import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Which calendar an event belongs to.
enum CalendarScope {
  /// Personal schedule (optionally shared 1:1 with [CalendarEvent.scopeId] peer).
  individual,

  /// Shared with co-parents and kids (family safety unit).
  family,

  /// Mesh chat group members.
  group,

  /// Trusted organization members / local org planning.
  organization;

  String get label => switch (this) {
        CalendarScope.individual => 'Personal',
        CalendarScope.family => 'Family',
        CalendarScope.group => 'Group',
        CalendarScope.organization => 'Organization',
      };

  String get shortLabel => switch (this) {
        CalendarScope.individual => 'Me',
        CalendarScope.family => 'Family',
        CalendarScope.group => 'Group',
        CalendarScope.organization => 'Org',
      };

  static CalendarScope parse(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    return switch (s) {
      'family' => CalendarScope.family,
      'group' => CalendarScope.group,
      'organization' || 'org' => CalendarScope.organization,
      _ => CalendarScope.individual,
    };
  }
}

/// One calendar entry (appointment, reminder, family plan, org event, …).
final class CalendarEvent {
  final String id;
  final String title;
  final String? description;
  final String? location;

  /// Inclusive start (UTC).
  final DateTime start;

  /// Exclusive end (UTC). Defaults to 1 hour after start when omitted on create.
  final DateTime end;
  final bool allDay;

  final CalendarScope scope;

  /// Peer id, group id, org id, or family key (`family` / composite).
  final String scopeId;

  final String creatorId;
  final String creatorName;

  /// Who should keep a copy (mesh fan-out targets; may include creator).
  final List<String> audienceIds;

  final DateTime updatedAt;

  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    this.location,
    required this.start,
    required this.end,
    this.allDay = false,
    required this.scope,
    required this.scopeId,
    required this.creatorId,
    required this.creatorName,
    this.audienceIds = const [],
    required this.updatedAt,
  });

  Duration get duration => end.difference(start);

  bool get isMultiDay {
    final a = DateTime.utc(start.year, start.month, start.day);
    final b = DateTime.utc(end.year, end.month, end.day);
    return b.isAfter(a);
  }

  /// True if the event touches local calendar day [day] (local or UTC day bucket).
  bool overlapsDay(DateTime day) {
    final dayStart = DateTime.utc(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  bool overlapsRange(DateTime rangeStart, DateTime rangeEnd) =>
      start.isBefore(rangeEnd) && end.isAfter(rangeStart);

  CalendarEvent copyWith({
    String? title,
    String? description,
    String? location,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    CalendarScope? scope,
    String? scopeId,
    List<String>? audienceIds,
    DateTime? updatedAt,
    bool clearDescription = false,
    bool clearLocation = false,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      description: clearDescription
          ? null
          : (description ?? this.description),
      location: clearLocation ? null : (location ?? this.location),
      start: start ?? this.start,
      end: end ?? this.end,
      allDay: allDay ?? this.allDay,
      scope: scope ?? this.scope,
      scopeId: scopeId ?? this.scopeId,
      creatorId: creatorId,
      creatorName: creatorName,
      audienceIds: audienceIds ?? this.audienceIds,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        if (description != null && description!.isNotEmpty)
          'description': description,
        if (location != null && location!.isNotEmpty) 'location': location,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'allDay': allDay,
        'scope': scope.name,
        'scopeId': scopeId,
        'creatorId': creatorId,
        'creatorName': creatorName,
        'audienceIds': audienceIds,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CalendarEvent.fromJson(Map<String, Object?> json) {
    final ids = <String>[];
    final raw = json['audienceIds'];
    if (raw is List) ids.addAll(raw.map((e) => '$e'));
    final start = json['start'] is String
        ? DateTime.parse(json['start']! as String).toUtc()
        : DateTime.now().toUtc();
    final end = json['end'] is String
        ? DateTime.parse(json['end']! as String).toUtc()
        : start.add(const Duration(hours: 1));
    return CalendarEvent(
      id: json['id']! as String,
      title: json['title'] as String? ?? 'Event',
      description: json['description'] as String?,
      location: json['location'] as String?,
      start: start,
      end: end,
      allDay: json['allDay'] == true,
      scope: CalendarScope.parse(json['scope'] as String?),
      scopeId: json['scopeId'] as String? ?? '',
      creatorId: json['creatorId'] as String? ?? '',
      creatorName: json['creatorName'] as String? ?? '',
      audienceIds: ids,
      updatedAt: json['updatedAt'] is String
          ? DateTime.parse(json['updatedAt']! as String).toUtc()
          : DateTime.now().toUtc(),
    );
  }

  static String newId([Random? random]) {
    final r = random ?? Random.secure();
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final n = r.nextInt(0x7fffffff).toRadixString(16);
    return 'cal-$t-$n';
  }
}

/// Local multi-scope calendar store.
final class CalendarStore {
  CalendarStore();

  final Map<String, CalendarEvent> _events = {};

  int get length => _events.length;

  List<CalendarEvent> get all {
    final list = _events.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  CalendarEvent? operator [](String id) => _events[id];

  bool contains(String id) => _events.containsKey(id);

  void put(CalendarEvent e) {
    final existing = _events[e.id];
    if (existing != null && existing.updatedAt.isAfter(e.updatedAt)) {
      return; // Keep newer local copy.
    }
    _events[e.id] = e;
  }

  /// Force put (local edit always wins timestamp when caller stamps now).
  void putForce(CalendarEvent e) => _events[e.id] = e;

  CalendarEvent? remove(String id) => _events.remove(id);

  List<CalendarEvent> forScope(CalendarScope scope, {String? scopeId}) {
    return all.where((e) {
      if (e.scope != scope) return false;
      if (scopeId == null || scopeId.isEmpty) return true;
      return e.scopeId == scopeId;
    }).toList();
  }

  List<CalendarEvent> forDay(DateTime day, {CalendarScope? scope}) {
    return all.where((e) {
      if (scope != null && e.scope != scope) return false;
      return e.overlapsDay(day);
    }).toList();
  }

  List<CalendarEvent> inRange(
    DateTime rangeStart,
    DateTime rangeEnd, {
    CalendarScope? scope,
  }) {
    return all.where((e) {
      if (scope != null && e.scope != scope) return false;
      return e.overlapsRange(rangeStart, rangeEnd);
    }).toList();
  }

  /// Upcoming events from [from] (default now), limited to [limit].
  List<CalendarEvent> upcoming({DateTime? from, int limit = 50}) {
    final start = from ?? DateTime.now().toUtc();
    return all.where((e) => e.end.isAfter(start)).take(limit).toList();
  }

  /// Drop every event for [scope]/[scopeId] (e.g. after leaving a group).
  int removeScope(CalendarScope scope, String scopeId) {
    final ids = _events.values
        .where((e) => e.scope == scope && e.scopeId == scopeId)
        .map((e) => e.id)
        .toList();
    for (final id in ids) {
      _events.remove(id);
    }
    return ids.length;
  }

  Map<String, Object?> toJson() => {
        'events': all.map((e) => e.toJson()).toList(),
      };

  factory CalendarStore.fromJson(Map<String, Object?> json) {
    final s = CalendarStore();
    final raw = json['events'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          s.putForce(CalendarEvent.fromJson(Map<String, Object?>.from(e)));
        }
      }
    }
    return s;
  }
}

/// Mesh control frames for calendar sync.
abstract final class CalendarWire {
  static const typeKey = 'type';
  static const upsertType = 'calendar_upsert';
  static const deleteType = 'calendar_delete';

  /// Ask a peer for all events of a scope (group / org / family catch-up).
  static const syncRequestType = 'calendar_sync_request';

  static const _syncTypes = {
    upsertType,
    deleteType,
    syncRequestType,
  };

  static Uint8List encodeUpsert(CalendarEvent event) {
    return _enc(upsertType, {'event': event.toJson()});
  }

  static Uint8List encodeDelete({
    required String eventId,
    required String byId,
    String? scope,
    String? scopeId,
  }) {
    return _enc(deleteType, {
      'eventId': eventId,
      'byId': byId,
      if (scope != null) 'scope': scope,
      if (scopeId != null) 'scopeId': scopeId,
    });
  }

  static Uint8List encodeSyncRequest({
    required CalendarScope scope,
    required String scopeId,
    required String fromId,
  }) {
    return _enc(syncRequestType, {
      'scope': scope.name,
      'scopeId': scopeId,
      'fromId': fromId,
    });
  }

  static CalendarWireEvent? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      final type = map[typeKey] as String?;
      if (type == null || !_syncTypes.contains(type)) return null;
      return CalendarWireEvent(type: type, body: map);
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

final class CalendarWireEvent {
  final String type;
  final Map<String, Object?> body;

  const CalendarWireEvent({required this.type, required this.body});

  CalendarEvent? get event {
    final raw = body['event'];
    if (raw is! Map) return null;
    return CalendarEvent.fromJson(Map<String, Object?>.from(raw));
  }

  String? get eventId => body['eventId'] as String?;
  String? get byId => body['byId'] as String?;

  CalendarScope? get requestScope {
    final s = body['scope'] as String?;
    if (s == null) return null;
    return CalendarScope.parse(s);
  }

  String? get requestScopeId => body['scopeId'] as String?;
  String? get requestFromId => body['fromId'] as String?;
}

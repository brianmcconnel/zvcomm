import 'dart:convert';

/// One hour on a 24-hour day schedule (local calendar day).
final class TimeLogEntry {
  /// Local day key `YYYY-MM-DD`.
  final String dayKey;

  /// Hour of day 0–23 (local).
  final int hour;

  /// What you were doing (short label).
  final String activity;

  final String? notes;
  final DateTime updatedAt;

  const TimeLogEntry({
    required this.dayKey,
    required this.hour,
    required this.activity,
    this.notes,
    required this.updatedAt,
  });

  TimeLogEntry copyWith({
    String? activity,
    String? notes,
    DateTime? updatedAt,
    bool clearNotes = false,
  }) {
    return TimeLogEntry(
      dayKey: dayKey,
      hour: hour,
      activity: activity ?? this.activity,
      notes: clearNotes ? null : (notes ?? this.notes),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() => {
        'dayKey': dayKey,
        'hour': hour,
        'activity': activity,
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory TimeLogEntry.fromJson(Map<String, Object?> json) => TimeLogEntry(
        dayKey: json['dayKey']! as String,
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        activity: json['activity'] as String? ?? '',
        notes: json['notes'] as String?,
        updatedAt: json['updatedAt'] is String
            ? DateTime.parse(json['updatedAt']! as String)
            : DateTime.now().toUtc(),
      );

  static String dayKeyOf(DateTime localDay) {
    final d = DateTime(localDay.year, localDay.month, localDay.day);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static String formatHour(int hour) {
    final h = hour % 24;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final ap = h < 12 ? 'AM' : 'PM';
    return '$h12:00 $ap';
  }
}

/// Suggested activity chips for quick logging.
abstract final class TimeLogPresets {
  static const List<String> common = [
    'Work',
    'School',
    'Study',
    'Sleep',
    'Meal',
    'Exercise',
    'Commute',
    'Family',
    'Friends',
    'Screen time',
    'Chores',
    'Hobby',
    'Meeting',
    'Break',
    'Other',
  ];
}

/// Local 24-hour time recording store (personal productivity / accountability).
final class TimeLogStore {
  TimeLogStore();

  /// dayKey → (hour → entry)
  final Map<String, Map<int, TimeLogEntry>> _byDay = {};

  int get dayCount => _byDay.length;

  Map<int, TimeLogEntry> dayMap(String dayKey) =>
      Map.unmodifiable(_byDay[dayKey] ?? const {});

  List<TimeLogEntry> forDay(DateTime localDay) {
    final key = TimeLogEntry.dayKeyOf(localDay);
    final map = _byDay[key];
    if (map == null || map.isEmpty) return const [];
    final list = map.values.toList()..sort((a, b) => a.hour.compareTo(b.hour));
    return list;
  }

  TimeLogEntry? slot(DateTime localDay, int hour) {
    final key = TimeLogEntry.dayKeyOf(localDay);
    return _byDay[key]?[hour.clamp(0, 23)];
  }

  void put(TimeLogEntry entry) {
    final h = entry.hour.clamp(0, 23);
    final e = entry.hour == h
        ? entry
        : TimeLogEntry(
            dayKey: entry.dayKey,
            hour: h,
            activity: entry.activity,
            notes: entry.notes,
            updatedAt: entry.updatedAt,
          );
    _byDay.putIfAbsent(e.dayKey, () => {})[e.hour] = e;
  }

  void setSlot({
    required DateTime localDay,
    required int hour,
    required String activity,
    String? notes,
  }) {
    final key = TimeLogEntry.dayKeyOf(localDay);
    put(
      TimeLogEntry(
        dayKey: key,
        hour: hour.clamp(0, 23),
        activity: activity.trim(),
        notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  void clearSlot(DateTime localDay, int hour) {
    final key = TimeLogEntry.dayKeyOf(localDay);
    _byDay[key]?.remove(hour.clamp(0, 23));
    if (_byDay[key]?.isEmpty == true) _byDay.remove(key);
  }

  /// Hours 0–23 with no activity for [localDay].
  List<int> emptyHours(DateTime localDay) {
    final map = dayMap(TimeLogEntry.dayKeyOf(localDay));
    return [for (var h = 0; h < 24; h++) if (!map.containsKey(h)) h];
  }

  int filledCount(DateTime localDay) =>
      dayMap(TimeLogEntry.dayKeyOf(localDay)).length;

  /// Prompt when the current local hour is unlogged and we're at least
  /// [grace] into the hour (avoids nagging at :00).
  bool shouldPromptNow({
    DateTime? now,
    Duration grace = const Duration(minutes: 10),
  }) {
    final n = now ?? DateTime.now();
    if (n.minute < grace.inMinutes && n.second < 30 && n.minute == 0) {
      return false;
    }
    // After grace minutes into the hour.
    final minutesInto = n.minute + n.second / 60.0;
    if (minutesInto < grace.inMinutes) return false;
    final entry = slot(n, n.hour);
    return entry == null || entry.activity.trim().isEmpty;
  }

  /// Next empty hour at or before [now] (for “catch up” prompts).
  int? latestUnloggedHour({DateTime? now}) {
    final n = now ?? DateTime.now();
    for (var h = n.hour; h >= 0; h--) {
      final e = slot(n, h);
      if (e == null || e.activity.trim().isEmpty) return h;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'days': {
          for (final e in _byDay.entries)
            e.key: e.value.values.map((v) => v.toJson()).toList(),
        },
      };

  factory TimeLogStore.fromJson(Map<String, Object?> json) {
    final s = TimeLogStore();
    final days = json['days'];
    if (days is Map) {
      days.forEach((k, v) {
        if (v is! List) return;
        for (final item in v) {
          if (item is Map) {
            s.put(TimeLogEntry.fromJson(Map<String, Object?>.from(item)));
          }
        }
      });
    }
    return s;
  }

  /// Serialize for tests / debug.
  String encode() => jsonEncode(toJson());
}

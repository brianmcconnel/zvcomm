import 'dart:convert';
import 'dart:typed_data';

/// Why a peer is being reported.
enum ReportCategory {
  spam,
  harassment,
  abuse,
  impersonation,
  other;

  String get label => switch (this) {
        ReportCategory.spam => 'Spam',
        ReportCategory.harassment => 'Harassment',
        ReportCategory.abuse => 'Abuse',
        ReportCategory.impersonation => 'Impersonation',
        ReportCategory.other => 'Other',
      };

  String get id => name;

  static ReportCategory parse(String? raw) {
    if (raw == null || raw.isEmpty) return ReportCategory.other;
    final s = raw.trim().toLowerCase();
    return ReportCategory.values.firstWhere(
      (c) => c.name == s || c.id == s,
      orElse: () => ReportCategory.other,
    );
  }
}

enum ReportStatus {
  /// Stored only on this device.
  local,

  /// Forwarded over the mesh to a moderator / peer.
  submitted,
}

/// User-generated report about another device.
final class UserReport {
  final String id;
  final String subjectId;
  final String? subjectDisplayName;
  final String reporterId;
  final ReportCategory category;
  final String details;
  final DateTime createdAt;
  final String? groupId;
  final ReportStatus status;

  const UserReport({
    required this.id,
    required this.subjectId,
    required this.reporterId,
    required this.category,
    required this.details,
    required this.createdAt,
    this.subjectDisplayName,
    this.groupId,
    this.status = ReportStatus.local,
  });

  UserReport copyWith({ReportStatus? status}) => UserReport(
        id: id,
        subjectId: subjectId,
        subjectDisplayName: subjectDisplayName,
        reporterId: reporterId,
        category: category,
        details: details,
        createdAt: createdAt,
        groupId: groupId,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'subjectId': subjectId,
        if (subjectDisplayName != null)
          'subjectDisplayName': subjectDisplayName,
        'reporterId': reporterId,
        'category': category.id,
        'details': details,
        'createdAt': createdAt.toIso8601String(),
        if (groupId != null) 'groupId': groupId,
        'status': status.name,
      };

  factory UserReport.fromJson(Map<String, Object?> json) => UserReport(
        id: json['id']! as String,
        subjectId: json['subjectId']! as String,
        subjectDisplayName: json['subjectDisplayName'] as String?,
        reporterId: json['reporterId']! as String,
        category: ReportCategory.parse(json['category'] as String?),
        details: json['details'] as String? ?? '',
        createdAt: json['createdAt'] is String
            ? DateTime.parse(json['createdAt']! as String)
            : DateTime.now().toUtc(),
        groupId: json['groupId'] as String?,
        status: ReportStatus.values.firstWhere(
          (s) => s.name == (json['status'] as String? ?? 'local'),
          orElse: () => ReportStatus.local,
        ),
      );
}

/// Local report log (no central server — export or mesh-forward to a moderator).
final class ReportStore {
  ReportStore();

  final List<UserReport> _reports = [];
  static const int maxReports = 100;

  List<UserReport> get all => List.unmodifiable(_reports);

  void add(UserReport report) {
    _reports.insert(0, report);
    if (_reports.length > maxReports) {
      _reports.removeRange(maxReports, _reports.length);
    }
  }

  void clear() => _reports.clear();

  Map<String, Object?> toJson() => {
        'reports': _reports.map((r) => r.toJson()).toList(),
      };

  factory ReportStore.fromJson(Map<String, Object?> json) {
    final store = ReportStore();
    final raw = json['reports'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          store._reports.add(
            UserReport.fromJson(Map<String, Object?>.from(e)),
          );
        }
      }
    }
    return store;
  }
}

/// Mesh control payload for peer reports (`type: user_report`).
abstract final class ReportWire {
  static const typeKey = 'type';
  static const reportType = 'user_report';

  static Uint8List encode(UserReport report) {
    final body = {
      typeKey: reportType,
      'report': report.toJson(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  static UserReport? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      if (map[typeKey] != reportType) return null;
      final raw = map['report'];
      if (raw is! Map) return null;
      return UserReport.fromJson(Map<String, Object?>.from(raw));
    } catch (_) {
      return null;
    }
  }
}

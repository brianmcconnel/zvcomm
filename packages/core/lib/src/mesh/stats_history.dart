import 'mesh_stats.dart';

/// One sample of mesh counters + live topology at a point in time.
final class StatsSample {
  final DateTime at;

  /// Absolute counters (from [MeshStats]).
  final int originated;
  final int delivered;
  final int forwarded;
  final int duplicatesDropped;
  final int sendFailures;
  final int flooded;
  final int unicastRouted;
  final int presenceSent;
  final int presenceReceived;

  final int peerCount;
  final int presenceCount;

  /// Per-second rates since the previous sample (0 for first).
  final double originatedPerSec;
  final double deliveredPerSec;
  final double forwardedPerSec;
  final double failuresPerSec;

  const StatsSample({
    required this.at,
    required this.originated,
    required this.delivered,
    required this.forwarded,
    required this.duplicatesDropped,
    required this.sendFailures,
    required this.flooded,
    required this.unicastRouted,
    required this.presenceSent,
    required this.presenceReceived,
    required this.peerCount,
    required this.presenceCount,
    this.originatedPerSec = 0,
    this.deliveredPerSec = 0,
    this.forwardedPerSec = 0,
    this.failuresPerSec = 0,
  });

  /// Combined message activity (originated + delivered + forwarded)/s.
  double get activityPerSec =>
      originatedPerSec + deliveredPerSec + forwardedPerSec;
}

/// Ring buffer of [StatsSample]s for Task Manager–style charts.
final class StatsHistory {
  final int capacity;
  final List<StatsSample> _samples = [];
  StatsSample? _last;

  StatsHistory({this.capacity = 180}); // ~3 min at 1 Hz

  List<StatsSample> get samples => List.unmodifiable(_samples);

  int get length => _samples.length;

  StatsSample? get latest => _samples.isEmpty ? null : _samples.last;

  Duration? get span {
    if (_samples.length < 2) return null;
    return _samples.last.at.difference(_samples.first.at);
  }

  void clear() {
    _samples.clear();
    _last = null;
  }

  /// Record counters; rates are derived from the previous sample.
  StatsSample record({
    required MeshStats stats,
    required int peerCount,
    required int presenceCount,
    DateTime? at,
  }) {
    final now = at ?? DateTime.now().toUtc();
    final prev = _last;
    var oRate = 0.0, dRate = 0.0, fRate = 0.0, failRate = 0.0;
    if (prev != null) {
      final dt = now.difference(prev.at).inMilliseconds / 1000.0;
      if (dt > 0) {
        oRate = ((stats.originated - prev.originated).clamp(0, 1 << 30)) / dt;
        dRate = ((stats.delivered - prev.delivered).clamp(0, 1 << 30)) / dt;
        fRate = ((stats.forwarded - prev.forwarded).clamp(0, 1 << 30)) / dt;
        failRate =
            ((stats.sendFailures - prev.sendFailures).clamp(0, 1 << 30)) / dt;
      }
    }

    final sample = StatsSample(
      at: now,
      originated: stats.originated,
      delivered: stats.delivered,
      forwarded: stats.forwarded,
      duplicatesDropped: stats.duplicatesDropped,
      sendFailures: stats.sendFailures,
      flooded: stats.flooded,
      unicastRouted: stats.unicastRouted,
      presenceSent: stats.presenceSent,
      presenceReceived: stats.presenceReceived,
      peerCount: peerCount,
      presenceCount: presenceCount,
      originatedPerSec: oRate,
      deliveredPerSec: dRate,
      forwardedPerSec: fRate,
      failuresPerSec: failRate,
    );
    _samples.add(sample);
    _last = sample;
    while (_samples.length > capacity) {
      _samples.removeAt(0);
    }
    return sample;
  }
}

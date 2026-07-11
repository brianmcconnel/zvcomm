import '../models/peer.dart';
import '../models/transport_kind.dart';

/// Learned next-hop for multi-hop unicast (distance-vector lite).
final class RouteEntry {
  final String destinationId;
  final String nextHopId;
  final int hopCount;
  final DateTime lastUpdated;
  final int? lastRssi;

  const RouteEntry({
    required this.destinationId,
    required this.nextHopId,
    required this.hopCount,
    required this.lastUpdated,
    this.lastRssi,
  });

  RouteEntry copyWith({
    String? nextHopId,
    int? hopCount,
    DateTime? lastUpdated,
    int? lastRssi,
  }) =>
      RouteEntry(
        destinationId: destinationId,
        nextHopId: nextHopId ?? this.nextHopId,
        hopCount: hopCount ?? this.hopCount,
        lastUpdated: lastUpdated ?? this.lastUpdated,
        lastRssi: lastRssi ?? this.lastRssi,
      );
}

/// Adaptive route cache: prefer fresher / shorter paths / better RSSI.
final class RouteTable {
  final Duration routeTtl;
  final Map<String, RouteEntry> _routes = {};

  RouteTable({this.routeTtl = const Duration(minutes: 2)});

  Map<String, RouteEntry> get snapshot => Map.unmodifiable(_routes);

  RouteEntry? lookup(String destinationId) {
    final e = _routes[destinationId];
    if (e == null) return null;
    if (DateTime.now().toUtc().difference(e.lastUpdated) > routeTtl) {
      _routes.remove(destinationId);
      return null;
    }
    return e;
  }

  /// Learn that [destinationId] is reachable via [nextHopId] in [hopCount] hops.
  void learn({
    required String destinationId,
    required String nextHopId,
    required int hopCount,
    int? rssi,
  }) {
    if (destinationId.isEmpty || nextHopId.isEmpty) return;
    if (hopCount < 1) return;

    final now = DateTime.now().toUtc();
    final existing = _routes[destinationId];
    if (existing == null) {
      _routes[destinationId] = RouteEntry(
        destinationId: destinationId,
        nextHopId: nextHopId,
        hopCount: hopCount,
        lastUpdated: now,
        lastRssi: rssi,
      );
      return;
    }

    final betterHops = hopCount < existing.hopCount;
    final sameHopsBetterRssi = hopCount == existing.hopCount &&
        rssi != null &&
        (existing.lastRssi == null || rssi > existing.lastRssi!);
    final refreshSame = hopCount == existing.hopCount &&
        nextHopId == existing.nextHopId;

    if (betterHops || sameHopsBetterRssi || refreshSame) {
      _routes[destinationId] = existing.copyWith(
        nextHopId: nextHopId,
        hopCount: hopCount,
        lastUpdated: now,
        lastRssi: rssi,
      );
    }
  }

  /// When we hear a packet from [sourceId] via neighbor [fromNeighborId],
  /// hop count from the remaining hopLimit is unknown; treat as 1-hop to source
  /// if fromNeighbor is the source, else hopCount = max path estimate.
  void learnFromIngress({
    required String sourceId,
    required String fromNeighborId,
    required int packetHopLimitRemaining,
    required int originalHopLimit,
    int? rssi,
  }) {
    final hopsFromSource = (originalHopLimit - packetHopLimitRemaining)
        .clamp(1, 255);
    // Next hop toward source is the neighbor we heard it from.
    learn(
      destinationId: sourceId,
      nextHopId: fromNeighborId,
      hopCount: hopsFromSource,
      rssi: rssi,
    );
  }

  void forget(String destinationId) => _routes.remove(destinationId);

  void clear() => _routes.clear();

  int get length => _routes.length;
}

/// Score a candidate neighbor for adaptive link selection (higher is better).
int scoreNeighbor(Peer peer, {String? preferredNextHop}) {
  var score = 0;
  if (preferredNextHop != null && peer.id == preferredNextHop) {
    score += 1000;
  }
  final t = peer.preferredTransport;
  if (t != null) score += t.bandwidthRank;
  final rssi = peer.rssi;
  if (rssi != null) {
    // Map -100..-20 → 0..80
    score += (rssi + 100).clamp(0, 80);
  }
  return score;
}

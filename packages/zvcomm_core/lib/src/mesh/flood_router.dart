import 'dart:collection';

import 'mesh_packet.dart';

/// Bounded LRU-style dedup set for flood suppression.
final class PacketDeduper {
  final int capacity;
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();

  PacketDeduper({this.capacity = 2048});

  /// Returns `true` if this is the first time we see [key].
  bool observe(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    while (_seen.length > capacity) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  void clear() => _seen.clear();

  int get length => _seen.length;
}

/// Managed flooding decisions for multi-hop mesh (Phase 0).
///
/// Policy:
/// - Drop duplicates (source + messageId).
/// - Drop when hopLimit <= 0 after local delivery check.
/// - Forward to all neighbors except the ingress link (caller handles that).
final class FloodRouter {
  final PacketDeduper deduper;
  final String localId;

  FloodRouter({
    required this.localId,
    int dedupCapacity = 2048,
  }) : deduper = PacketDeduper(capacity: dedupCapacity);

  /// Result of handling an inbound packet.
  FloodDecision decide(MeshPacket packet) {
    if (!deduper.observe(packet.dedupKey)) {
      return const FloodDecision(duplicate: true);
    }

    final forUs = packet.isBroadcast || packet.destinationId == localId;
    final canForward = packet.hopLimit > 1 &&
        (packet.isBroadcast || packet.destinationId != localId);

    return FloodDecision(
      deliverLocally: forUs,
      shouldForward: canForward,
      forwardPacket: canForward ? packet.decrementHop() : null,
    );
  }
}

/// Outcome of [FloodRouter.decide].
final class FloodDecision {
  final bool duplicate;
  final bool deliverLocally;
  final bool shouldForward;
  final MeshPacket? forwardPacket;

  const FloodDecision({
    this.duplicate = false,
    this.deliverLocally = false,
    this.shouldForward = false,
    this.forwardPacket,
  });
}

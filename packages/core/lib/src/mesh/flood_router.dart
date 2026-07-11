import 'dart:collection';

import 'bloom_filter.dart';
import 'mesh_config.dart';
import 'mesh_packet.dart';

/// Bounded LRU-style exact dedup set (Phase 0 compatible).
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

/// Common interface for exact and hybrid dedupers.
abstract interface class Deduper {
  bool observe(String key);
  void clear();
}

final class ExactDeduperAdapter implements Deduper {
  final PacketDeduper inner;
  ExactDeduperAdapter(this.inner);
  @override
  bool observe(String key) => inner.observe(key);
  @override
  void clear() => inner.clear();
}

final class HybridDeduperAdapter implements Deduper {
  final HybridPacketDeduper inner;
  HybridDeduperAdapter(this.inner);
  @override
  bool observe(String key) => inner.observe(key);
  @override
  void clear() => inner.clear();
}

/// Managed flooding + TTL decisions for multi-hop mesh.
///
/// Policy:
/// - Drop duplicates (source + messageId) via exact LRU and optional bloom.
/// - Drop when hopLimit would not allow forward after local delivery.
/// - Forward to neighbors except the ingress link (caller handles fan-out).
final class FloodRouter {
  final Deduper deduper;
  final String localId;

  FloodRouter({
    required this.localId,
    int dedupCapacity = 2048,
    bool useBloom = true,
    int bloomBits = 8192 * 8,
  }) : deduper = useBloom
            ? HybridDeduperAdapter(
                HybridPacketDeduper(
                  exactCapacity: dedupCapacity,
                  bloomBits: bloomBits,
                ),
              )
            : ExactDeduperAdapter(PacketDeduper(capacity: dedupCapacity));

  factory FloodRouter.fromConfig(String localId, MeshConfig config) {
    return FloodRouter(
      localId: localId,
      dedupCapacity: config.dedupExactCapacity,
      useBloom: true,
      bloomBits: config.bloomBits,
    );
  }

  /// Result of handling an inbound packet.
  FloodDecision decide(MeshPacket packet) {
    if (!deduper.observe(packet.dedupKey)) {
      return const FloodDecision(duplicate: true);
    }

    final forUs = packet.isBroadcast || packet.destinationId == localId;
    final canForward = packet.hopLimit > 1 &&
        (packet.isBroadcast || packet.destinationId != localId);

    if (!canForward && !forUs && packet.hopLimit <= 1) {
      return FloodDecision(
        deliverLocally: forUs,
        shouldForward: false,
        ttlExpired: !forUs,
      );
    }

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
  final bool ttlExpired;
  final MeshPacket? forwardPacket;

  const FloodDecision({
    this.duplicate = false,
    this.deliverLocally = false,
    this.shouldForward = false,
    this.ttlExpired = false,
    this.forwardPacket,
  });
}

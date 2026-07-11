/// Tunables for [MeshNode] routing and presence.
final class MeshConfig {
  /// Default TTL for newly originated packets.
  final int defaultHopLimit;

  /// Exact LRU capacity before keys age into the bloom filter.
  final int dedupExactCapacity;

  /// Bloom filter size in bits.
  final int bloomBits;

  /// How often to emit presence heartbeats (Duration.zero disables).
  final Duration presenceInterval;

  /// Consider a peer offline after this silence.
  final Duration presenceTtl;

  /// Prefer unicast next-hop from route table before flooding.
  final bool adaptiveRouting;

  /// Original hop limit stamped for route learning (stored in packet).
  final int routeLearningBaseHopLimit;

  const MeshConfig({
    this.defaultHopLimit = 8,
    this.dedupExactCapacity = 2048,
    this.bloomBits = 8192 * 8,
    this.presenceInterval = const Duration(seconds: 5),
    this.presenceTtl = const Duration(seconds: 20),
    this.adaptiveRouting = true,
    this.routeLearningBaseHopLimit = 8,
  });

  static const MeshConfig defaults = MeshConfig();

  /// Dense sims / high churn.
  static const MeshConfig simulation = MeshConfig(
    defaultHopLimit: 12,
    dedupExactCapacity: 4096,
    bloomBits: 16384 * 8,
    presenceInterval: Duration(seconds: 2),
    presenceTtl: Duration(seconds: 10),
  );
}

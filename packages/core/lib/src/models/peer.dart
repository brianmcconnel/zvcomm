import 'transport_kind.dart';

/// A discovered remote endpoint on one or more transports.
///
/// Peers are identity-aware when a device ID / public key is known; discovery
/// may also produce transient peers known only by a transport address.
final class Peer {
  /// Stable device identifier (hex or base64 URL-safe). Empty until enrolled.
  final String id;

  /// Human-readable display name (may be empty).
  final String displayName;

  /// Transports on which this peer was recently seen.
  final Set<TransportKind> transports;

  /// Last observed RSSI in dBm, if available.
  final int? rssi;

  /// Opaque per-transport addresses (e.g. BLE MAC, Wi-Fi service ID).
  final Map<TransportKind, String> addresses;

  /// Wall-clock of last discovery sighting.
  final DateTime lastSeen;

  /// Optional metadata from advertisements (capability flags, version, etc.).
  final Map<String, String> metadata;

  const Peer({
    required this.id,
    this.displayName = '',
    this.transports = const {},
    this.rssi,
    this.addresses = const {},
    required this.lastSeen,
    this.metadata = const {},
  });

  Peer copyWith({
    String? id,
    String? displayName,
    Set<TransportKind>? transports,
    int? rssi,
    Map<TransportKind, String>? addresses,
    DateTime? lastSeen,
    Map<String, String>? metadata,
  }) {
    return Peer(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      transports: transports ?? this.transports,
      rssi: rssi ?? this.rssi,
      addresses: addresses ?? this.addresses,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Preferred transport for data when multiple are available.
  TransportKind? get preferredTransport {
    if (transports.isEmpty) return null;
    return transports.reduce(
      (a, b) => a.bandwidthRank >= b.bandwidthRank ? a : b,
    );
  }

  @override
  String toString() =>
      'Peer(id=$id, name=$displayName, transports=$transports, rssi=$rssi)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

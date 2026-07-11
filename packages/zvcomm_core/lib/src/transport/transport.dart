import 'dart:async';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import 'connection.dart';

/// Capability flags for a transport implementation.
final class TransportCapabilities {
  final bool canDiscover;
  final bool canConnect;
  final bool canAdvertise;
  final bool supportsBackground;
  final int? maxMtu;
  final int? typicalRangeMeters;

  const TransportCapabilities({
    this.canDiscover = true,
    this.canConnect = true,
    this.canAdvertise = true,
    this.supportsBackground = false,
    this.maxMtu,
    this.typicalRangeMeters,
  });
}

/// Unified pluggable transport API used by the mesh layer.
///
/// Concrete backends (BLE, NFC, Wi-Fi, mock, future UWB) implement this
/// interface so routing never depends on platform specifics.
abstract class Transport {
  /// Technology this transport implements.
  TransportKind get kind;

  /// Human-readable name for UI / logs.
  String get name;

  /// Static capabilities.
  TransportCapabilities get capabilities;

  /// Whether the underlying radio / stack is available on this device.
  Future<bool> isAvailable();

  /// Start advertising local presence (optional for some transports).
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  });

  /// Stop advertising.
  Future<void> stopAdvertising();

  /// Discover nearby peers. Implementations push [Peer] updates as they appear.
  ///
  /// The stream remains open until cancelled or [stopDiscovery] is called.
  Stream<Peer> discover();

  /// Stop active discovery scans.
  Future<void> stopDiscovery();

  /// Open a connection to [peer] on this transport.
  Future<Connection> connect(Peer peer);

  /// Inbound connections accepted by this transport (peer dialed us).
  ///
  /// Mesh nodes must subscribe so they can receive frames on passive links.
  Stream<Connection> get incomingConnections;

  /// Optional power-management hint (duty cycle, scan interval, etc.).
  Future<void> setPowerMode(TransportPowerMode mode);

  /// Release resources.
  Future<void> dispose();
}

/// Coarse power / scan aggressiveness modes.
enum TransportPowerMode {
  /// Maximum discovery rate and throughput.
  performance,

  /// Balanced default.
  balanced,

  /// Prefer battery life; slower discovery.
  powerSaver,

  /// Minimal activity (e.g. only connected links).
  ultraLow,
}

/// Optional mixin for transports that accept raw send without a full connection
/// (e.g. NFC one-shot, BLE advertisement payloads).
mixin ConnectionlessSend on Transport {
  Future<void> sendTo(Peer peer, Uint8List data);
}

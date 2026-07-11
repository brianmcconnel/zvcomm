import 'dart:async';

import 'package:zvcomm_core/zvcomm_core.dart';

/// Placeholder Wi-Fi P2P transport. Phase 1 will add platform implementations.
final class WifiTransport implements Transport {
  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  String get name => 'Wi-Fi P2P';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: false,
        maxMtu: 1400,
        typicalRangeMeters: 50,
      );

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    // No-op until Phase 1.
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Stream<Peer> discover() => const Stream.empty();

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<Connection> connect(Peer peer) async {
    throw UnsupportedError('Wi-Fi transport not implemented (Phase 1)');
  }

  @override
  Stream<Connection> get incomingConnections => const Stream.empty();

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {}

  @override
  Future<void> dispose() async {}
}

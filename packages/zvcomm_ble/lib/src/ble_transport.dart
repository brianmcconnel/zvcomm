import 'dart:async';

import 'package:zvcomm_core/zvcomm_core.dart';

/// Placeholder BLE transport. Always reports unavailable until Phase 1.
final class BleTransport implements Transport {
  @override
  TransportKind get kind => TransportKind.ble;

  @override
  String get name => 'Bluetooth LE';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 512,
        typicalRangeMeters: 30,
      );

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    // No-op until Phase 1; [isAvailable] is false so managers skip us.
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Stream<Peer> discover() => const Stream.empty();

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<Connection> connect(Peer peer) async {
    throw UnsupportedError('BLE transport not implemented (Phase 1)');
  }

  @override
  Stream<Connection> get incomingConnections => const Stream.empty();

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {}

  @override
  Future<void> dispose() async {}
}

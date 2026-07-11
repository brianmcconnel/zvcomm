import 'dart:async';

import 'package:zvcomm_core/zvcomm_core.dart';

/// Placeholder NFC transport. Phase 1 will use a permissive plugin or channels.
final class NfcTransport implements Transport {
  @override
  TransportKind get kind => TransportKind.nfc;

  @override
  String get name => 'NFC';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: false,
        supportsBackground: false,
        maxMtu: 256,
        typicalRangeMeters: 1,
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
    throw UnsupportedError('NFC transport not implemented (Phase 1)');
  }

  @override
  Stream<Connection> get incomingConnections => const Stream.empty();

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {}

  @override
  Future<void> dispose() async {}
}

import 'dart:async';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import '../transport/connection.dart';
import '../transport/transport.dart';
import 'transport_plugin.dart';

/// Placeholder transport for future radios (UWB, LoRa, …).
///
/// Always reports unavailable until a real backend is registered under the
/// same plugin id (registry replace) or [enabled] is forced for tests.
final class StubTransport implements Transport {
  @override
  final TransportKind kind;
  @override
  final String name;
  final bool forceAvailable;

  StubTransport({
    required this.kind,
    required this.name,
    this.forceAvailable = false,
  });

  @override
  TransportCapabilities get capabilities => TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: false,
        maxMtu: kind == TransportKind.lora ? 200 : 1024,
        typicalRangeMeters: kind == TransportKind.lora
            ? 5000
            : kind == TransportKind.uwb
                ? 20
                : 50,
      );

  @override
  Stream<Connection> get incomingConnections => const Stream.empty();

  @override
  Future<bool> isAvailable() async => forceAvailable;

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {}

  @override
  Future<void> stopAdvertising() async {}

  @override
  Stream<Peer> discover() => const Stream.empty();

  @override
  Future<void> stopDiscovery() async {}

  @override
  Future<Connection> connect(Peer peer) async {
    throw UnsupportedError('$name transport is a stub (Phase 5 placeholder)');
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {}

  @override
  Future<void> dispose() async {}
}

/// Built-in stub plugins for future hardware (disabled by default).
abstract final class BuiltinStubPlugins {
  static final TransportPlugin uwb = SimpleTransportPlugin(
    id: 'builtin.uwb.stub',
    name: 'UWB (stub)',
    kind: TransportKind.uwb,
    priority: 80,
    enabledByDefault: false,
    description: 'Placeholder for IEEE 802.15.4z / vendor UWB APIs.',
    capabilities: const TransportCapabilities(
      maxMtu: 1024,
      typicalRangeMeters: 20,
    ),
    factory: (ctx) => StubTransport(kind: TransportKind.uwb, name: 'UWB'),
  );

  static final TransportPlugin lora = SimpleTransportPlugin(
    id: 'builtin.lora.stub',
    name: 'LoRa (stub)',
    kind: TransportKind.lora,
    priority: 20,
    enabledByDefault: false,
    description: 'Placeholder for LoRa/LoRaWAN or custom long-range radio.',
    capabilities: const TransportCapabilities(
      maxMtu: 200,
      typicalRangeMeters: 5000,
    ),
    factory: (ctx) => StubTransport(kind: TransportKind.lora, name: 'LoRa'),
  );

  static List<TransportPlugin> get all => [uwb, lora];
}

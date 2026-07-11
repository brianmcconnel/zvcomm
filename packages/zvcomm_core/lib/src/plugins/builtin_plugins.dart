import '../models/transport_kind.dart';
import '../transport/mock_transport.dart';
import 'adapter_transport.dart';
import 'hardware_adapter.dart';
import 'stub_transports.dart';
import 'transport_plugin.dart';
import 'transport_registry.dart';

/// Core plugins that do not depend on Flutter platform channels.
///
/// Flutter packages (`zvcomm_ble`, `zvcomm_nfc`, `zvcomm_wifi`) register
/// themselves via their `register*Plugins()` entry points from the app.
abstract final class BuiltinCorePlugins {
  static const mockId = 'builtin.mock';
  static const hardwareAdapterId = 'builtin.hardware_adapter';

  /// In-process mock radio (requires [MockMedium] in options: `medium`).
  static final TransportPlugin mock = SimpleTransportPlugin(
    id: mockId,
    name: 'Mock radio',
    kind: TransportKind.mock,
    priority: 50,
    enabledByDefault: false,
    description: 'In-process radio for demos and tests. Pass options.medium.',
    factory: (ctx) {
      final medium = ctx.option<MockMedium>('medium');
      if (medium == null) {
        throw ArgumentError('builtin.mock requires options["medium"]');
      }
      return MockTransport(
        medium: medium,
        localId: ctx.localId,
        displayName: ctx.displayName ?? '',
        position: ctx.option<SimPoint>('position'),
        rangeMeters: ctx.option<double>('rangeMeters') ?? 50,
      );
    },
  );

  /// Point-to-point transport over a [HardwareAdapter] in options: `adapter`.
  static final TransportPlugin hardwareAdapter = SimpleTransportPlugin(
    id: hardwareAdapterId,
    name: 'Hardware adapter',
    kind: TransportKind.custom,
    priority: 30,
    enabledByDefault: false,
    description:
        'Wraps a HardwareAdapter (serial, USB, loopback) as a mesh transport.',
    factory: (ctx) {
      final adapter = ctx.option<HardwareAdapter>('adapter');
      if (adapter == null) {
        throw ArgumentError(
          'builtin.hardware_adapter requires options["adapter"]',
        );
      }
      return AdapterTransport(
        adapter: adapter,
        kind: ctx.option<TransportKind>('kind') ?? TransportKind.custom,
        name: ctx.option<String>('name') ?? adapter.name,
        remotePeerId: ctx.option<String>('remotePeerId') ?? 'hw-peer',
        remoteDisplayName:
            ctx.option<String>('remoteDisplayName') ?? 'Hardware peer',
      );
    },
  );

  /// Register mock, hardware bridge, and UWB/LoRa stubs.
  static void registerAll([TransportRegistry? registry]) {
    final r = registry ?? TransportRegistry.instance;
    r.registerAll([
      mock,
      hardwareAdapter,
      ...BuiltinStubPlugins.all,
    ]);
  }
}

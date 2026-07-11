import 'package:core/core.dart';

import 'ble_transport.dart';

/// Plugin id for the built-in BLE transport.
const String blePluginId = 'builtin.ble';

/// Registers BLE with [TransportRegistry.instance] (or [registry]).
void registerBlePlugin([TransportRegistry? registry]) {
  (registry ?? TransportRegistry.instance).register(
    SimpleTransportPlugin(
      id: blePluginId,
      name: 'Bluetooth LE',
      kind: TransportKind.ble,
      priority: 40,
      enabledByDefault: true,
      description: 'GATT mesh service via bluetooth_low_energy (MIT).',
      capabilities: const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 512,
        typicalRangeMeters: 30,
      ),
      factory: (_) => BleTransport(),
    ),
  );
}

import 'package:zvcomm_core/zvcomm_core.dart';

import 'wifi_transport.dart';

const String wifiPluginId = 'builtin.wifi';

void registerWifiPlugin([TransportRegistry? registry]) {
  (registry ?? TransportRegistry.instance).register(
    SimpleTransportPlugin(
      id: wifiPluginId,
      name: 'Wi-Fi P2P / LAN',
      kind: TransportKind.wifi,
      priority: 100,
      enabledByDefault: true,
      description: 'Wi-Fi Direct (Android) + LAN SoftAP fallback.',
      capabilities: const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        maxMtu: 1400,
        typicalRangeMeters: 50,
      ),
      factory: (_) => WifiTransport(),
    ),
  );
}

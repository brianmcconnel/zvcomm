import 'package:zvcomm_core/zvcomm_core.dart';

import 'nfc_transport.dart';

const String nfcPluginId = 'builtin.nfc';

void registerNfcPlugin([TransportRegistry? registry]) {
  (registry ?? TransportRegistry.instance).register(
    SimpleTransportPlugin(
      id: nfcPluginId,
      name: 'NFC',
      kind: TransportKind.nfc,
      priority: 10,
      enabledByDefault: true,
      description: 'NDEF bootstrap / short payloads (MIT plugins).',
      capabilities: const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: false,
        maxMtu: 256,
        typicalRangeMeters: 1,
      ),
      factory: (_) => NfcTransport(),
    ),
  );
}

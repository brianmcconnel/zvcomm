import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zvcomm_ble/zvcomm_ble.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_nfc/zvcomm_nfc.dart';
import 'package:zvcomm_ui/zvcomm_ui.dart';
import 'package:zvcomm_wifi/zvcomm_wifi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZvcommApp());
}

class ZvcommApp extends StatelessWidget {
  const ZvcommApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZVComm',
      debugShowCheckedModeBanner: false,
      theme: ZvcommTheme.light(),
      darkTheme: ZvcommTheme.dark(),
      themeMode: ThemeMode.system,
      home: const PeerDiscoveryPage(),
    );
  }
}

/// Phase 1 home: multi-transport discovery (BLE, NFC, Wi-Fi/LAN, optional mock).
class PeerDiscoveryPage extends StatefulWidget {
  const PeerDiscoveryPage({super.key});

  @override
  State<PeerDiscoveryPage> createState() => _PeerDiscoveryPageState();
}

class _PeerDiscoveryPageState extends State<PeerDiscoveryPage> {
  DeviceIdentity? _identity;
  late final BleTransport _ble;
  late final NfcTransport _nfc;
  late final WifiTransport _wifi;
  late final MockMedium _medium;
  MockTransport? _mockTransport;
  MockTransport? _demoPeerTransport;
  MeshNode? _node;

  StreamSubscription<Peer>? _peerSub;
  final Map<String, Peer> _peers = {};
  final Map<TransportKind, bool> _available = {};
  bool _running = false;
  final bool _useMockDemo = true;
  TransportPowerMode _powerMode = TransportPowerMode.balanced;
  String? _status;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _ble = BleTransport();
    _nfc = NfcTransport();
    _wifi = WifiTransport();
    _medium = MockMedium();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    final identity =
        await DeviceIdentity.generate(displayName: 'This device');
    _identity = identity;
    _mockTransport = MockTransport(
      medium: _medium,
      localId: identity.id,
      displayName: identity.displayName,
      position: const SimPoint(0, 0),
    );
    _demoPeerTransport = MockTransport(
      medium: _medium,
      localId: 'demo-peer-01',
      displayName: 'Demo Peer',
      position: const SimPoint(8, 0),
    );
    _node = MeshNode(
      localId: identity.id,
      displayName: identity.displayName,
      transports: TransportManager([
        _ble,
        _nfc,
        _wifi,
        _mockTransport!,
      ]),
    );
    if (!mounted) return;
    setState(() => _ready = true);
    await _probeAvailability();
    await _start();
  }

  Future<void> _probeAvailability() async {
    final results = <TransportKind, bool>{
      TransportKind.ble: await _ble.isAvailable(),
      TransportKind.nfc: await _nfc.isAvailable(),
      TransportKind.wifi: await _wifi.isAvailable(),
      TransportKind.mock: true,
    };
    if (!mounted) return;
    setState(() => _available.addAll(results));
  }

  Future<void> _start() async {
    final node = _node;
    final demo = _demoPeerTransport;
    if (node == null || demo == null) return;
    setState(() => _status = 'Starting discovery…');
    if (_useMockDemo) {
      await demo.startAdvertising(
        localId: 'demo-peer-01',
        displayName: 'Demo Peer',
        metadata: {'demo': 'true'},
      );
    }
    _peerSub = node.peerUpdates.listen((peer) {
      if (!mounted) return;
      setState(() => _peers[peer.id] = peer);
    });
    await node.transports.setPowerMode(_powerMode);
    await node.start();
    if (!mounted) return;
    final active = _available.entries
        .where((e) => e.value)
        .map((e) => e.key.name.toUpperCase())
        .join(', ');
    setState(() {
      _running = true;
      _status = 'Scanning: ${active.isEmpty ? "none" : active}'
          '${_useMockDemo ? " + mock demo" : ""}'
          ' · power=${_powerMode.name} · Ed25519/X25519 identity';
    });
  }

  Future<void> _stop() async {
    final node = _node;
    final demo = _demoPeerTransport;
    await _peerSub?.cancel();
    _peerSub = null;
    await node?.stop();
    await demo?.stopAdvertising();
    if (!mounted) return;
    setState(() {
      _running = false;
      _status = 'Stopped';
    });
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_running) {
      await _stop();
    } else {
      await _start();
    }
  }

  Future<void> _cyclePowerMode() async {
    final node = _node;
    if (node == null) return;
    const modes = TransportPowerMode.values;
    final next = modes[(_powerMode.index + 1) % modes.length];
    _powerMode = next;
    await node.transports.setPowerMode(next);
    if (!mounted) return;
    setState(() {
      _status = 'Power mode → ${next.name}';
    });
  }

  @override
  void dispose() {
    // Cancel discovery/announce timers before async dispose (widget tests).
    _mockTransport?.cancelDiscoverySync();
    _demoPeerTransport?.cancelDiscoverySync();
    _wifi.cancelTimersSync();
    unawaited(_peerSub?.cancel());
    unawaited(_node?.dispose());
    unawaited(_demoPeerTransport?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerList = _peers.values.toList();
    final identity = _identity;

    if (!_ready || identity == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZVComm'),
        actions: [
          IconButton(
            tooltip: 'Cycle power mode',
            onPressed: _cyclePowerMode,
            icon: const Icon(Icons.battery_saver_outlined),
          ),
          IconButton(
            tooltip: _running ? 'Stop discovery' : 'Start discovery',
            onPressed: _toggle,
            icon: Icon(
              _running ? Icons.stop_circle_outlined : Icons.play_circle_outline,
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Local identity',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    identity.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText(
                    identity.id,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TransportChip(
                        label: 'BLE',
                        available: _available[TransportKind.ble] ?? false,
                      ),
                      _TransportChip(
                        label: 'NFC',
                        available: _available[TransportKind.nfc] ?? false,
                      ),
                      _TransportChip(
                        label: 'Wi-Fi',
                        available: _available[TransportKind.wifi] ?? false,
                      ),
                      _TransportChip(
                        label: 'Mock',
                        available: true,
                      ),
                    ],
                  ),
                  if (_status != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _status!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ],
                  if (kIsWeb)
                    Text(
                      'Web build: radio transports unavailable; mock only.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Discovered peers (${peerList.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: PeerListView(
              peers: peerList,
              emptyMessage: _running
                  ? 'Listening for peers…\n'
                      'BLE / NFC need hardware; Wi-Fi uses Direct (Android) or LAN SoftAP fallback.'
                  : 'Discovery stopped',
              onPeerTap: (peer) {
                final transports =
                    peer.transports.map((t) => t.name).join(', ');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '${peer.displayName.isEmpty ? peer.id : peer.displayName}'
                      ' · $transports',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TransportChip extends StatelessWidget {
  final String label;
  final bool available;

  const _TransportChip({required this.label, required this.available});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        available ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: available ? scheme.primary : scheme.outline,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(
        color: available ? scheme.primary : scheme.outlineVariant,
      ),
    );
  }
}

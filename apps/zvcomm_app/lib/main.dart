import 'dart:async';

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

/// Phase 0 home: local identity + discovered peers via mock (and stub) transports.
class PeerDiscoveryPage extends StatefulWidget {
  const PeerDiscoveryPage({super.key});

  @override
  State<PeerDiscoveryPage> createState() => _PeerDiscoveryPageState();
}

class _PeerDiscoveryPageState extends State<PeerDiscoveryPage> {
  late final DeviceIdentity _identity;
  late final MockMedium _medium;
  late final MockTransport _mockTransport;
  late final MeshNode _node;
  late final MockTransport _demoPeerTransport;

  StreamSubscription<Peer>? _peerSub;
  final Map<String, Peer> _peers = {};
  bool _running = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _identity = DeviceIdentity.generate(displayName: 'This device');
    _medium = MockMedium();

    // Local node on the mock medium.
    _mockTransport = MockTransport(
      medium: _medium,
      localId: _identity.id,
      displayName: _identity.displayName,
      position: const SimPoint(0, 0),
    );

    // Demo remote peer so the UI is non-empty without a second device.
    _demoPeerTransport = MockTransport(
      medium: _medium,
      localId: 'demo-peer-01',
      displayName: 'Demo Peer',
      position: const SimPoint(8, 0),
    );

    _node = MeshNode(
      localId: _identity.id,
      displayName: _identity.displayName,
      transports: TransportManager([
        _mockTransport,
        BleTransport(),
        NfcTransport(),
        WifiTransport(),
      ]),
    );

    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() => _status = 'Starting discovery…');
    await _demoPeerTransport.startAdvertising(
      localId: 'demo-peer-01',
      displayName: 'Demo Peer',
      metadata: {'demo': 'true'},
    );
    _peerSub = _node.peerUpdates.listen((peer) {
      if (!mounted) return;
      setState(() {
        _peers[peer.id] = peer;
      });
    });
    await _node.start();
    if (!mounted) return;
    setState(() {
      _running = true;
      _status = 'Scanning (mock medium + transport stubs)';
    });
  }

  Future<void> _stop() async {
    await _peerSub?.cancel();
    _peerSub = null;
    await _node.stop();
    await _demoPeerTransport.stopAdvertising();
    if (!mounted) return;
    setState(() {
      _running = false;
      _status = 'Stopped';
    });
  }

  Future<void> _toggle() async {
    if (_running) {
      await _stop();
    } else {
      await _start();
    }
  }

  @override
  void dispose() {
    // Cancel discovery timers synchronously so Flutter tests do not see
    // pending timers after the widget tree is disposed.
    _mockTransport.cancelDiscoverySync();
    _demoPeerTransport.cancelDiscoverySync();
    unawaited(_peerSub?.cancel());
    unawaited(_node.dispose());
    unawaited(_demoPeerTransport.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peerList = _peers.values.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZVComm'),
        actions: [
          IconButton(
            tooltip: _running ? 'Stop discovery' : 'Start discovery',
            onPressed: _toggle,
            icon: Icon(_running ? Icons.stop_circle_outlined : Icons.play_circle_outline),
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
                    _identity.displayName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SelectableText(
                    _identity.id,
                    style: Theme.of(context).textTheme.bodySmall,
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
                  ? 'Listening on mock transport…\nBLE / NFC / Wi-Fi stubs are unavailable until Phase 1.'
                  : 'Discovery stopped',
              onPeerTap: (peer) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected ${peer.displayName.isEmpty ? peer.id : peer.displayName}'),
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

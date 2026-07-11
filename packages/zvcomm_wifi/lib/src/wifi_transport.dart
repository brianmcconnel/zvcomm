import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

import 'lan_softap_transport.dart';

/// Multi-backend Wi-Fi transport.
///
/// * **Android:** Wi-Fi Direct group via [flutter_p2p_connection] (MIT).
/// * **Desktop / fallback:** [LanSoftApTransport] UDP discovery + TCP.
final class WifiTransport implements Transport {
  final LanSoftApTransport _lan = LanSoftApTransport();
  FlutterP2pHost? _host;
  FlutterP2pClient? _client;

  final StreamController<Peer> _discovery =
      StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();

  final Map<String, _P2pTextConnection> _p2pLinks = {};
  final Map<String, BleDiscoveredDevice> _bleDevices = {};
  final List<StreamSubscription<dynamic>> _subs = [];

  String _localId = '';
  String _displayName = '';
  bool _useAndroidP2p = false;

  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  String get name => _useAndroidP2p ? 'Wi-Fi Direct' : _lan.name;

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
  Stream<Connection> get incomingConnections => Stream.multi((controller) {
        final a = _inbound.stream.listen(controller.add, onError: controller.addError);
        final b = _lan.incomingConnections
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = () async {
          await a.cancel();
          await b.cancel();
        };
      });

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  @override
  Future<bool> isAvailable() async {
    if (_isAndroid) {
      try {
        await _ensureAndroidPermissions();
        return true;
      } catch (_) {
        return _lan.isAvailable();
      }
    }
    return _lan.isAvailable();
  }

  Future<void> _ensureAndroidPermissions() async {
    await [
      Permission.locationWhenInUse,
      Permission.nearbyWifiDevices,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ].request();
  }

  Future<void> _initAndroidIfNeeded() async {
    if (!_isAndroid || _useAndroidP2p) return;
    _host = FlutterP2pHost(
      username: _displayName.isEmpty ? null : _displayName,
    );
    _client = FlutterP2pClient(
      username: _displayName.isEmpty ? null : _displayName,
    );
    await _host!.initialize();
    await _client!.initialize();
    await _ensureAndroidPermissions();
    _useAndroidP2p = true;

    _subs.add(_host!.streamClientList().listen((clients) {
      for (final c in clients) {
        if (c.id == _localId) continue;
        final peer = Peer(
          id: c.id,
          displayName: c.username,
          transports: {TransportKind.wifi},
          addresses: {TransportKind.wifi: c.id},
          lastSeen: DateTime.now().toUtc(),
          metadata: {'p2pRole': c.isHost ? 'host' : 'client'},
        );
        if (!_discovery.isClosed) _discovery.add(peer);
      }
    }));

    _subs.add(_host!.streamReceivedTexts().listen((text) {
      _handleP2pText(text, fromHost: true);
    }));
    _subs.add(_client!.streamReceivedTexts().listen((text) {
      _handleP2pText(text, fromHost: false);
    }));
  }

  Future<void> _broadcastP2p(String msg) async {
    if (_host != null && _advertisingAsHost) {
      await _host!.broadcastText(msg);
    }
    if (_client != null) {
      try {
        await _client!.broadcastText(msg);
      } catch (_) {
        // Client may not be in a group yet.
      }
    }
  }

  bool _advertisingAsHost = false;

  void _handleP2pText(String text, {required bool fromHost}) {
    try {
      if (!text.startsWith('ZV|')) return;
      final parts = text.split('|');
      if (parts.length < 3) return;
      final peerId = parts[1];
      if (peerId == _localId) return;
      final bytes = base64.decode(parts.sublist(2).join('|'));
      final conn = _p2pLinks.putIfAbsent(peerId, () {
        final peer = Peer(
          id: peerId,
          transports: {TransportKind.wifi},
          addresses: {TransportKind.wifi: peerId},
          lastSeen: DateTime.now().toUtc(),
        );
        final link = _P2pTextConnection(
          peer: peer,
          sendText: (payload) async {
            final msg = 'ZV|$_localId|${base64.encode(payload)}';
            await _broadcastP2p(msg);
          },
        );
        link.markOpen();
        if (!_inbound.isClosed) _inbound.add(link);
        return link;
      });
      conn.deliver(Uint8List.fromList(bytes));
    } catch (_) {}
  }

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    _localId = localId;
    _displayName = displayName ?? '';

    if (_isAndroid) {
      try {
        await _initAndroidIfNeeded();
        await _host!.createGroup(advertise: true);
        _advertisingAsHost = true;
        return;
      } catch (_) {
        _useAndroidP2p = false;
        _advertisingAsHost = false;
      }
    }
    await _lan.startAdvertising(
      localId: localId,
      displayName: displayName,
      metadata: metadata,
    );
  }

  @override
  Future<void> stopAdvertising() async {
    _advertisingAsHost = false;
    if (_useAndroidP2p && _host != null) {
      try {
        await _host!.removeGroup();
      } catch (_) {}
    }
    await _lan.stopAdvertising();
  }

  @override
  Stream<Peer> discover() {
    if (_isAndroid) {
      unawaited(_startAndroidDiscovery());
    }
    _subs.add(_lan.discover().listen((p) {
      if (!_discovery.isClosed) _discovery.add(p);
    }));
    return _discovery.stream;
  }

  Future<void> _startAndroidDiscovery() async {
    try {
      await _initAndroidIfNeeded();
      await _client!.startScan((devices) {
        for (final d in devices) {
          _bleDevices[d.deviceAddress] = d;
          final peer = Peer(
            id: d.deviceAddress,
            displayName: d.deviceName,
            transports: {TransportKind.wifi},
            addresses: {TransportKind.wifi: d.deviceAddress},
            lastSeen: DateTime.now().toUtc(),
            metadata: {'p2pDiscovery': 'ble-cred'},
          );
          if (!_discovery.isClosed) _discovery.add(peer);
        }
      });
    } catch (_) {}
  }

  @override
  Future<void> stopDiscovery() async {
    if (_useAndroidP2p && _client != null) {
      try {
        await _client!.stopScan();
      } catch (_) {}
    }
    await _lan.stopDiscovery();
  }

  @override
  Future<Connection> connect(Peer peer) async {
    if (_useAndroidP2p && _client != null) {
      final addr = peer.addresses[TransportKind.wifi] ?? peer.id;
      final device = _bleDevices[addr];
      if (device != null) {
        try {
          await _client!.connectWithDevice(device);
          final conn = _p2pLinks.putIfAbsent(peer.id, () {
            final link = _P2pTextConnection(
              peer: peer,
              sendText: (payload) async {
                final msg = 'ZV|$_localId|${base64.encode(payload)}';
                await _broadcastP2p(msg);
              },
            );
            link.markOpen();
            return link;
          });
          return conn;
        } catch (_) {}
      }
    }
    return _lan.connect(peer);
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    await _lan.setPowerMode(mode);
  }

  /// Cancel LAN SoftAP timers synchronously for test teardown.
  void cancelTimersSync() => _lan.cancelTimersSync();

  @override
  Future<void> dispose() async {
    cancelTimersSync();
    await stopDiscovery();
    await stopAdvertising();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final links = List<_P2pTextConnection>.from(_p2pLinks.values);
    _p2pLinks.clear();
    for (final c in links) {
      await c.close();
    }
    try {
      await _host?.dispose();
      await _client?.dispose();
    } catch (_) {}
    await _lan.dispose();
    await _discovery.close();
    await _inbound.close();
  }
}

final class _P2pTextConnection implements Connection {
  @override
  final Peer peer;

  @override
  TransportKind get kind => TransportKind.wifi;

  final Future<void> Function(Uint8List data) sendText;
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  ConnectionState _state = ConnectionState.connecting;

  _P2pTextConnection({required this.peer, required this.sendText});

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _states.stream;

  @override
  LinkMetrics get metrics => const LinkMetrics(mtu: 1400, rttMs: 20);

  void markOpen() {
    _state = ConnectionState.open;
    if (!_states.isClosed) _states.add(_state);
  }

  void deliver(Uint8List data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('P2P connection not open');
    }
    await sendText(data);
  }

  @override
  Future<void> close() async {
    _state = ConnectionState.closed;
    if (!_states.isClosed) _states.add(_state);
    await _incoming.close();
    await _states.close();
  }
}

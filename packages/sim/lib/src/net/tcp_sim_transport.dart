import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';

import 'sim_protocol.dart';

/// [Transport] that talks to a [SimHub] over TCP (multi-process / Docker sim).
final class TcpSimTransport implements Transport {
  @override
  TransportKind get kind => TransportKind.mock;

  @override
  String get name => 'TcpSim';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 1024,
        typicalRangeMeters: 50,
      );

  final String hubHost;
  final int hubPort;
  final String localId;
  final String displayName;
  final double x;
  final double y;
  final double rangeMeters;
  final void Function(String line)? log;

  Socket? _socket;
  final SimCodec _codec = SimCodec();
  final Map<String, InMemoryConnection> _connections = {};
  final StreamController<Connection> _incoming =
      StreamController<Connection>.broadcast();
  StreamController<Peer>? _discovery;
  final Map<String, Peer> _peers = {};
  Completer<void>? _registered;
  bool _advertising = false;
  bool _discovering = false;
  Map<String, String> _metadata = const {};
  StreamSubscription<List<int>>? _sub;

  TcpSimTransport({
    required this.hubHost,
    required this.hubPort,
    required this.localId,
    this.displayName = '',
    this.x = 0,
    this.y = 0,
    this.rangeMeters = 50,
    this.log,
  });

  @override
  Stream<Connection> get incomingConnections => _incoming.stream;

  Future<void> connectToHub() async {
    if (_socket != null) return;
    _registered = Completer<void>();
    _socket = await Socket.connect(
      hubHost,
      hubPort,
      timeout: const Duration(seconds: 10),
    );
    _sub = _socket!.listen(
      _onBytes,
      onDone: _onSocketDone,
      onError: (_) => _onSocketDone(),
      cancelOnError: true,
    );
    await _send({
      'type': SimMsgType.register,
      'id': localId,
      'name': displayName.isEmpty ? localId : displayName,
      'x': x,
      'y': y,
      'range': rangeMeters,
    });
    await _registered!.future.timeout(const Duration(seconds: 10));
    _log('registered with hub $hubHost:$hubPort as $localId');
  }

  void _onBytes(List<int> data) {
    for (final msg in _codec.add(data)) {
      unawaited(_handle(msg));
    }
  }

  Future<void> _handle(Map<String, Object?> msg) async {
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case SimMsgType.registerOk:
        if (!(_registered?.isCompleted ?? true)) {
          _registered!.complete();
        }
      case SimMsgType.peer:
        final id = msg['id'] as String? ?? '';
        if (id.isEmpty || id == localId) return;
        final peer = Peer(
          id: id,
          displayName: msg['name'] as String? ?? id,
          transports: {TransportKind.mock},
          rssi: (msg['rssi'] as num?)?.toInt(),
          addresses: {TransportKind.mock: id},
          lastSeen: DateTime.now().toUtc(),
          metadata: _stringMap(msg['meta']),
        );
        _peers[id] = peer;
        if (_discovering && _discovery != null && !_discovery!.isClosed) {
          _discovery!.add(peer);
        }
      case SimMsgType.connected:
        final peerId = msg['peer'] as String? ?? '';
        if (peerId.isEmpty) return;
        final inbound = msg['inbound'] as bool? ?? false;
        final conn = _ensureConnection(
          peerId,
          name: msg['name'] as String? ?? peerId,
          rssi: (msg['rssi'] as num?)?.toInt(),
        );
        if (inbound && !_incoming.isClosed) {
          _incoming.add(conn);
        }
      case SimMsgType.data:
        final from = msg['from'] as String? ?? '';
        final b64 = msg['payload'] as String? ?? '';
        if (from.isEmpty || b64.isEmpty) return;
        final conn = _connections[from] ??
            _ensureConnection(
              from,
              name: _peers[from]?.displayName ?? from,
              rssi: _peers[from]?.rssi,
            );
        if (conn.state != ConnectionState.open) {
          conn.markOpen();
          if (!_incoming.isClosed) {
            _incoming.add(conn);
          }
        }
        conn.deliver(simB64Decode(b64));
      case SimMsgType.leave:
        final id = msg['id'] as String? ?? '';
        _peers.remove(id);
        final c = _connections.remove(id);
        await c?.close();
      case SimMsgType.error:
        _log('hub error: ${msg['message']}');
      default:
        break;
    }
  }

  InMemoryConnection _ensureConnection(
    String peerId, {
    required String name,
    int? rssi,
  }) {
    final existing = _connections[peerId];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }
    final peer = Peer(
      id: peerId,
      displayName: name,
      transports: {TransportKind.mock},
      rssi: rssi,
      addresses: {TransportKind.mock: peerId},
      lastSeen: DateTime.now().toUtc(),
    );
    final conn = InMemoryConnection(
      peer: peer,
      kind: TransportKind.mock,
      metrics: LinkMetrics(mtu: 1024, rssi: rssi ?? -50, rttMs: 5),
    );
    conn.onSend = (data) {
      unawaited(_send({
        'type': SimMsgType.data,
        'to': peerId,
        'payload': simB64Encode(Uint8List.fromList(data)),
      }));
    };
    conn.markOpen();
    _connections[peerId] = conn;
    return conn;
  }

  Map<String, String> _stringMap(Object? raw) {
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  Future<void> _send(Map<String, Object?> msg) async {
    final s = _socket;
    if (s == null) throw StateError('not connected to hub');
    s.add(SimCodec.encode(msg));
    await s.flush();
  }

  void _onSocketDone() {
    _log('hub socket closed');
    if (!(_registered?.isCompleted ?? true)) {
      _registered!
          .completeError(StateError('hub disconnected during register'));
    }
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    await connectToHub();
    _metadata = metadata;
    _advertising = true;
    await _send({
      'type': SimMsgType.advertise,
      'meta': metadata,
    });
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
  }

  @override
  Stream<Peer> discover() {
    _discovering = true;
    _discovery?.close();
    final controller = StreamController<Peer>.broadcast();
    _discovery = controller;
    // Replay known peers.
    scheduleMicrotask(() {
      for (final p in _peers.values) {
        if (!controller.isClosed) controller.add(p);
      }
    });
    // Re-advertise so hub rebroadcasts peer list.
    if (_advertising) {
      unawaited(_send({'type': SimMsgType.advertise, 'meta': _metadata}));
    }
    return controller.stream;
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    final c = _discovery;
    _discovery = null;
    if (c != null && !c.isClosed) await c.close();
  }

  @override
  Future<Connection> connect(Peer peer) async {
    await connectToHub();
    final existing = _connections[peer.id];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }
    await _send({'type': SimMsgType.connect, 'to': peer.id});
    // Wait briefly for hub connected event.
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      final c = _connections[peer.id];
      if (c != null && c.state == ConnectionState.open) return c;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // Optimistic local connection even if event raced.
    return _ensureConnection(
      peer.id,
      name: peer.displayName,
      rssi: peer.rssi,
    );
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {}

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    try {
      await _send({'type': SimMsgType.leave});
    } catch (_) {}
    await _sub?.cancel();
    await _socket?.close();
    _socket = null;
    for (final c in _connections.values) {
      await c.close();
    }
    _connections.clear();
    if (!_incoming.isClosed) await _incoming.close();
  }

  void _log(String line) {
    final msg = '[$localId] $line';
    if (log != null) {
      log!(msg);
    } else {
      stdout.writeln(msg);
    }
  }
}

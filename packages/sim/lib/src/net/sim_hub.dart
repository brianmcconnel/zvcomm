import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:core/core.dart';

import 'sim_protocol.dart';

/// Registered client on the simulated radio medium.
final class HubClient {
  final Socket socket;
  final SimCodec codec = SimCodec();
  String? id;
  String name = '';
  double x = 0;
  double y = 0;
  double range = 50;
  bool advertising = false;
  Map<String, String> metadata = const {};

  HubClient(this.socket);

  SimPoint get position => SimPoint(x, y);

  Future<void> send(Map<String, Object?> msg) async {
    try {
      socket.add(SimCodec.encode(msg));
      await socket.flush();
    } catch (_) {
      // Peer likely disconnected.
    }
  }
}

/// Central TCP hub that simulates range-limited radio links for mesh nodes.
///
/// Clients run in separate processes/containers and only exchange traffic with
/// peers inside their configured radio range (multi-hop is handled by MeshNode).
final class SimHub {
  final InternetAddress address;
  final int port;
  final double packetLoss;
  final Duration linkDelay;
  final Random _random;
  final void Function(String line)? log;

  ServerSocket? _server;
  final Set<HubClient> _clients = {};
  final Map<String, HubClient> _byId = {};

  SimHub({
    InternetAddress? address,
    this.port = 7700,
    this.packetLoss = 0,
    this.linkDelay = Duration.zero,
    Random? random,
    this.log,
  })  : address = address ?? InternetAddress.anyIPv4,
        _random = random ?? Random(42);

  int get clientCount => _byId.length;

  Future<void> start() async {
    _server = await ServerSocket.bind(address, port);
    _log('hub listening on ${address.address}:$port '
        '(loss=$packetLoss delay=${linkDelay.inMilliseconds}ms)');
    _server!.listen(_onSocket, onError: (Object e) => _log('server error: $e'));
  }

  Future<void> stop() async {
    final clients = List<HubClient>.from(_clients);
    for (final c in clients) {
      await c.socket.close();
    }
    _clients.clear();
    _byId.clear();
    await _server?.close();
    _server = null;
  }

  void _onSocket(Socket socket) {
    final client = HubClient(socket);
    _clients.add(client);
    _log('socket + ${socket.remoteAddress.address}:${socket.remotePort}');
    socket.listen(
      (data) => _onBytes(client, data),
      onDone: () => unawaited(_drop(client)),
      onError: (_) => unawaited(_drop(client)),
      cancelOnError: true,
    );
  }

  void _onBytes(HubClient client, List<int> data) {
    for (final msg in client.codec.add(data)) {
      unawaited(_handle(client, msg));
    }
  }

  Future<void> _handle(HubClient client, Map<String, Object?> msg) async {
    final type = msg['type'] as String? ?? '';
    switch (type) {
      case SimMsgType.register:
        await _register(client, msg);
      case SimMsgType.advertise:
        client.advertising = true;
        final meta = msg['meta'];
        if (meta is Map) {
          client.metadata = meta.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          );
        }
        await _broadcastPeers();
      case SimMsgType.connect:
        await _connect(client, msg['to'] as String? ?? '');
      case SimMsgType.data:
        await _data(client, msg);
      case SimMsgType.ping:
        await client.send({'type': SimMsgType.pong});
      case SimMsgType.leave:
        await _drop(client);
      default:
        await client.send({
          'type': SimMsgType.error,
          'message': 'unknown type: $type',
        });
    }
  }

  Future<void> _register(HubClient client, Map<String, Object?> msg) async {
    final id = msg['id'] as String? ?? '';
    if (id.isEmpty) {
      await client.send({
        'type': SimMsgType.error,
        'message': 'register requires id',
      });
      return;
    }
    final existing = _byId[id];
    if (existing != null && existing != client) {
      await _drop(existing);
    }
    client.id = id;
    client.name = msg['name'] as String? ?? id;
    client.x = (msg['x'] as num?)?.toDouble() ?? 0;
    client.y = (msg['y'] as num?)?.toDouble() ?? 0;
    client.range = (msg['range'] as num?)?.toDouble() ?? 50;
    _byId[id] = client;
    _log('register $id (${client.name}) @ (${client.x},${client.y}) '
        'range=${client.range}');
    await client.send({'type': SimMsgType.registerOk, 'id': id});
    await _broadcastPeers();
    _logTopology();
  }

  Future<void> _connect(HubClient from, String toId) async {
    final fromId = from.id;
    if (fromId == null || toId.isEmpty) return;
    final to = _byId[toId];
    if (to == null) {
      await from.send({
        'type': SimMsgType.error,
        'message': 'peer $toId not registered',
      });
      return;
    }
    if (!_inRange(from, to)) {
      await from.send({
        'type': SimMsgType.error,
        'message': 'peer $toId out of range',
      });
      return;
    }
    await from.send({
      'type': SimMsgType.connected,
      'peer': toId,
      'name': to.name,
      'inbound': false,
      'rssi': _rssi(from, to),
    });
    await to.send({
      'type': SimMsgType.connected,
      'peer': fromId,
      'name': from.name,
      'inbound': true,
      'rssi': _rssi(to, from),
    });
    _log('link $fromId ↔ $toId (rssi=${_rssi(from, to)})');
  }

  Future<void> _data(HubClient from, Map<String, Object?> msg) async {
    final fromId = from.id;
    if (fromId == null) return;
    final toId = msg['to'] as String?;
    final b64 = msg['payload'] as String? ?? '';
    if (b64.isEmpty || toId == null || toId.isEmpty) return;

    if (packetLoss > 0 && _random.nextDouble() < packetLoss) {
      return;
    }

    final to = _byId[toId];
    if (to == null || !_inRange(from, to)) return;

    Future<void> deliver() async {
      await to.send({
        'type': SimMsgType.data,
        'from': fromId,
        'to': toId,
        'payload': b64,
      });
    }

    if (linkDelay <= Duration.zero) {
      await deliver();
    } else {
      unawaited(Future<void>.delayed(linkDelay, deliver));
    }
  }

  Future<void> _broadcastPeers() async {
    final snap = List<HubClient>.from(_byId.values);
    for (final viewer in snap) {
      if (viewer.id == null) continue;
      for (final other in snap) {
        if (other.id == null || other.id == viewer.id) continue;
        if (!other.advertising) continue;
        if (!_inRange(viewer, other)) continue;
        await viewer.send({
          'type': SimMsgType.peer,
          'id': other.id,
          'name': other.name,
          'rssi': _rssi(viewer, other),
          'x': other.x,
          'y': other.y,
          'meta': other.metadata,
        });
      }
    }
  }

  bool _inRange(HubClient a, HubClient b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dist = sqrt(dx * dx + dy * dy);
    return dist <= min(a.range, b.range);
  }

  int _rssi(HubClient a, HubClient b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    final dist = sqrt(dx * dx + dy * dy);
    return (-20 - dist * 2).round().clamp(-100, -20);
  }

  Future<void> _drop(HubClient client) async {
    if (!_clients.remove(client)) return;
    final id = client.id;
    if (id != null) {
      _byId.remove(id);
      _log('leave $id');
      for (final other in _byId.values) {
        await other.send({'type': SimMsgType.leave, 'id': id});
      }
    }
    try {
      await client.socket.close();
    } catch (_) {}
    _logTopology();
  }

  void _logTopology() {
    final ids = _byId.keys.toList()..sort();
    if (ids.isEmpty) {
      _log('topology: (empty)');
      return;
    }
    final links = <String>[];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = _byId[ids[i]]!;
        final b = _byId[ids[j]]!;
        if (_inRange(a, b)) {
          links.add('${ids[i]}—${ids[j]}');
        }
      }
    }
    _log('topology nodes=${ids.join(",")} links=${links.join(" ")}');
  }

  void _log(String line) {
    final msg = '[hub] $line';
    if (log != null) {
      log!(msg);
    } else {
      stdout.writeln(msg);
    }
  }
}

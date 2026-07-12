import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import 'connection.dart';
import 'transport.dart';

/// Shared in-process "radio medium" so multiple [MockTransport] instances can
/// discover and message each other (tests + simulator).
final class MockMedium {
  final List<MockTransport> _nodes = [];
  final Random _random;

  /// Independent packet loss probability in \[0, 1\] applied per send.
  double packetLoss;

  /// Optional latency added before deliver (wall-clock; keep small in tests).
  Duration linkDelay;

  MockMedium({
    Random? random,
    this.packetLoss = 0,
    this.linkDelay = Duration.zero,
  }) : _random = random ?? Random(42);

  Random get random => _random;

  void register(MockTransport transport) {
    if (!_nodes.contains(transport)) {
      _nodes.add(transport);
    }
  }

  void unregister(MockTransport transport) {
    _nodes.remove(transport);
  }

  Iterable<MockTransport> others(MockTransport self) =>
      _nodes.where((n) => n != self && n._advertising);

  /// Simulated RSSI based on optional positions; defaults to a fixed range.
  int rssiBetween(MockTransport a, MockTransport b) {
    if (a.position == null || b.position == null) {
      return -40 - _random.nextInt(30);
    }
    final dx = a.position!.x - b.position!.x;
    final dy = a.position!.y - b.position!.y;
    final dist = sqrt(dx * dx + dy * dy);
    // Rough free-space style mapping for simulation UX only.
    final rssi = (-20 - dist * 2).round().clamp(-100, -20);
    return rssi;
  }

  bool inRange(MockTransport a, MockTransport b) {
    if (a.position == null || b.position == null) return true;
    final dx = a.position!.x - b.position!.x;
    final dy = a.position!.y - b.position!.y;
    final dist = sqrt(dx * dx + dy * dy);
    final maxRange = min(a.rangeMeters, b.rangeMeters);
    return dist <= maxRange;
  }

  /// Deliver [data] to [to] subject to loss / delay models.
  void deliver(InMemoryConnection to, Uint8List data) {
    if (packetLoss > 0 && _random.nextDouble() < packetLoss) {
      return;
    }
    if (linkDelay <= Duration.zero) {
      to.deliver(data);
      return;
    }
    Future<void>.delayed(linkDelay, () {
      if (to.state == ConnectionState.open) {
        to.deliver(data);
      }
    });
  }
}

/// 2D position for simple range simulation.
final class SimPoint {
  final double x;
  final double y;
  const SimPoint(this.x, this.y);
}

/// Fully permissive in-memory transport for unit tests and Phase 0 UI demos.
final class MockTransport implements Transport {
  @override
  TransportKind get kind => TransportKind.mock;

  @override
  String get name => 'Mock';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 1024,
        typicalRangeMeters: 50,
      );

  final MockMedium medium;
  final String localId;
  final String displayName;
  double rangeMeters;
  SimPoint? position;

  bool _advertising = false;
  bool _discovering = false;
  Map<String, String> _metadata = const {};
  StreamController<Peer>? _discoveryController;
  Timer? _scanTimer;
  final Map<String, InMemoryConnection> _connections = {};
  final StreamController<Connection> _incomingConnections =
      StreamController<Connection>.broadcast();
  TransportPowerMode _powerMode = TransportPowerMode.balanced;

  MockTransport({
    required this.medium,
    required this.localId,
    this.displayName = '',
    this.position,
    this.rangeMeters = 50,
  }) {
    medium.register(this);
  }

  @override
  Stream<Connection> get incomingConnections => _incomingConnections.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    _metadata = metadata;
    _advertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
  }

  @override
  Stream<Peer> discover() {
    _discovering = true;
    _discoveryController?.close();
    final controller = StreamController<Peer>.broadcast(
      onCancel: () {
        // Keep scanning if other listeners remain; simple Phase 0 behavior:
        // stop when the last listener cancels.
        if (!(_discoveryController?.hasListener ?? true)) {
          unawaited(stopDiscovery());
        }
      },
    );
    _discoveryController = controller;

    final interval = switch (_powerMode) {
      TransportPowerMode.performance => const Duration(milliseconds: 200),
      TransportPowerMode.balanced => const Duration(milliseconds: 500),
      TransportPowerMode.powerSaver => const Duration(seconds: 2),
      TransportPowerMode.ultraLow => const Duration(seconds: 5),
    };

    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(interval, (_) => _emitSightings());
    // Immediate first scan.
    scheduleMicrotask(_emitSightings);

    return controller.stream;
  }

  void _emitSightings() {
    final controller = _discoveryController;
    if (!_discovering || controller == null || controller.isClosed) return;

    for (final other in medium.others(this)) {
      if (!medium.inRange(this, other)) continue;
      final meta = Map<String, String>.from(other._metadata);
      // Expose sim coordinates for peer map (local mesh plane, meters).
      final pos = other.position;
      if (pos != null) {
        meta['x'] = pos.x.toStringAsFixed(3);
        meta['y'] = pos.y.toStringAsFixed(3);
      }
      final peer = Peer(
        id: other.localId,
        displayName: other.displayName,
        transports: {TransportKind.mock},
        rssi: medium.rssiBetween(this, other),
        addresses: {TransportKind.mock: other.localId},
        lastSeen: DateTime.now().toUtc(),
        metadata: meta,
      );
      controller.add(peer);
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    final controller = _discoveryController;
    _discoveryController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
  }

  /// Synchronously cancel discovery timers (for widget-test teardown).
  void cancelDiscoverySync() {
    _discovering = false;
    _scanTimer?.cancel();
    _scanTimer = null;
  }

  @override
  Future<Connection> connect(Peer peer) async {
    final existing = _connections[peer.id];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }

    final remote = medium._nodes.cast<MockTransport?>().firstWhere(
          (n) => n?.localId == peer.id,
          orElse: () => null,
        );
    if (remote == null) {
      throw StateError('Mock peer ${peer.id} is not on the medium');
    }
    if (!medium.inRange(this, remote)) {
      throw StateError('Mock peer ${peer.id} is out of range');
    }

    final localConn = InMemoryConnection(
      peer: peer,
      kind: TransportKind.mock,
      metrics: LinkMetrics(
        mtu: 1024,
        rssi: medium.rssiBetween(this, remote),
        rttMs: 2,
      ),
    );

    final remotePeer = Peer(
      id: localId,
      displayName: displayName,
      transports: {TransportKind.mock},
      lastSeen: DateTime.now().toUtc(),
      addresses: {TransportKind.mock: localId},
    );

    final remoteConn = InMemoryConnection(
      peer: remotePeer,
      kind: TransportKind.mock,
      metrics: LinkMetrics(
        mtu: 1024,
        rssi: medium.rssiBetween(remote, this),
        rttMs: 2,
      ),
    );

    localConn.onSend =
        (data) => medium.deliver(remoteConn, Uint8List.fromList(data));
    remoteConn.onSend =
        (data) => medium.deliver(localConn, Uint8List.fromList(data));

    localConn.markOpen();
    remoteConn.markOpen();

    _connections[peer.id] = localConn;
    remote._connections[localId] = remoteConn;

    // Notify the remote mesh stack of the accepted inbound connection.
    if (!remote._incomingConnections.isClosed) {
      remote._incomingConnections.add(remoteConn);
    }

    return localConn;
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    _powerMode = mode;
    if (_discovering) {
      // Restart discovery with new interval.
      final listeners = _discoveryController;
      if (listeners != null && !listeners.isClosed) {
        discover();
      }
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    for (final c in _connections.values) {
      await c.close();
    }
    _connections.clear();
    await _incomingConnections.close();
    medium.unregister(this);
  }
}

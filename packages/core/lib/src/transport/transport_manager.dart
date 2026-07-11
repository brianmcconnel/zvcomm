import 'dart:async';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import 'connection.dart';
import 'transport.dart';

/// Aggregates multiple [Transport] backends into one discovery / connect API.
///
/// Supports Phase 5 hot-plug via [register] / [unregister].
final class TransportManager {
  final List<Transport> _transports = [];
  final Map<String, Peer> _peers = {};
  final StreamController<Peer> _peerUpdates =
      StreamController<Peer>.broadcast();
  final StreamController<Connection> _incomingConnections =
      StreamController<Connection>.broadcast();

  /// Per-transport discovery + inbound subscriptions for hot-unplug.
  final Map<Transport, List<StreamSubscription<dynamic>>> _transportSubs = {};

  String? _localId;
  String? _displayName;
  Map<String, String> _metadata = const {};
  bool _advertising = false;
  bool _discovering = false;
  TransportPowerMode _powerMode = TransportPowerMode.balanced;

  TransportManager([Iterable<Transport> transports = const []]) {
    _transports.addAll(transports);
  }

  List<Transport> get transports => List.unmodifiable(_transports);

  /// Snapshot of last-seen peers (by id).
  Map<String, Peer> get peers => Map.unmodifiable(_peers);

  /// Live peer sightings merged across all transports.
  Stream<Peer> get peerUpdates => _peerUpdates.stream;

  /// Inbound connections from any backend.
  Stream<Connection> get incomingConnections => _incomingConnections.stream;

  bool get isDiscovering => _discovering;

  Transport? transportOf(TransportKind kind) {
    for (final t in _transports) {
      if (t.kind == kind) return t;
    }
    return null;
  }

  Transport? transportWhere(bool Function(Transport t) test) {
    for (final t in _transports) {
      if (test(t)) return t;
    }
    return null;
  }

  /// Hot-add a transport. If discovery/advertising is active, wires it up.
  Future<void> register(Transport transport) async {
    if (_transports.contains(transport)) return;
    _transports.add(transport);
    await transport.setPowerMode(_powerMode);

    _wireInbound(transport);

    if (_advertising && _localId != null) {
      if (transport.capabilities.canAdvertise &&
          await transport.isAvailable()) {
        await transport.startAdvertising(
          localId: _localId!,
          displayName: _displayName,
          metadata: _metadata,
        );
      }
    }

    if (_discovering) {
      await _startDiscoveryOn(transport);
    }
  }

  /// Remove and dispose a transport instance.
  Future<void> unregister(Transport transport) async {
    if (!_transports.remove(transport)) return;
    await _teardownTransport(transport);
    await transport.dispose();
  }

  /// Unregister the first transport matching [kind].
  Future<bool> unregisterKind(TransportKind kind) async {
    final t = transportOf(kind);
    if (t == null) return false;
    await unregister(t);
    return true;
  }

  Future<void> _teardownTransport(Transport transport) async {
    _inboundWired.remove(transport);
    final subs = _transportSubs.remove(transport) ?? const [];
    for (final s in subs) {
      await s.cancel();
    }
    try {
      await transport.stopDiscovery();
    } catch (_) {}
    try {
      await transport.stopAdvertising();
    } catch (_) {}
  }

  final Set<Transport> _inboundWired = {};

  void _wireInbound(Transport t) {
    if (_inboundWired.contains(t)) return;
    _inboundWired.add(t);
    final list = _transportSubs.putIfAbsent(t, () => []);
    final sub = t.incomingConnections.listen((conn) {
      if (!_incomingConnections.isClosed) {
        _incomingConnections.add(conn);
      }
    });
    list.add(sub);
  }

  /// Subscribe to inbound connections on all transports (idempotent).
  void listenForInboundConnections() {
    for (final t in _transports) {
      _wireInbound(t);
    }
  }

  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    _localId = localId;
    _displayName = displayName;
    _metadata = metadata;
    _advertising = true;
    for (final t in List<Transport>.from(_transports)) {
      if (!t.capabilities.canAdvertise) continue;
      if (!await t.isAvailable()) continue;
      await t.startAdvertising(
        localId: localId,
        displayName: displayName,
        metadata: metadata,
      );
    }
  }

  Future<void> stopAdvertising() async {
    _advertising = false;
    for (final t in List<Transport>.from(_transports)) {
      await t.stopAdvertising();
    }
  }

  /// Begin discovery on all available transports.
  Future<void> startDiscovery() async {
    if (_discovering) return;
    _discovering = true;
    listenForInboundConnections();

    for (final t in List<Transport>.from(_transports)) {
      await _startDiscoveryOn(t);
    }
  }

  Future<void> _startDiscoveryOn(Transport t) async {
    final available = await t.isAvailable();
    if (!available || !t.capabilities.canDiscover) return;
    final list = _transportSubs.putIfAbsent(t, () => []);
    final sub = t.discover().listen(_onPeer);
    list.add(sub);
  }

  void _onPeer(Peer peer) {
    final existing = _peers[peer.id];
    if (existing == null) {
      _peers[peer.id] = peer;
      if (!_peerUpdates.isClosed) _peerUpdates.add(peer);
      return;
    }

    final merged = existing.copyWith(
      displayName:
          peer.displayName.isNotEmpty ? peer.displayName : existing.displayName,
      transports: {...existing.transports, ...peer.transports},
      rssi: peer.rssi ?? existing.rssi,
      addresses: {...existing.addresses, ...peer.addresses},
      lastSeen: peer.lastSeen,
      metadata: {...existing.metadata, ...peer.metadata},
    );
    _peers[peer.id] = merged;
    if (!_peerUpdates.isClosed) _peerUpdates.add(merged);
  }

  Future<void> stopDiscovery() async {
    _discovering = false;
    for (final t in List<Transport>.from(_transports)) {
      await t.stopDiscovery();
    }
    for (final entry in _transportSubs.entries) {
      // Keep inbound subs; only cancel discovery by full cancel+rewire inbound
      for (final s in entry.value) {
        await s.cancel();
      }
      entry.value.clear();
    }
    // Re-wire inbound only so connections still work while not discovering.
    for (final t in _transports) {
      _wireInbound(t);
    }
  }

  /// Connect using preferred transport, with optional [preferred] override.
  Future<Connection> connect(
    Peer peer, {
    TransportKind? preferred,
  }) async {
    final kinds = preferred != null
        ? [preferred, ...peer.transports.where((k) => k != preferred)]
        : _sortedKinds(peer);

    Object? lastError;
    for (final kind in kinds) {
      final t = transportOf(kind);
      if (t == null) continue;
      try {
        return await t.connect(peer);
      } catch (e) {
        lastError = e;
      }
    }
    throw StateError(
      'Failed to connect to ${peer.id}: ${lastError ?? "no transport"}',
    );
  }

  List<TransportKind> _sortedKinds(Peer peer) {
    final list = peer.transports.toList()
      ..sort((a, b) => b.bandwidthRank.compareTo(a.bandwidthRank));
    return list;
  }

  Future<void> setPowerMode(TransportPowerMode mode) async {
    _powerMode = mode;
    for (final t in List<Transport>.from(_transports)) {
      await t.setPowerMode(mode);
    }
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    for (final t in List<Transport>.from(_transports)) {
      final subs = _transportSubs.remove(t) ?? const [];
      for (final s in subs) {
        await s.cancel();
      }
      await t.dispose();
    }
    _transports.clear();
    await _peerUpdates.close();
    await _incomingConnections.close();
    _peers.clear();
  }
}

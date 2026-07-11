import 'dart:async';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import 'connection.dart';
import 'transport.dart';

/// Aggregates multiple [Transport] backends into one discovery / connect API.
final class TransportManager {
  final List<Transport> _transports;
  final Map<String, Peer> _peers = {};
  final StreamController<Peer> _peerUpdates =
      StreamController<Peer>.broadcast();
  final StreamController<Connection> _incomingConnections =
      StreamController<Connection>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _discovering = false;
  bool _listeningInbound = false;

  TransportManager(Iterable<Transport> transports)
      : _transports = List.unmodifiable(transports);

  List<Transport> get transports => _transports;

  /// Snapshot of last-seen peers (by id).
  Map<String, Peer> get peers => Map.unmodifiable(_peers);

  /// Live peer sightings merged across all transports.
  Stream<Peer> get peerUpdates => _peerUpdates.stream;

  /// Inbound connections from any backend.
  Stream<Connection> get incomingConnections => _incomingConnections.stream;

  Transport? transportOf(TransportKind kind) {
    for (final t in _transports) {
      if (t.kind == kind) return t;
    }
    return null;
  }

  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    for (final t in _transports) {
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
    for (final t in _transports) {
      await t.stopAdvertising();
    }
  }

  /// Subscribe to inbound connections on all transports (safe to call once).
  void listenForInboundConnections() {
    if (_listeningInbound) return;
    _listeningInbound = true;
    for (final t in _transports) {
      final sub = t.incomingConnections.listen((conn) {
        if (!_incomingConnections.isClosed) {
          _incomingConnections.add(conn);
        }
      });
      _subs.add(sub);
    }
  }

  /// Begin discovery on all available transports.
  Future<void> startDiscovery() async {
    if (_discovering) return;
    _discovering = true;
    listenForInboundConnections();

    for (final t in _transports) {
      final available = await t.isAvailable();
      if (!available || !t.capabilities.canDiscover) continue;
      final sub = t.discover().listen(_onPeer);
      _subs.add(sub);
    }
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
    // Cancel transport scans/timers before awaiting subscription cleanup.
    for (final t in _transports) {
      await t.stopDiscovery();
    }
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _listeningInbound = false;
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
    for (final t in _transports) {
      await t.setPowerMode(mode);
    }
  }

  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    for (final t in _transports) {
      await t.dispose();
    }
    await _peerUpdates.close();
    await _incomingConnections.close();
    _peers.clear();
  }
}

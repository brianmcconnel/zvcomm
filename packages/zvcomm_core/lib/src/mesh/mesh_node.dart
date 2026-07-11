import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/message.dart';
import '../models/peer.dart';
import '../transport/connection.dart';
import '../transport/transport_manager.dart';
import 'flood_router.dart';
import 'mesh_packet.dart';

/// Minimal mesh participant: discovery via [TransportManager], flood routing,
/// and local message delivery.
///
/// Phase 0: single-hop + multi-hop flooding skeleton without encryption.
final class MeshNode {
  final String localId;
  final String displayName;
  final TransportManager transports;
  final FloodRouter router;

  final StreamController<MeshMessage> _inbound =
      StreamController<MeshMessage>.broadcast();
  final Map<String, Connection> _links = {};
  final List<StreamSubscription<dynamic>> _subs = [];
  int _seq = 0;
  final Random _random;

  MeshNode({
    required this.localId,
    this.displayName = '',
    required this.transports,
    Random? random,
  })  : _random = random ?? Random.secure(),
        router = FloodRouter(localId: localId);

  /// Application messages delivered to this node.
  Stream<MeshMessage> get messages => _inbound.stream;

  Map<String, Peer> get peers => transports.peers;

  Stream<Peer> get peerUpdates => transports.peerUpdates;

  Future<void> start() async {
    transports.listenForInboundConnections();
    _subs.add(transports.incomingConnections.listen(_attachLink));
    await transports.startAdvertising(
      localId: localId,
      displayName: displayName,
      metadata: {'mesh': 'v1'},
    );
    await transports.startDiscovery();
  }

  Future<void> stop() async {
    // Stop radios first so discovery timers are cancelled before async cleanup.
    await transports.stopDiscovery();
    await transports.stopAdvertising();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    for (final c in _links.values) {
      await c.close();
    }
    _links.clear();
  }

  Future<void> dispose() async {
    await stop();
    await transports.dispose();
    await _inbound.close();
  }

  /// Ensure a link exists to [peer] and attach receive handling.
  Future<Connection> ensureLink(Peer peer) async {
    final existing = _links[peer.id];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }
    final conn = await transports.connect(peer);
    _attachLink(conn);
    return conn;
  }

  void _attachLink(Connection conn) {
    final peerId = conn.peer.id;
    final existing = _links[peerId];
    if (existing != null &&
        identical(existing, conn) &&
        existing.state == ConnectionState.open) {
      return;
    }
    _links[peerId] = conn;
    _subs.add(
      conn.incoming.listen((data) => _onFrame(data, from: peerId)),
    );
  }

  /// Send a chat/text message (broadcast if [to] is null).
  Future<void> sendChat(String text, {String? to}) async {
    final payload = Uint8List.fromList(utf8.encode(text));
    await send(
      MeshMessage(
        id: _newId(),
        sourceId: localId,
        destinationId: to,
        kind: MessageKind.chat,
        payload: payload,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  /// Originating send: encapsulate and flood/forward.
  Future<void> send(MeshMessage message) async {
    final packet = MeshPacket(
      messageId: message.id,
      sourceId: message.sourceId ?? localId,
      destinationId: message.destinationId,
      kind: message.kind,
      hopLimit: message.hopLimit,
      sequence: ++_seq,
      payload: message.payload,
    );
    // Originator has "seen" it.
    router.deduper.observe(packet.dedupKey);
    await _broadcastPacket(packet, exceptPeerId: null);
  }

  Future<void> _broadcastPacket(
    MeshPacket packet, {
    required String? exceptPeerId,
  }) async {
    final encoded = packet.encode();
    // Connect to currently known peers if needed.
    for (final peer in peers.values) {
      if (peer.id == localId) continue;
      if (peer.id == exceptPeerId) continue;
      try {
        final conn = await ensureLink(peer);
        await conn.send(encoded);
      } catch (_) {
        // Best-effort flooding; individual link failures are ignored.
      }
    }
  }

  void _onFrame(Uint8List data, {required String from}) {
    final MeshPacket packet;
    try {
      packet = MeshPacket.decode(data);
    } catch (_) {
      return;
    }

    final decision = router.decide(packet);
    if (decision.duplicate) return;

    if (decision.deliverLocally) {
      final msg = MeshMessage(
        id: packet.messageId,
        sourceId: packet.sourceId,
        destinationId: packet.destinationId,
        kind: packet.kind,
        payload: packet.payload,
        timestamp: DateTime.now().toUtc(),
        hopLimit: packet.hopLimit,
      );
      if (!_inbound.isClosed) {
        _inbound.add(msg);
      }
    }

    if (decision.shouldForward && decision.forwardPacket != null) {
      unawaited(
        _broadcastPacket(decision.forwardPacket!, exceptPeerId: from),
      );
    }
  }

  String _newId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

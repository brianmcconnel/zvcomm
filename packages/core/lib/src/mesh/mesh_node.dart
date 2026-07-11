import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/message.dart';
import '../models/peer.dart';
import '../transport/connection.dart';
import '../transport/transport_manager.dart';
import 'flood_router.dart';
import 'mesh_config.dart';
import 'mesh_packet.dart';
import 'mesh_stats.dart';
import 'presence.dart';
import 'route_table.dart';

/// Mesh participant: discovery, adaptive multi-hop routing, presence, stats.
///
/// Phase 2: bloom-backed dedup, route table unicast, presence heartbeats.
final class MeshNode {
  final String localId;
  final String displayName;
  final TransportManager transports;
  final MeshConfig config;
  final FloodRouter router;
  final RouteTable routes;
  final PresenceTable presence;
  final MeshStats stats = MeshStats();

  final StreamController<MeshMessage> _inbound =
      StreamController<MeshMessage>.broadcast();
  final StreamController<PresenceInfo> _presenceUpdates =
      StreamController<PresenceInfo>.broadcast();

  final Map<String, Connection> _links = {};
  final List<StreamSubscription<dynamic>> _subs = [];
  int _seq = 0;
  int _presenceSeq = 0;
  Timer? _presenceTimer;
  final Random _random;

  MeshNode({
    required this.localId,
    this.displayName = '',
    required this.transports,
    MeshConfig? config,
    Random? random,
  })  : config = config ?? MeshConfig.defaults,
        _random = random ?? Random.secure(),
        router = FloodRouter.fromConfig(
          localId,
          config ?? MeshConfig.defaults,
        ),
        routes = RouteTable(),
        presence = PresenceTable(
          ttl: (config ?? MeshConfig.defaults).presenceTtl,
        );

  /// Application messages delivered to this node (excludes pure presence).
  Stream<MeshMessage> get messages => _inbound.stream;

  /// Live presence advertisements from the mesh.
  Stream<PresenceInfo> get presenceUpdates => _presenceUpdates.stream;

  Map<String, Peer> get peers => transports.peers;

  Stream<Peer> get peerUpdates => transports.peerUpdates;

  /// Open links by peer id.
  Map<String, Connection> get links => Map.unmodifiable(_links);

  Future<void> start() async {
    transports.listenForInboundConnections();
    _subs.add(transports.incomingConnections.listen(_attachLink));
    await transports.startAdvertising(
      localId: localId,
      displayName: displayName,
      metadata: {'mesh': 'v2', 'presence': '1'},
    );
    await transports.startDiscovery();
    _startPresence();
  }

  Duration _presenceInterval = Duration.zero;
  bool _background = false;

  void _startPresence() {
    _presenceInterval = config.presenceInterval;
    _restartPresenceTimer();
    unawaited(sendPresence());
  }

  void _restartPresenceTimer() {
    _presenceTimer?.cancel();
    final base = _presenceInterval;
    if (base <= Duration.zero) return;
    final interval = _background
        ? Duration(
            microseconds: base.inMicroseconds * config.backgroundPresenceFactor,
          )
        : base;
    _presenceTimer = Timer.periodic(interval, (_) {
      unawaited(sendPresence());
    });
  }

  /// Stretch presence / conserve energy when the app is backgrounded.
  void setBackgroundMode(bool background) {
    if (_background == background) return;
    _background = background;
    _restartPresenceTimer();
  }

  Future<void> stop() async {
    _presenceTimer?.cancel();
    _presenceTimer = null;
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
    await _presenceUpdates.close();
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
    // Direct neighbor is 1 hop.
    routes.learn(
      destinationId: peerId,
      nextHopId: peerId,
      hopCount: 1,
      rssi: conn.peer.rssi ?? conn.metrics.rssi,
    );
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
        hopLimit: config.defaultHopLimit,
      ),
    );
  }

  /// Originate a presence heartbeat.
  Future<void> sendPresence() async {
    _presenceSeq++;
    final payload = PresenceCodec.encode(
      peerId: localId,
      displayName: displayName,
      sequence: _presenceSeq,
      metadata: const {'mesh': 'v2'},
    );
    stats.presenceSent++;
    await send(
      MeshMessage(
        id: _newId(),
        sourceId: localId,
        destinationId: null,
        kind: MessageKind.presence,
        payload: payload,
        timestamp: DateTime.now().toUtc(),
        hopLimit: config.defaultHopLimit,
      ),
    );
  }

  /// Originating send: encapsulate and route/flood.
  Future<void> send(MeshMessage message) async {
    final hopLimit =
        message.hopLimit > 0 ? message.hopLimit : config.defaultHopLimit;
    final packet = MeshPacket(
      messageId: message.id,
      sourceId: message.sourceId ?? localId,
      destinationId: message.destinationId,
      kind: message.kind,
      hopLimit: hopLimit,
      sequence: ++_seq,
      payload: message.payload,
    );
    router.deduper.observe(packet.dedupKey);
    stats.originated++;
    await _egress(packet, exceptPeerId: null, originating: true);
  }

  Future<void> _egress(
    MeshPacket packet, {
    required String? exceptPeerId,
    bool originating = false,
  }) async {
    final encoded = packet.encode();

    // Adaptive unicast: single next hop when destination known.
    if (config.adaptiveRouting &&
        !packet.isBroadcast &&
        packet.destinationId != null) {
      final dest = packet.destinationId!;
      // Direct neighbor?
      final direct = peers[dest];
      if (direct != null && direct.id != exceptPeerId) {
        if (await _trySend(direct, encoded)) {
          stats.unicastRouted++;
          if (!originating) stats.forwarded++;
          return;
        }
      }
      final route = routes.lookup(dest);
      if (route != null && route.nextHopId != exceptPeerId) {
        final hopPeer = peers[route.nextHopId];
        if (hopPeer != null && await _trySend(hopPeer, encoded)) {
          stats.unicastRouted++;
          if (!originating) stats.forwarded++;
          return;
        }
      }
    }

    // Managed flood ordered by link quality.
    final candidates = peers.values.where((p) {
      if (p.id == localId) return false;
      if (p.id == exceptPeerId) return false;
      return true;
    }).toList()
      ..sort((a, b) => scoreNeighbor(b).compareTo(scoreNeighbor(a)));

    var sent = 0;
    for (final peer in candidates) {
      if (await _trySend(peer, encoded)) sent++;
    }
    if (sent > 0) {
      stats.flooded++;
      if (!originating) stats.forwarded++;
    }
  }

  Future<bool> _trySend(Peer peer, Uint8List encoded) async {
    try {
      final conn = await ensureLink(peer);
      await conn.send(encoded);
      return true;
    } catch (_) {
      stats.sendFailures++;
      return false;
    }
  }

  void _onFrame(Uint8List data, {required String from}) {
    final MeshPacket packet;
    try {
      packet = MeshPacket.decode(data);
    } catch (_) {
      return;
    }

    // Learn reverse path toward source via ingress neighbor.
    final neighbor = peers[from];
    routes.learnFromIngress(
      sourceId: packet.sourceId,
      fromNeighborId: from,
      packetHopLimitRemaining: packet.hopLimit,
      originalHopLimit: config.routeLearningBaseHopLimit,
      rssi: neighbor?.rssi,
    );
    // If unicast to someone else, also remember destination might be past us —
    // not enough info without path vector; skip.

    final decision = router.decide(packet);
    if (decision.duplicate) {
      stats.duplicatesDropped++;
      return;
    }
    if (decision.ttlExpired) {
      stats.ttlExpired++;
    }

    if (decision.deliverLocally) {
      if (packet.kind == MessageKind.presence) {
        final info = PresenceCodec.decode(packet.payload);
        if (info != null && info.peerId != localId) {
          if (presence.observe(info)) {
            stats.presenceReceived++;
            if (!_presenceUpdates.isClosed) {
              _presenceUpdates.add(info);
            }
          }
        }
      } else {
        final msg = MeshMessage(
          id: packet.messageId,
          sourceId: packet.sourceId,
          destinationId: packet.destinationId,
          kind: packet.kind,
          payload: packet.payload,
          timestamp: DateTime.now().toUtc(),
          hopLimit: packet.hopLimit,
        );
        stats.delivered++;
        if (!_inbound.isClosed) {
          _inbound.add(msg);
        }
      }
    }

    if (decision.shouldForward && decision.forwardPacket != null) {
      unawaited(
        _egress(
          decision.forwardPacket!,
          exceptPeerId: from,
          originating: false,
        ),
      );
    }
  }

  String _newId() {
    final bytes = List<int>.generate(8, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

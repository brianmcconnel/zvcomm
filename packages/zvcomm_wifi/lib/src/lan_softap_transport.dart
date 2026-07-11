import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:zvcomm_core/zvcomm_core.dart';

/// Desktop SoftAP / LAN fallback: UDP discovery + TCP framed mesh links.
///
/// Used when Wi-Fi Direct is unavailable (Linux/macOS/Windows development).
/// Not a true SoftAP radio stack — it binds a TCP server and announces via
/// UDP broadcast so peers on the same L2/L3 segment can mesh.
final class LanSoftApTransport implements Transport {
  final StreamController<Peer> _discovery =
      StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();

  final Map<String, _LanConnection> _links = {};
  final Map<String, _DiscoveredLanPeer> _seen = {};

  String _localId = '';
  String _displayName = '';
  bool _advertising = false;
  bool _discovering = false;
  TransportPowerMode _powerMode = TransportPowerMode.balanced;

  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _announceTimer;
  StreamSubscription<RawSocketEvent>? _udpSub;
  final List<StreamSubscription<Socket>> _serverSubs = [];
  int _tcpPort = 0;

  int get tcpPort => _tcpPort == 0 ? ZvcommProtocol.lanTcpPort : _tcpPort;
  int get udpPort => ZvcommProtocol.lanUdpPort;

  @override
  TransportKind get kind => TransportKind.wifi;

  @override
  String get name => 'LAN SoftAP fallback';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 1400,
        typicalRangeMeters: 50,
      );

  @override
  Stream<Connection> get incomingConnections => _inbound.stream;

  @override
  Future<bool> isAvailable() async {
    // Always available for desktop/integration tests using loopback.
    return true;
  }

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    _localId = localId;
    _displayName = displayName ?? '';
    _advertising = true;
    // Ephemeral port so multiple nodes can run in one process (tests / desktop).
    _server ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _tcpPort = _server!.port;
    _serverSubs.add(_server!.listen(_onInboundSocket));
    await _ensureUdp();
    _restartAnnounceTimer();
  }

  @override
  Future<void> stopAdvertising() async {
    _advertising = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    for (final s in _serverSubs) {
      await s.cancel();
    }
    _serverSubs.clear();
    await _server?.close();
    _server = null;
  }

  @override
  Stream<Peer> discover() {
    _discovering = true;
    unawaited(_ensureUdp());
    return _discovery.stream;
  }

  Future<void> _ensureUdp() async {
    if (_udp != null) return;
    // Shared UDP discovery port; reuse so multiple in-process nodes work.
    try {
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        udpPort,
        reuseAddress: true,
        reusePort: true,
      );
    } catch (_) {
      // Fallback without reusePort (some platforms).
      _udp = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0,
        reuseAddress: true,
      );
    }
    _udp!.broadcastEnabled = true;
    _udpSub = _udp!.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = _udp!.receive();
      if (dg == null) return;
      _onUdp(dg);
    });
  }

  void _restartAnnounceTimer() {
    _announceTimer?.cancel();
    final interval = switch (_powerMode) {
      TransportPowerMode.performance => const Duration(milliseconds: 400),
      TransportPowerMode.balanced => const Duration(seconds: 1),
      TransportPowerMode.powerSaver => const Duration(seconds: 3),
      TransportPowerMode.ultraLow => const Duration(seconds: 8),
    };
    _announceTimer = Timer.periodic(interval, (_) => _announce());
    _announce();
  }

  void _announce() {
    if (!_advertising || _udp == null || _localId.isEmpty) return;
    final payload = utf8.encode(
      '${ZvcommProtocol.lanMagic}|$_localId|$_displayName|$tcpPort',
    );
    try {
      _udp!.send(
        payload,
        InternetAddress('255.255.255.255'),
        udpPort,
      );
    } catch (_) {}
  }

  void _onUdp(Datagram dg) {
    if (!_discovering && !_advertising) return;
    try {
      final text = utf8.decode(dg.data);
      final parts = text.split('|');
      if (parts.length < 4 || parts[0] != ZvcommProtocol.lanMagic) return;
      final id = parts[1];
      if (id.isEmpty || id == _localId) return;
      final name = parts[2];
      final port = int.tryParse(parts[3]) ?? tcpPort;
      final host = dg.address.address;
      _seen[id] = _DiscoveredLanPeer(id: id, name: name, host: host, port: port);
      final peer = Peer(
        id: id,
        displayName: name,
        transports: {TransportKind.wifi},
        addresses: {TransportKind.wifi: '$host:$port'},
        lastSeen: DateTime.now().toUtc(),
        metadata: {'lanHost': host, 'lanPort': '$port'},
      );
      if (!_discovery.isClosed) {
        _discovery.add(peer);
      }
    } catch (_) {}
  }

  void _onInboundSocket(Socket socket) {
    final remote =
        '${socket.remoteAddress.address}:${socket.remotePort}';
    final peer = Peer(
      id: remote,
      displayName: '',
      transports: {TransportKind.wifi},
      addresses: {TransportKind.wifi: remote},
      lastSeen: DateTime.now().toUtc(),
    );
    final conn = _LanConnection(
      peer: peer,
      socket: socket,
      onClosed: () => _links.remove(remote),
    );
    conn.markOpen();
    _links[remote] = conn;
    if (!_inbound.isClosed) {
      _inbound.add(conn);
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
  }

  @override
  Future<Connection> connect(Peer peer) async {
    final address = peer.addresses[TransportKind.wifi] ?? peer.id;
    final existing = _links[address];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }

    final cached = _seen[peer.id];
    String host;
    int port;
    if (cached != null) {
      host = cached.host;
      port = cached.port;
    } else if (address.contains(':')) {
      final idx = address.lastIndexOf(':');
      host = address.substring(0, idx);
      port = int.tryParse(address.substring(idx + 1)) ?? tcpPort;
    } else {
      throw StateError('LAN peer address unknown for ${peer.id}');
    }

    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 5),
    );
    final key = '$host:$port';
    final conn = _LanConnection(
      peer: peer.copyWith(
        transports: {...peer.transports, TransportKind.wifi},
        addresses: {...peer.addresses, TransportKind.wifi: key},
      ),
      socket: socket,
      onClosed: () => _links.remove(key),
    );
    conn.markOpen();
    _links[key] = conn;
    return conn;
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    _powerMode = mode;
    if (_advertising) _restartAnnounceTimer();
  }

  /// Cancel announce timers synchronously (Flutter widget-test teardown).
  void cancelTimersSync() {
    _announceTimer?.cancel();
    _announceTimer = null;
    _discovering = false;
    _advertising = false;
  }

  @override
  Future<void> dispose() async {
    cancelTimersSync();
    await stopDiscovery();
    await stopAdvertising();
    final links = List<_LanConnection>.from(_links.values);
    _links.clear();
    for (final c in links) {
      await c.close();
    }
    await _udpSub?.cancel();
    _udp?.close();
    _udp = null;
    await _discovery.close();
    await _inbound.close();
  }
}

final class _DiscoveredLanPeer {
  final String id;
  final String name;
  final String host;
  final int port;
  _DiscoveredLanPeer({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
  });
}

final class _LanConnection implements Connection {
  @override
  final Peer peer;

  @override
  TransportKind get kind => TransportKind.wifi;

  final Socket socket;
  final void Function() onClosed;
  final StreamFrameCodec _codec = StreamFrameCodec();
  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  StreamSubscription<List<int>>? _sub;
  ConnectionState _state = ConnectionState.connecting;

  _LanConnection({
    required this.peer,
    required this.socket,
    required this.onClosed,
  }) {
    // Read the first line as peer identity announcement if present later.
    _sub = socket.listen(
      (data) {
        try {
          for (final frame in _codec.add(Uint8List.fromList(data))) {
            if (!_incoming.isClosed) _incoming.add(frame);
          }
        } catch (_) {
          _codec.clear();
        }
      },
      onDone: () => unawaited(close()),
      onError: (_) => unawaited(close()),
      cancelOnError: true,
    );
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _states.stream;

  @override
  LinkMetrics get metrics => const LinkMetrics(mtu: 1400, rttMs: 5);

  void markOpen() {
    _state = ConnectionState.open;
    if (!_states.isClosed) _states.add(_state);
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('LAN connection not open');
    }
    socket.add(StreamFrameCodec.encode(data));
    await socket.flush();
  }

  @override
  Future<void> close() async {
    if (_state == ConnectionState.closed) return;
    _state = ConnectionState.closed;
    if (!_states.isClosed) _states.add(_state);
    await _sub?.cancel();
    try {
      await socket.close();
    } catch (_) {}
    onClosed();
    await _incoming.close();
    await _states.close();
  }
}

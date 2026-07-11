import 'dart:async';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/transport_kind.dart';
import '../protocol/frame_codec.dart';
import '../transport/connection.dart';
import '../transport/transport.dart';
import 'hardware_adapter.dart';

/// Point-to-point [Transport] backed by a [HardwareAdapter].
///
/// Discovery yields a single synthetic peer while the adapter is open.
/// Suitable for LoRa/UWB/custom radio dongles that present a byte stream.
final class AdapterTransport implements Transport {
  final HardwareAdapter adapter;
  @override
  final TransportKind kind;
  @override
  final String name;

  final String remotePeerId;
  final String remoteDisplayName;

  final StreamController<Peer> _discovery = StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();

  StreamSubscription<Uint8List>? _adapterSub;
  _AdapterConnection? _connection;
  Timer? _discoveryTimer;
  bool _discovering = false;
  String _localId = '';

  AdapterTransport({
    required this.adapter,
    this.kind = TransportKind.custom,
    String? name,
    this.remotePeerId = 'hw-peer',
    this.remoteDisplayName = 'Hardware peer',
  }) : name = name ?? adapter.name;

  @override
  TransportCapabilities get capabilities => TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: false,
        maxMtu: 512,
        typicalRangeMeters: kind == TransportKind.lora ? 2000 : 50,
      );

  @override
  Stream<Connection> get incomingConnections => _inbound.stream;

  @override
  Future<bool> isAvailable() => adapter.isConnected();

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    _localId = localId;
    await adapter.open();
    _ensureAdapterListen();
  }

  @override
  Future<void> stopAdvertising() async {}

  @override
  Stream<Peer> discover() {
    _discovering = true;
    unawaited(_emitPeerIfOpen());
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_discovering) return;
      unawaited(_emitPeerIfOpen());
    });
    return _discovery.stream;
  }

  Future<void> _emitPeerIfOpen() async {
    if (!await adapter.isConnected()) return;
    if (_discovery.isClosed) return;
    _discovery.add(
      Peer(
        id: remotePeerId,
        displayName: remoteDisplayName,
        transports: {kind},
        rssi: adapter.rssi,
        addresses: {kind: adapter.id},
        lastSeen: DateTime.now().toUtc(),
        metadata: {
          'adapter': adapter.id,
          if (_localId.isNotEmpty) 'localId': _localId,
        },
      ),
    );
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }

  void _ensureAdapterListen() {
    _adapterSub ??= adapter.inbound.listen((data) {
      final conn = _connection;
      if (conn == null || conn.state != ConnectionState.open) {
        // Passive open: create inbound connection on first frame.
        final peer = Peer(
          id: remotePeerId,
          displayName: remoteDisplayName,
          transports: {kind},
          rssi: adapter.rssi,
          addresses: {kind: adapter.id},
          lastSeen: DateTime.now().toUtc(),
        );
        final c = _AdapterConnection(
          peer: peer,
          kind: kind,
          adapter: adapter,
        );
        c.markOpen();
        _connection = c;
        if (!_inbound.isClosed) {
          _inbound.add(c);
        }
        c.deliverRaw(data);
      } else {
        conn.deliverRaw(data);
      }
    });
  }

  @override
  Future<Connection> connect(Peer peer) async {
    await adapter.open();
    _ensureAdapterListen();
    final existing = _connection;
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }
    final conn = _AdapterConnection(
      peer: peer.copyWith(
        transports: {...peer.transports, kind},
        addresses: {...peer.addresses, kind: adapter.id},
      ),
      kind: kind,
      adapter: adapter,
    );
    conn.markOpen();
    _connection = conn;
    return conn;
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    // Hardware adapters may map duty cycle later; no-op by default.
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    await _adapterSub?.cancel();
    _adapterSub = null;
    await _connection?.close();
    _connection = null;
    await adapter.dispose();
    await _discovery.close();
    await _inbound.close();
  }

  /// Cancel discovery timers synchronously (tests / Flutter dispose).
  void cancelDiscoverySync() {
    _discovering = false;
    _discoveryTimer?.cancel();
    _discoveryTimer = null;
  }
}

final class _AdapterConnection implements Connection {
  @override
  final Peer peer;
  @override
  final TransportKind kind;

  final HardwareAdapter adapter;
  final StreamFrameCodec _codec = StreamFrameCodec();
  late final StreamController<Uint8List> _incoming;
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  ConnectionState _state = ConnectionState.connecting;
  final List<Uint8List> _rxBuffer = [];
  int _listeners = 0;

  _AdapterConnection({
    required this.peer,
    required this.kind,
    required this.adapter,
  }) {
    _incoming = StreamController<Uint8List>.broadcast(
      onListen: () {
        _listeners++;
        if (_rxBuffer.isEmpty) return;
        final pending = List<Uint8List>.from(_rxBuffer);
        _rxBuffer.clear();
        for (final f in pending) {
          if (!_incoming.isClosed) _incoming.add(f);
        }
      },
      onCancel: () {
        _listeners = (_listeners - 1).clamp(0, 1 << 20);
      },
    );
  }

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _states.stream;

  @override
  LinkMetrics get metrics => LinkMetrics(mtu: 512, rssi: adapter.rssi);

  void markOpen() {
    _state = ConnectionState.open;
    if (!_states.isClosed) _states.add(_state);
  }

  void deliverRaw(Uint8List data) {
    try {
      for (final frame in _codec.add(data)) {
        if (_listeners == 0) {
          _rxBuffer.add(frame);
        } else if (!_incoming.isClosed) {
          _incoming.add(frame);
        }
      }
    } catch (_) {
      _codec.clear();
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('adapter connection not open');
    }
    await adapter.write(StreamFrameCodec.encode(data));
  }

  @override
  Future<void> close() async {
    if (_state == ConnectionState.closed) return;
    _state = ConnectionState.closed;
    if (!_states.isClosed) _states.add(_state);
    await _incoming.close();
    await _states.close();
  }
}

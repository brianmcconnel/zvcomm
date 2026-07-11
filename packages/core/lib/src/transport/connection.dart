import 'dart:async';
import 'dart:typed_data';

import '../models/peer.dart';
import '../models/transport_kind.dart';

/// State of a [Connection].
enum ConnectionState {
  connecting,
  open,
  closing,
  closed,
  failed,
}

/// QoS / link metrics exposed by a transport connection.
final class LinkMetrics {
  final int? mtu;
  final int? rssi;
  final int? rttMs;
  final double? packetLoss;

  const LinkMetrics({
    this.mtu,
    this.rssi,
    this.rttMs,
    this.packetLoss,
  });
}

/// Bidirectional link to a [Peer] on a single [TransportKind].
abstract class Connection {
  /// Remote peer for this link.
  Peer get peer;

  /// Transport that owns this connection.
  TransportKind get kind;

  /// Current connection state.
  ConnectionState get state;

  /// Stream of inbound frames (raw bytes after transport framing).
  Stream<Uint8List> get incoming;

  /// Stream of state changes.
  Stream<ConnectionState> get stateChanges;

  /// Latest known link metrics.
  LinkMetrics get metrics;

  /// Send a complete frame. Implementations may fragment by MTU.
  Future<void> send(Uint8List data);

  /// Gracefully close the link.
  Future<void> close();
}

/// Simple in-memory connection used by [MockTransport] and unit tests.
final class InMemoryConnection implements Connection {
  @override
  final Peer peer;

  @override
  final TransportKind kind;

  late final StreamController<Uint8List> _incoming;
  final StreamController<ConnectionState> _stateChanges =
      StreamController<ConnectionState>.broadcast();

  ConnectionState _state = ConnectionState.connecting;
  LinkMetrics _metrics;
  void Function(Uint8List data)? _onSend;
  final List<Uint8List> _rxBuffer = [];
  int _listenerCount = 0;

  InMemoryConnection({
    required this.peer,
    this.kind = TransportKind.mock,
    LinkMetrics metrics = const LinkMetrics(mtu: 512, rssi: -50, rttMs: 5),
    void Function(Uint8List data)? onSend,
  })  : _metrics = metrics,
        _onSend = onSend {
    _incoming = StreamController<Uint8List>.broadcast(
      onListen: _onListen,
      onCancel: () {
        _listenerCount = (_listenerCount - 1).clamp(0, 1 << 30);
      },
    );
  }

  void _onListen() {
    _listenerCount++;
    if (_rxBuffer.isEmpty) return;
    final pending = List<Uint8List>.from(_rxBuffer);
    _rxBuffer.clear();
    for (final data in pending) {
      if (!_incoming.isClosed) {
        _incoming.add(data);
      }
    }
  }

  /// Wire the peer side's send path (simulator / mock pairing).
  set onSend(void Function(Uint8List data)? handler) => _onSend = handler;

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _stateChanges.stream;

  @override
  LinkMetrics get metrics => _metrics;

  void updateMetrics(LinkMetrics metrics) => _metrics = metrics;

  /// Deliver bytes as if received from the remote peer.
  ///
  /// Frames arriving before a listener attaches are buffered (avoids races
  /// when the dialing side sends immediately after [connect]).
  void deliver(Uint8List data) {
    if (_state != ConnectionState.open) return;
    if (_incoming.isClosed) return;
    if (_listenerCount == 0) {
      _rxBuffer.add(Uint8List.fromList(data));
      return;
    }
    _incoming.add(data);
  }

  void markOpen() => _setState(ConnectionState.open);

  void markFailed() => _setState(ConnectionState.failed);

  void _setState(ConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) {
      _stateChanges.add(next);
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('Connection is not open (state=$_state)');
    }
    _onSend?.call(data);
  }

  @override
  Future<void> close() async {
    if (_state == ConnectionState.closed) return;
    _setState(ConnectionState.closing);
    _setState(ConnectionState.closed);
    await _incoming.close();
    await _stateChanges.close();
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';

/// BLE link that fragments frames to the negotiated write/notify MTU.
final class BleConnection implements Connection {
  @override
  final Peer peer;

  @override
  TransportKind get kind => TransportKind.ble;

  final Future<void> Function(Uint8List chunk) _writeChunk;
  final Future<void> Function() _onClose;
  final int Function() _maxChunk;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionState> _stateChanges =
      StreamController<ConnectionState>.broadcast();
  final StreamFrameCodec _codec = StreamFrameCodec();

  ConnectionState _state = ConnectionState.connecting;
  LinkMetrics _metrics;

  BleConnection({
    required this.peer,
    required Future<void> Function(Uint8List chunk) writeChunk,
    required Future<void> Function() onClose,
    required int Function() maxChunk,
    LinkMetrics metrics = const LinkMetrics(mtu: 185),
  })  : _writeChunk = writeChunk,
        _onClose = onClose,
        _maxChunk = maxChunk,
        _metrics = metrics;

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _stateChanges.stream;

  @override
  LinkMetrics get metrics => _metrics;

  void updateMetrics(LinkMetrics metrics) => _metrics = metrics;

  void markOpen() => _setState(ConnectionState.open);

  void markFailed() => _setState(ConnectionState.failed);

  /// Feed ATT-layer bytes (may be a partial length-prefixed frame).
  void deliverChunk(Uint8List chunk) {
    if (_state != ConnectionState.open && _state != ConnectionState.connecting) {
      return;
    }
    try {
      for (final frame in _codec.add(chunk)) {
        if (!_incoming.isClosed) {
          _incoming.add(frame);
        }
      }
    } catch (_) {
      // Drop malformed stream; keep connection for recovery.
      _codec.clear();
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('BLE connection is not open (state=$_state)');
    }
    final framed = StreamFrameCodec.encode(data);
    final max = _maxChunk().clamp(20, 512);
    for (final part in StreamFrameCodec.chunk(framed, max)) {
      await _writeChunk(part);
    }
  }

  @override
  Future<void> close() async {
    if (_state == ConnectionState.closed) return;
    _setState(ConnectionState.closing);
    try {
      await _onClose();
    } catch (_) {}
    _setState(ConnectionState.closed);
    await _incoming.close();
    await _stateChanges.close();
  }

  void _setState(ConnectionState next) {
    if (_state == next) return;
    _state = next;
    if (!_stateChanges.isClosed) {
      _stateChanges.add(next);
    }
  }
}

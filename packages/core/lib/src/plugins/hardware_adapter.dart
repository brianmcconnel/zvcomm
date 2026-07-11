import 'dart:async';
import 'dart:typed_data';

/// Low-level byte pipe to optional hardware (serial radio, USB dongle, etc.).
///
/// Adapters are wrapped by [AdapterTransport] so mesh code only sees [Transport].
abstract class HardwareAdapter {
  /// Stable adapter id (e.g. `serial:/dev/ttyUSB0`, `loopback:a`).
  String get id;

  /// Human-readable label.
  String get name;

  /// Whether the device is open and usable.
  Future<bool> isConnected();

  /// Open the device (no-op if already open).
  Future<void> open();

  /// Close and release resources.
  Future<void> close();

  /// Inbound raw frames from hardware.
  Stream<Uint8List> get inbound;

  /// Write a raw frame to hardware.
  Future<void> write(Uint8List data);

  /// Optional RSSI / link quality in dBm.
  int? get rssi => null;

  /// Dispose streams and native handles.
  Future<void> dispose() async {
    await close();
  }
}

/// In-process paired adapters for tests and simulator-style hardware mocks.
///
/// Bytes written to [a] appear on [b.inbound] and vice versa.
final class LoopbackHardwarePair {
  final LoopbackHardwareAdapter a;
  final LoopbackHardwareAdapter b;

  LoopbackHardwarePair._(this.a, this.b);

  factory LoopbackHardwarePair({
    String idA = 'loopback:a',
    String idB = 'loopback:b',
  }) {
    late LoopbackHardwareAdapter a;
    late LoopbackHardwareAdapter b;
    a = LoopbackHardwareAdapter(
      id: idA,
      name: 'Loopback A',
      peerWriter: (data) => b.deliver(data),
    );
    b = LoopbackHardwareAdapter(
      id: idB,
      name: 'Loopback B',
      peerWriter: (data) => a.deliver(data),
    );
    return LoopbackHardwarePair._(a, b);
  }

  Future<void> dispose() async {
    await a.dispose();
    await b.dispose();
  }
}

/// One side of a [LoopbackHardwarePair] (or a custom peer writer).
final class LoopbackHardwareAdapter implements HardwareAdapter {
  @override
  final String id;
  @override
  final String name;

  final void Function(Uint8List data) peerWriter;
  final StreamController<Uint8List> _inbound =
      StreamController<Uint8List>.broadcast();
  bool _open = false;
  int? _rssi;

  LoopbackHardwareAdapter({
    required this.id,
    required this.name,
    required this.peerWriter,
    int? rssi,
  }) : _rssi = rssi;

  @override
  int? get rssi => _rssi;

  set rssi(int? value) => _rssi = value;

  @override
  Stream<Uint8List> get inbound => _inbound.stream;

  @override
  Future<bool> isConnected() async => _open;

  @override
  Future<void> open() async {
    _open = true;
  }

  @override
  Future<void> close() async {
    _open = false;
  }

  @override
  Future<void> write(Uint8List data) async {
    if (!_open) throw StateError('adapter $id is closed');
    peerWriter(Uint8List.fromList(data));
  }

  /// Inject bytes as if received from the wire.
  void deliver(Uint8List data) {
    if (_open && !_inbound.isClosed) {
      _inbound.add(data);
    }
  }

  @override
  Future<void> dispose() async {
    await close();
    await _inbound.close();
  }
}

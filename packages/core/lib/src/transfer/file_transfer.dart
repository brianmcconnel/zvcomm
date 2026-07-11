import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../mesh/mesh_node.dart';
import '../models/message.dart';

/// Wire subtype for [MessageKind.data] file transfer frames.
abstract final class FileTransferWire {
  static const int offer = 0x01;
  static const int chunk = 0x02;
  static const int ack = 0x03;
  static const int complete = 0x04;
  static const int abort = 0x05;

  /// Default chunk size (fits BLE MTU after framing overhead).
  static const int defaultChunkSize = 400;
}

/// Metadata for an outgoing or incoming transfer.
final class FileTransferInfo {
  final String transferId;
  final String fileName;
  final int totalBytes;
  final int chunkSize;
  final int totalChunks;
  final String? mimeType;
  final String? sourceId;
  final String? destinationId;

  const FileTransferInfo({
    required this.transferId,
    required this.fileName,
    required this.totalBytes,
    required this.chunkSize,
    required this.totalChunks,
    this.mimeType,
    this.sourceId,
    this.destinationId,
  });

  double progress(int bytesReceived) =>
      totalBytes == 0 ? 1.0 : (bytesReceived / totalBytes).clamp(0.0, 1.0);
}

/// Progress update for UI.
final class FileTransferProgress {
  final FileTransferInfo info;
  final int bytesTransferred;
  final bool done;
  final bool failed;
  final String? error;

  const FileTransferProgress({
    required this.info,
    required this.bytesTransferred,
    this.done = false,
    this.failed = false,
    this.error,
  });

  double get fraction => info.progress(bytesTransferred);
}

/// Assembles / disassembles file transfer frames over [MeshNode].
final class FileTransferService {
  final MeshNode node;
  final int chunkSize;
  final Random _random;

  final StreamController<FileTransferProgress> _progress =
      StreamController<FileTransferProgress>.broadcast();
  final StreamController<({FileTransferInfo info, Uint8List bytes})>
      _completed = StreamController.broadcast();

  final Map<String, _IncomingAssembly> _incoming = {};
  StreamSubscription<MeshMessage>? _sub;

  FileTransferService({
    required this.node,
    this.chunkSize = FileTransferWire.defaultChunkSize,
    Random? random,
  }) : _random = random ?? Random.secure();

  Stream<FileTransferProgress> get progress => _progress.stream;

  /// Completed files (metadata + full bytes).
  Stream<({FileTransferInfo info, Uint8List bytes})> get completed =>
      _completed.stream;

  void start() {
    _sub ??= node.messages.listen(_onMessage);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> dispose() async {
    await stop();
    await _progress.close();
    await _completed.close();
    _incoming.clear();
  }

  /// Send [bytes] as [fileName] to [to] (null = broadcast flood).
  Future<FileTransferInfo> sendFile({
    required String fileName,
    required Uint8List bytes,
    String? to,
    String? mimeType,
  }) async {
    final id = _newId();
    final totalChunks = bytes.isEmpty ? 1 : (bytes.length / chunkSize).ceil();
    final info = FileTransferInfo(
      transferId: id,
      fileName: fileName,
      totalBytes: bytes.length,
      chunkSize: chunkSize,
      totalChunks: totalChunks,
      mimeType: mimeType ?? 'application/octet-stream',
      sourceId: node.localId,
      destinationId: to,
    );

    await node.send(
      MeshMessage(
        id: _newId(),
        sourceId: node.localId,
        destinationId: to,
        kind: MessageKind.data,
        payload: _encodeOffer(info),
        timestamp: DateTime.now().toUtc(),
      ),
    );

    for (var i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end =
          (start + chunkSize > bytes.length) ? bytes.length : start + chunkSize;
      final slice = bytes.isEmpty
          ? Uint8List(0)
          : Uint8List.sublistView(bytes, start, end);
      await node.send(
        MeshMessage(
          id: _newId(),
          sourceId: node.localId,
          destinationId: to,
          kind: MessageKind.data,
          payload: _encodeChunk(id, i, slice),
          timestamp: DateTime.now().toUtc(),
        ),
      );
      if (!_progress.isClosed) {
        _progress.add(
          FileTransferProgress(
            info: info,
            bytesTransferred: end,
          ),
        );
      }
    }

    await node.send(
      MeshMessage(
        id: _newId(),
        sourceId: node.localId,
        destinationId: to,
        kind: MessageKind.data,
        payload: _encodeComplete(id),
        timestamp: DateTime.now().toUtc(),
      ),
    );

    if (!_progress.isClosed) {
      _progress.add(
        FileTransferProgress(
          info: info,
          bytesTransferred: bytes.length,
          done: true,
        ),
      );
    }
    return info;
  }

  void _onMessage(MeshMessage msg) {
    if (msg.kind != MessageKind.data || msg.payload.isEmpty) return;
    final type = msg.payload[0];
    try {
      switch (type) {
        case FileTransferWire.offer:
          final info = _decodeOffer(msg.payload, msg);
          _incoming[info.transferId] = _IncomingAssembly(info);
          if (!_progress.isClosed) {
            _progress.add(
              FileTransferProgress(info: info, bytesTransferred: 0),
            );
          }
        case FileTransferWire.chunk:
          final parsed = _decodeChunk(msg.payload);
          final ass = _incoming[parsed.transferId];
          if (ass == null) return;
          ass.addChunk(parsed.index, parsed.data);
          if (!_progress.isClosed) {
            _progress.add(
              FileTransferProgress(
                info: ass.info,
                bytesTransferred: ass.bytesReceived,
              ),
            );
          }
        case FileTransferWire.complete:
          final tid = _decodeTransferId(msg.payload);
          final ass = _incoming.remove(tid);
          if (ass == null) return;
          final bytes = ass.assemble();
          if (!_progress.isClosed) {
            _progress.add(
              FileTransferProgress(
                info: ass.info,
                bytesTransferred: bytes.length,
                done: true,
              ),
            );
          }
          if (!_completed.isClosed) {
            _completed.add((info: ass.info, bytes: bytes));
          }
        case FileTransferWire.abort:
          final tid = _decodeTransferId(msg.payload);
          final ass = _incoming.remove(tid);
          if (ass != null && !_progress.isClosed) {
            _progress.add(
              FileTransferProgress(
                info: ass.info,
                bytesTransferred: ass.bytesReceived,
                failed: true,
                error: 'aborted',
              ),
            );
          }
      }
    } catch (_) {
      // Ignore malformed transfer frames.
    }
  }

  Uint8List _encodeOffer(FileTransferInfo info) {
    final meta = utf8.encode(
      jsonEncode({
        'id': info.transferId,
        'name': info.fileName,
        'size': info.totalBytes,
        'chunk': info.chunkSize,
        'chunks': info.totalChunks,
        'mime': info.mimeType,
      }),
    );
    return Uint8List.fromList([FileTransferWire.offer, ...meta]);
  }

  FileTransferInfo _decodeOffer(Uint8List payload, MeshMessage msg) {
    final map =
        jsonDecode(utf8.decode(payload.sublist(1))) as Map<String, dynamic>;
    return FileTransferInfo(
      transferId: map['id'] as String,
      fileName: map['name'] as String? ?? 'file',
      totalBytes: map['size'] as int? ?? 0,
      chunkSize: map['chunk'] as int? ?? chunkSize,
      totalChunks: map['chunks'] as int? ?? 1,
      mimeType: map['mime'] as String?,
      sourceId: msg.sourceId,
      destinationId: msg.destinationId,
    );
  }

  Uint8List _encodeChunk(String transferId, int index, Uint8List data) {
    final idBytes = utf8.encode(transferId);
    final out = BytesBuilder(copy: false)
      ..addByte(FileTransferWire.chunk)
      ..addByte(idBytes.length)
      ..add(idBytes)
      ..add(_u16be(index))
      ..add(_u16be(data.length))
      ..add(data);
    return out.toBytes();
  }

  ({String transferId, int index, Uint8List data}) _decodeChunk(
    Uint8List payload,
  ) {
    var o = 1;
    final idLen = payload[o++];
    final tid = utf8.decode(payload.sublist(o, o + idLen));
    o += idLen;
    final index = _readU16be(payload, o);
    o += 2;
    final len = _readU16be(payload, o);
    o += 2;
    final data = Uint8List.sublistView(payload, o, o + len);
    return (transferId: tid, index: index, data: data);
  }

  Uint8List _encodeComplete(String transferId) {
    final idBytes = utf8.encode(transferId);
    return Uint8List.fromList([
      FileTransferWire.complete,
      idBytes.length,
      ...idBytes,
    ]);
  }

  String _decodeTransferId(Uint8List payload) {
    final idLen = payload[1];
    return utf8.decode(payload.sublist(2, 2 + idLen));
  }

  String _newId() {
    final b = List<int>.generate(8, (_) => _random.nextInt(256));
    return b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _u16be(int v) {
    final o = Uint8List(2);
    o.buffer.asByteData().setUint16(0, v, Endian.big);
    return o;
  }

  static int _readU16be(Uint8List d, int o) =>
      ByteData.sublistView(d).getUint16(o, Endian.big);
}

final class _IncomingAssembly {
  final FileTransferInfo info;
  final Map<int, Uint8List> chunks = {};

  _IncomingAssembly(this.info);

  void addChunk(int index, Uint8List data) {
    chunks[index] = data;
  }

  int get bytesReceived => chunks.values.fold<int>(0, (a, b) => a + b.length);

  Uint8List assemble() {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < info.totalChunks; i++) {
      final c = chunks[i];
      if (c != null) out.add(c);
    }
    return out.toBytes();
  }
}

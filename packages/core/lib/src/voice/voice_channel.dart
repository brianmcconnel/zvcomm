import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../mesh/mesh_node.dart';
import '../models/message.dart';

/// Wire subtypes for walkie-talkie / PTT frames on [MessageKind.data].
///
/// Disjoint from [FileTransferWire] (0x01–0x05).
abstract final class VoiceWire {
  static const int talkStart = 0x10;
  static const int talkChunk = 0x11;
  static const int talkEnd = 0x12;
  static const int talkBusy = 0x13;

  /// PCM encoding id (16-bit little-endian mono).
  static const int encodingPcm16le = 1;

  /// Default capture rate for mesh voice (narrowband telephony).
  static const int defaultSampleRate = 8000;

  /// Samples per channel (mono).
  static const int defaultChannels = 1;

  /// Application chunk size (~25 ms at 8 kHz mono s16).
  static const int defaultChunkBytes = 400;

  /// Max clip length to protect the mesh.
  static const Duration maxTalkDuration = Duration(seconds: 12);

  /// Max PCM payload bytes for one transmission.
  static int get maxPcmBytes =>
      defaultSampleRate * 2 * maxTalkDuration.inSeconds;
}

/// Outbound or inbound push-to-talk transmission metadata.
final class VoiceTransmission {
  final String sessionId;
  final String? sourceId;
  final String? destinationId;

  /// When set, this talk is scoped to a mesh group (fan-out to members).
  final String? groupId;
  final int sampleRate;
  final int channels;
  final int encoding;
  final DateTime startedAt;
  final int? totalChunks;
  final int? totalBytes;

  const VoiceTransmission({
    required this.sessionId,
    this.sourceId,
    this.destinationId,
    this.groupId,
    this.sampleRate = VoiceWire.defaultSampleRate,
    this.channels = VoiceWire.defaultChannels,
    this.encoding = VoiceWire.encodingPcm16le,
    required this.startedAt,
    this.totalChunks,
    this.totalBytes,
  });

  bool get isBroadcast =>
      groupId == null && (destinationId == null || destinationId!.isEmpty);

  bool get isGroup => groupId != null && groupId!.isNotEmpty;

  Duration get duration {
    if (totalBytes == null || sampleRate <= 0 || channels <= 0) {
      return Duration.zero;
    }
    final samples = totalBytes! ~/ (2 * channels);
    return Duration(milliseconds: (samples * 1000) ~/ sampleRate);
  }
}

/// Progress / lifecycle event for UI.
enum VoiceEventKind {
  /// Local PTT started.
  txStart,

  /// Local chunk sent.
  txProgress,

  /// Local PTT finished (sent talk_end).
  txEnd,

  /// Local PTT aborted.
  txAbort,

  /// Remote talk_start received.
  rxStart,

  /// Remote chunk received.
  rxProgress,

  /// Remote clip complete (PCM ready to play).
  rxComplete,

  /// Remote talk aborted / incomplete.
  rxAbort,

  /// Channel busy (someone else talking).
  busy,

  /// Error message.
  error,
}

final class VoiceEvent {
  final VoiceEventKind kind;
  final VoiceTransmission? transmission;
  final Uint8List? pcm;
  final int bytesTransferred;
  final String? detail;

  const VoiceEvent({
    required this.kind,
    this.transmission,
    this.pcm,
    this.bytesTransferred = 0,
    this.detail,
  });
}

/// Simplex push-to-talk voice over [MeshNode] ([MessageKind.data] subtypes).
///
/// Hold-to-talk: [beginTalk] → repeated [sendPcmChunk] → [endTalk].
/// Receivers buffer PCM until [talkEnd] then emit [VoiceEventKind.rxComplete].
final class VoiceChannelService {
  final MeshNode node;
  final int chunkBytes;
  final Random _random;

  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();

  StreamSubscription<MeshMessage>? _sub;
  _OutgoingTalk? _tx;
  final Map<String, _IncomingTalk> _rx = {};

  /// Peer currently occupying the channel (remote talk in progress).
  String? busyPeerId;

  /// Optional filter: return false to ignore a remote talk_start (e.g. not in group).
  bool Function(VoiceTransmission info)? acceptIncoming;

  VoiceChannelService({
    required this.node,
    this.chunkBytes = VoiceWire.defaultChunkBytes,
    Random? random,
  }) : _random = random ?? Random.secure();

  Stream<VoiceEvent> get events => _events.stream;

  bool get isTransmitting => _tx != null;

  bool get isReceiving => _rx.isNotEmpty;

  bool get channelBusy => isReceiving || busyPeerId != null;

  void start() {
    _sub ??= node.messages.listen(_onMessage);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _tx = null;
    _rx.clear();
    busyPeerId = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  /// Start a PTT session.
  ///
  /// - [to]: single unicast peer (ignored when [recipients] is non-empty)
  /// - [recipients]: group fan-out (unicast each member)
  /// - both null/empty → mesh broadcast
  /// - [groupId]: optional group scope tagged on the wire for receivers
  Future<VoiceTransmission> beginTalk({
    String? to,
    List<String>? recipients,
    String? groupId,
  }) async {
    if (_tx != null) {
      throw StateError('already transmitting');
    }
    if (channelBusy) {
      throw StateError('channel busy — wait for the other station');
    }
    final dests = _resolveDestinations(to: to, recipients: recipients);
    final sessionId = _newId();
    final primary = dests.length == 1 ? dests.first : null;
    final tx = VoiceTransmission(
      sessionId: sessionId,
      sourceId: node.localId,
      destinationId: primary,
      groupId: groupId,
      startedAt: DateTime.now().toUtc(),
    );
    _tx = _OutgoingTalk(tx, destinations: dests);
    final startPayload = _encodeStart(tx);
    await _fanOut(dests, startPayload);
    _events.add(VoiceEvent(kind: VoiceEventKind.txStart, transmission: tx));
    return tx;
  }

  /// Send one PCM chunk (16-bit LE). No-op size 0.
  Future<void> sendPcmChunk(Uint8List pcm) async {
    final tx = _tx;
    if (tx == null) throw StateError('not transmitting — call beginTalk first');
    if (pcm.isEmpty) return;
    if (tx.bytesSent + pcm.length > VoiceWire.maxPcmBytes) {
      await endTalk();
      throw StateError('max talk duration exceeded');
    }

    // Split oversized buffers into wire-sized chunks.
    var offset = 0;
    while (offset < pcm.length) {
      final end = (offset + chunkBytes).clamp(0, pcm.length);
      final slice = Uint8List.sublistView(pcm, offset, end);
      offset = end;
      final seq = tx.seq++;
      tx.bytesSent += slice.length;
      final payload = _encodeChunk(tx.info.sessionId, seq, slice);
      await _fanOut(tx.destinations, payload);
      _events.add(
        VoiceEvent(
          kind: VoiceEventKind.txProgress,
          transmission: tx.info,
          bytesTransferred: tx.bytesSent,
        ),
      );
    }
  }

  /// End PTT and notify peers the clip is complete.
  Future<VoiceTransmission?> endTalk() async {
    final tx = _tx;
    if (tx == null) return null;
    _tx = null;
    final done = VoiceTransmission(
      sessionId: tx.info.sessionId,
      sourceId: tx.info.sourceId,
      destinationId: tx.info.destinationId,
      groupId: tx.info.groupId,
      sampleRate: tx.info.sampleRate,
      channels: tx.info.channels,
      encoding: tx.info.encoding,
      startedAt: tx.info.startedAt,
      totalChunks: tx.seq,
      totalBytes: tx.bytesSent,
    );
    await _fanOut(tx.destinations, _encodeEnd(done));
    _events.add(
      VoiceEvent(
        kind: VoiceEventKind.txEnd,
        transmission: done,
        bytesTransferred: done.totalBytes ?? 0,
      ),
    );
    return done;
  }

  /// Abort local PTT without sending remaining audio.
  Future<void> abortTalk({String reason = 'aborted'}) async {
    final tx = _tx;
    if (tx == null) return;
    _tx = null;
    final aborted = VoiceTransmission(
      sessionId: tx.info.sessionId,
      sourceId: tx.info.sourceId,
      destinationId: tx.info.destinationId,
      groupId: tx.info.groupId,
      sampleRate: tx.info.sampleRate,
      channels: tx.info.channels,
      encoding: tx.info.encoding,
      startedAt: tx.info.startedAt,
      totalChunks: tx.seq,
      totalBytes: tx.bytesSent,
    );
    await _fanOut(tx.destinations, _encodeEnd(aborted, aborted: true));
    _events.add(
      VoiceEvent(
        kind: VoiceEventKind.txAbort,
        transmission: tx.info,
        detail: reason,
      ),
    );
  }

  /// Convenience: send a full PCM clip as one PTT burst.
  Future<VoiceTransmission> sendPcmBurst(
    Uint8List pcm, {
    String? to,
    List<String>? recipients,
    String? groupId,
  }) async {
    await beginTalk(to: to, recipients: recipients, groupId: groupId);
    try {
      await sendPcmChunk(pcm);
      final done = await endTalk();
      return done!;
    } catch (e) {
      await abortTalk(reason: e.toString());
      rethrow;
    }
  }

  List<String?> _resolveDestinations({
    String? to,
    List<String>? recipients,
  }) {
    if (recipients != null && recipients.isNotEmpty) {
      return recipients.where((id) => id.isNotEmpty).toSet().toList();
    }
    return <String?>[to];
  }

  Future<void> _fanOut(List<String?> destinations, Uint8List payload) async {
    for (final dest in destinations) {
      await node.send(
        MeshMessage(
          id: _newId(),
          sourceId: node.localId,
          destinationId: dest,
          kind: MessageKind.data,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  void _onMessage(MeshMessage msg) {
    if (msg.kind != MessageKind.data || msg.payload.isEmpty) return;
    // Ignore our own echoes if the mesh reflects them.
    if (msg.sourceId != null && msg.sourceId == node.localId) return;

    final type = msg.payload[0];
    if (type < VoiceWire.talkStart || type > VoiceWire.talkBusy) return;

    try {
      switch (type) {
        case VoiceWire.talkStart:
          _onTalkStart(msg);
        case VoiceWire.talkChunk:
          _onTalkChunk(msg);
        case VoiceWire.talkEnd:
          _onTalkEnd(msg);
        case VoiceWire.talkBusy:
          _events.add(
            VoiceEvent(
              kind: VoiceEventKind.busy,
              detail: utf8.decode(msg.payload.sublist(1), allowMalformed: true),
            ),
          );
      }
    } catch (e) {
      _events.add(
        VoiceEvent(kind: VoiceEventKind.error, detail: e.toString()),
      );
    }
  }

  void _onTalkStart(MeshMessage msg) {
    final body = _decodeJson(msg.payload.sublist(1));
    final sessionId = body['sid'] as String? ?? '';
    if (sessionId.isEmpty) return;
    if (_tx != null) {
      // Local PTT wins; ignore remote (simplex collision).
      return;
    }
    // Already assembling this session (duplicate fan-out copy).
    if (_rx.containsKey(sessionId)) return;
    final info = VoiceTransmission(
      sessionId: sessionId,
      sourceId: msg.sourceId,
      destinationId: msg.destinationId,
      groupId: body['gid'] as String?,
      sampleRate: body['sr'] as int? ?? VoiceWire.defaultSampleRate,
      channels: body['ch'] as int? ?? VoiceWire.defaultChannels,
      encoding: body['enc'] as int? ?? VoiceWire.encodingPcm16le,
      startedAt: DateTime.now().toUtc(),
    );
    final accept = acceptIncoming;
    if (accept != null && !accept(info)) return;
    _rx[sessionId] = _IncomingTalk(info);
    busyPeerId = msg.sourceId;
    _events.add(VoiceEvent(kind: VoiceEventKind.rxStart, transmission: info));
  }

  void _onTalkChunk(MeshMessage msg) {
    if (msg.payload.length < 10) return;
    final sidLen = msg.payload[1];
    if (msg.payload.length < 2 + sidLen + 4) return;
    final sid = utf8.decode(msg.payload.sublist(2, 2 + sidLen));
    final seqOff = 2 + sidLen;
    final seq = ByteData.sublistView(msg.payload, seqOff, seqOff + 4)
        .getUint32(0, Endian.little);
    final pcm = msg.payload.sublist(seqOff + 4);
    final incoming = _rx[sid];
    if (incoming == null) return;
    incoming.add(seq, pcm);
    _events.add(
      VoiceEvent(
        kind: VoiceEventKind.rxProgress,
        transmission: incoming.info,
        bytesTransferred: incoming.bytesReceived,
      ),
    );
  }

  void _onTalkEnd(MeshMessage msg) {
    final body = _decodeJson(msg.payload.sublist(1));
    final sessionId = body['sid'] as String? ?? '';
    final aborted = body['abort'] == true;
    final incoming = _rx.remove(sessionId);
    if (busyPeerId == msg.sourceId) {
      busyPeerId = _rx.values.isEmpty ? null : _rx.values.first.info.sourceId;
    }
    if (incoming == null) return;
    final pcm = incoming.assemble();
    final done = VoiceTransmission(
      sessionId: sessionId,
      sourceId: incoming.info.sourceId,
      destinationId: incoming.info.destinationId,
      groupId: incoming.info.groupId,
      sampleRate: incoming.info.sampleRate,
      channels: incoming.info.channels,
      encoding: incoming.info.encoding,
      startedAt: incoming.info.startedAt,
      totalChunks: body['chunks'] as int? ?? incoming.chunks.length,
      totalBytes: pcm.length,
    );
    if (aborted || pcm.isEmpty) {
      _events.add(
        VoiceEvent(
          kind: VoiceEventKind.rxAbort,
          transmission: done,
          detail: aborted ? 'remote aborted' : 'empty clip',
        ),
      );
      return;
    }
    _events.add(
      VoiceEvent(
        kind: VoiceEventKind.rxComplete,
        transmission: done,
        pcm: pcm,
        bytesTransferred: pcm.length,
      ),
    );
  }

  Uint8List _encodeStart(VoiceTransmission tx) {
    final json = utf8.encode(
      jsonEncode({
        'sid': tx.sessionId,
        'sr': tx.sampleRate,
        'ch': tx.channels,
        'enc': tx.encoding,
        if (tx.groupId != null && tx.groupId!.isNotEmpty) 'gid': tx.groupId,
      }),
    );
    return Uint8List.fromList([VoiceWire.talkStart, ...json]);
  }

  Uint8List _encodeChunk(String sessionId, int seq, Uint8List pcm) {
    final sid = utf8.encode(sessionId);
    if (sid.length > 255) {
      throw ArgumentError('session id too long');
    }
    final out = BytesBuilder(copy: false)
      ..addByte(VoiceWire.talkChunk)
      ..addByte(sid.length)
      ..add(sid);
    final seqBytes = ByteData(4)..setUint32(0, seq, Endian.little);
    out.add(seqBytes.buffer.asUint8List());
    out.add(pcm);
    return out.toBytes();
  }

  Uint8List _encodeEnd(VoiceTransmission tx, {bool aborted = false}) {
    final json = utf8.encode(
      jsonEncode({
        'sid': tx.sessionId,
        'chunks': tx.totalChunks ?? 0,
        'bytes': tx.totalBytes ?? 0,
        if (aborted) 'abort': true,
      }),
    );
    return Uint8List.fromList([VoiceWire.talkEnd, ...json]);
  }

  Map<String, Object?> _decodeJson(Uint8List bytes) =>
      Map<String, Object?>.from(jsonDecode(utf8.decode(bytes)) as Map);

  String _newId() {
    final n = _random.nextInt(0x7fffffff);
    final t = DateTime.now().microsecondsSinceEpoch;
    return '${t.toRadixString(16)}-${n.toRadixString(16)}';
  }
}

final class _OutgoingTalk {
  final VoiceTransmission info;
  final List<String?> destinations;
  int seq = 0;
  int bytesSent = 0;
  _OutgoingTalk(this.info, {required this.destinations});
}

final class _IncomingTalk {
  final VoiceTransmission info;
  final Map<int, Uint8List> chunks = {};
  int bytesReceived = 0;

  _IncomingTalk(this.info);

  void add(int seq, Uint8List pcm) {
    if (chunks.containsKey(seq)) return;
    chunks[seq] = pcm;
    bytesReceived += pcm.length;
  }

  Uint8List assemble() {
    if (chunks.isEmpty) return Uint8List(0);
    final keys = chunks.keys.toList()..sort();
    final out = BytesBuilder(copy: false);
    for (final k in keys) {
      out.add(chunks[k]!);
    }
    return out.toBytes();
  }
}

/// Build a minimal WAV container around raw PCM s16le mono/stereo.
Uint8List pcm16ToWav(
  Uint8List pcm, {
  int sampleRate = VoiceWire.defaultSampleRate,
  int channels = VoiceWire.defaultChannels,
}) {
  final dataLen = pcm.length;
  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;
  final header = ByteData(44);
  // RIFF
  header.setUint8(0, 0x52); // R
  header.setUint8(1, 0x49); // I
  header.setUint8(2, 0x46); // F
  header.setUint8(3, 0x46); // F
  header.setUint32(4, 36 + dataLen, Endian.little);
  header.setUint8(8, 0x57); // W
  header.setUint8(9, 0x41); // A
  header.setUint8(10, 0x56); // V
  header.setUint8(11, 0x45); // E
  // fmt
  header.setUint8(12, 0x66); // f
  header.setUint8(13, 0x6d); // m
  header.setUint8(14, 0x74); // t
  header.setUint8(15, 0x20); // space
  header.setUint32(16, 16, Endian.little); // PCM chunk size
  header.setUint16(20, 1, Endian.little); // audio format PCM
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, 16, Endian.little); // bits per sample
  // data
  header.setUint8(36, 0x64); // d
  header.setUint8(37, 0x61); // a
  header.setUint8(38, 0x74); // t
  header.setUint8(39, 0x61); // a
  header.setUint32(40, dataLen, Endian.little);

  final out = BytesBuilder(copy: false)
    ..add(header.buffer.asUint8List())
    ..add(pcm);
  return out.toBytes();
}

/// Extract PCM from a standard PCM WAV (returns null if not s16le PCM).
Uint8List? wavToPcm16(Uint8List wav) {
  if (wav.length < 44) return null;
  if (wav[0] != 0x52 || wav[1] != 0x49 || wav[2] != 0x46 || wav[3] != 0x46) {
    return null;
  }
  // Find "data" chunk.
  var offset = 12;
  while (offset + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(offset, offset + 4));
    final size = ByteData.sublistView(wav, offset + 4, offset + 8)
        .getUint32(0, Endian.little);
    if (id == 'data') {
      final start = offset + 8;
      final end = (start + size).clamp(0, wav.length);
      return Uint8List.sublistView(wav, start, end);
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

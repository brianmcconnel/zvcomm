import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../crypto/identity.dart';
import '../crypto/secure_session.dart';
import '../models/message.dart';
import 'mesh_node.dart';

/// Optional secure façade over [MeshNode] for E2E encrypted chat.
///
/// Handshake and ciphertext travel as [MessageKind.control] / [MessageKind.chat]
/// payloads. Intermediate mesh hops cannot read sealed content.
final class SecureMesh {
  final MeshNode node;
  final DeviceIdentity identity;
  final SessionManager sessions;

  final StreamController<MeshMessage> _plaintext =
      StreamController<MeshMessage>.broadcast();
  StreamSubscription<MeshMessage>? _sub;

  SecureMesh({
    required this.node,
    required this.identity,
  }) : sessions = SessionManager(identity);

  /// Plaintext application messages after decryption.
  Stream<MeshMessage> get messages => _plaintext.stream;

  Future<void> start() async {
    await node.start();
    _sub = node.messages.listen(_onMeshMessage);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    await node.stop();
  }

  Future<void> dispose() async {
    await stop();
    sessions.clear();
    await _plaintext.close();
    await node.dispose();
  }

  /// Begin handshake with [peerId] (sends control message).
  Future<void> establishSession(String peerId) async {
    final init = await sessions.beginHandshake(peerId);
    await node.send(
      MeshMessage(
        id: _id(),
        sourceId: identity.id,
        destinationId: peerId,
        kind: MessageKind.control,
        payload: init,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  /// Send encrypted chat when a session exists; otherwise plain (or handshake first).
  Future<void> sendSecureChat(
    String text, {
    required String to,
    bool requireSession = true,
  }) async {
    if (!sessions.hasSession(to)) {
      if (requireSession) {
        await establishSession(to);
        // Caller may retry after handshake completes asynchronously.
        throw StateError('handshake started with $to; retry after established');
      }
      await node.sendChat(text, to: to);
      return;
    }
    final cipher = await sessions.encryptTo(
      to,
      Uint8List.fromList(utf8.encode(text)),
    );
    final payload = cipher;
    await node.send(
      MeshMessage(
        id: _id(),
        sourceId: identity.id,
        destinationId: to,
        kind: MessageKind.chat,
        payload: payload,
        timestamp: DateTime.now().toUtc(),
        headers: const {'enc': '1'},
      ),
    );
  }

  Future<void> _onMeshMessage(MeshMessage msg) async {
    final from = msg.sourceId ?? '';
    if (msg.kind == MessageKind.control) {
      try {
        final result = await sessions.handleHandshakeMessage(msg.payload);
        if (result.reply != null && from.isNotEmpty) {
          await node.send(
            MeshMessage(
              id: _id(),
              sourceId: identity.id,
              destinationId: from,
              kind: MessageKind.control,
              payload: result.reply!,
              timestamp: DateTime.now().toUtc(),
            ),
          );
        }
      } catch (_) {
        // Ignore malformed handshake.
      }
      return;
    }

    if (msg.kind == MessageKind.chat &&
        from.isNotEmpty &&
        sessions.hasSession(from) &&
        msg.payload.isNotEmpty &&
        msg.payload[0] == SecureWire.appData) {
      try {
        final clear = await sessions.decryptFrom(from, msg.payload);
        if (!_plaintext.isClosed) {
          _plaintext.add(
            msg.copyWith(payload: clear, headers: {...msg.headers, 'enc': '0'}),
          );
        }
        return;
      } catch (_) {
        // Fall through as plaintext.
      }
    }

    if (!_plaintext.isClosed) {
      _plaintext.add(msg);
    }
  }

  String _id() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(16);
}

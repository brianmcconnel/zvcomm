import 'dart:convert';
import 'dart:typed_data';

import '../models/message.dart';

/// UI-facing chat line (local or remote).
final class ChatLine {
  final String id;
  final String? peerId;
  final String text;
  final DateTime timestamp;
  final bool isLocal;
  final bool isBroadcast;
  final bool isSystem;

  const ChatLine({
    required this.id,
    required this.text,
    required this.timestamp,
    this.peerId,
    this.isLocal = false,
    this.isBroadcast = false,
    this.isSystem = false,
  });
}

/// In-memory chat history for a conversation key (`*` = broadcast).
final class ChatLog {
  final Map<String, List<ChatLine>> _threads = {};
  static const broadcastKey = '*';

  List<ChatLine> thread(String? peerId) {
    final key = peerId ?? broadcastKey;
    return List.unmodifiable(_threads[key] ?? const []);
  }

  void add(ChatLine line) {
    final key = line.isBroadcast
        ? broadcastKey
        : (line.isLocal
            ? (line.peerId ?? broadcastKey)
            : (line.peerId ?? broadcastKey));
    _threads.putIfAbsent(key, () => []).add(line);
  }

  void addLocalChat({
    required String text,
    String? to,
    required String messageId,
  }) {
    add(
      ChatLine(
        id: messageId,
        peerId: to,
        text: text,
        timestamp: DateTime.now().toUtc(),
        isLocal: true,
        isBroadcast: to == null || to.isEmpty,
      ),
    );
  }

  void addRemoteChat(MeshMessage msg) {
    if (msg.kind != MessageKind.chat) return;
    String text;
    try {
      text = utf8.decode(msg.payload);
    } catch (_) {
      text = '[binary ${msg.payload.length} B]';
    }
    add(
      ChatLine(
        id: msg.id,
        peerId: msg.sourceId,
        text: text,
        timestamp: msg.timestamp,
        isLocal: false,
        isBroadcast: msg.isBroadcast,
      ),
    );
  }

  void addSystem(String text) {
    add(
      ChatLine(
        id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        timestamp: DateTime.now().toUtc(),
        isSystem: true,
        isBroadcast: true,
      ),
    );
  }

  void clear([String? peerId]) {
    if (peerId == null) {
      _threads.clear();
    } else {
      _threads.remove(peerId);
    }
  }
}

/// Encode plain chat text payload.
Uint8List encodeChatText(String text) => Uint8List.fromList(utf8.encode(text));

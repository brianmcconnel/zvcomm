import 'dart:convert';
import 'dart:typed_data';

import '../models/message.dart';
import '../social/group.dart';
import 'message_censor.dart';

/// UI-facing chat line (local or remote).
final class ChatLine {
  final String id;
  final String? peerId;
  final String? groupId;
  final String text;
  final DateTime timestamp;
  final bool isLocal;
  final bool isBroadcast;
  final bool isSystem;

  /// Human name for the sender (remote); preferred over [peerId] in UI.
  final String? senderName;

  /// Emoji → reactor subject ids (RCS-style reactions).
  final Map<String, List<String>> reactions;

  /// Inline image (photo) payload when present.
  final Uint8List? imageBytes;
  final String? imageMime;
  final String? imageName;

  const ChatLine({
    required this.id,
    required this.text,
    required this.timestamp,
    this.peerId,
    this.groupId,
    this.isLocal = false,
    this.isBroadcast = false,
    this.isSystem = false,
    this.senderName,
    this.reactions = const {},
    this.imageBytes,
    this.imageMime,
    this.imageName,
  });

  bool get isGroup => groupId != null && groupId!.isNotEmpty;

  bool get isImage =>
      imageBytes != null && imageBytes!.isNotEmpty;

  /// Display label for the sender.
  String get displaySender {
    if (isLocal) return 'You';
    if (senderName != null && senderName!.isNotEmpty) return senderName!;
    if (peerId != null && peerId!.isNotEmpty) {
      return peerId!.length > 10 ? '${peerId!.substring(0, 10)}…' : peerId!;
    }
    return 'Unknown';
  }

  ChatLine copyWith({
    String? text,
    String? senderName,
    Map<String, List<String>>? reactions,
    Uint8List? imageBytes,
    String? imageMime,
    String? imageName,
    bool clearSenderName = false,
    bool clearImage = false,
  }) {
    return ChatLine(
      id: id,
      peerId: peerId,
      groupId: groupId,
      text: text ?? this.text,
      timestamp: timestamp,
      isLocal: isLocal,
      isBroadcast: isBroadcast,
      isSystem: isSystem,
      senderName: clearSenderName ? null : (senderName ?? this.senderName),
      reactions: reactions ?? this.reactions,
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      imageMime: clearImage ? null : (imageMime ?? this.imageMime),
      imageName: clearImage ? null : (imageName ?? this.imageName),
    );
  }

  /// Toggle [reactorId] on [emoji]; returns updated reaction map.
  Map<String, List<String>> toggledReactions({
    required String emoji,
    required String reactorId,
  }) {
    final next = <String, List<String>>{
      for (final e in reactions.entries) e.key: List<String>.from(e.value),
    };
    final list = next.putIfAbsent(emoji, () => <String>[]);
    if (list.contains(reactorId)) {
      list.remove(reactorId);
      if (list.isEmpty) next.remove(emoji);
    } else {
      list.add(reactorId);
    }
    return next;
  }
}

/// Gap after which a time separator is shown (RCS / iMessage style).
const Duration chatTimeSeparatorGap = Duration(minutes: 10);

/// In-memory chat history.
///
/// Thread keys:
/// - `*` — mesh broadcast
/// - `<peerId>` — 1:1 DM
/// - `g:<groupId>` — multi-party group
final class ChatLog {
  final Map<String, List<ChatLine>> _threads = {};
  static const broadcastKey = '*';

  static String groupKey(String groupId) => 'g:$groupId';

  List<ChatLine> thread(String? peerId) {
    final key = peerId ?? broadcastKey;
    return List.unmodifiable(_threads[key] ?? const []);
  }

  List<ChatLine> groupThread(String groupId) =>
      List.unmodifiable(_threads[groupKey(groupId)] ?? const []);

  void add(ChatLine line) {
    final String key;
    if (line.groupId != null && line.groupId!.isNotEmpty) {
      key = groupKey(line.groupId!);
    } else if (line.isBroadcast) {
      key = broadcastKey;
    } else {
      key = line.peerId ?? broadcastKey;
    }
    _threads.putIfAbsent(key, () => []).add(line);
  }

  void addLocalChat({
    required String text,
    String? to,
    required String messageId,
    String? groupId,
    String? senderName,
    Uint8List? imageBytes,
    String? imageMime,
    String? imageName,
  }) {
    add(
      ChatLine(
        id: messageId,
        peerId: groupId == null ? to : null,
        groupId: groupId,
        text: MessageCensor.censor(text),
        timestamp: DateTime.now().toUtc(),
        isLocal: true,
        isBroadcast: groupId == null && (to == null || to.isEmpty),
        senderName: senderName,
        imageBytes: imageBytes,
        imageMime: imageMime,
        imageName: imageName,
      ),
    );
  }

  void addRemoteChat(MeshMessage msg, {String? senderName}) {
    if (msg.kind != MessageKind.chat) return;
    String raw;
    try {
      raw = utf8.decode(msg.payload);
    } catch (_) {
      raw = '[binary ${msg.payload.length} B]';
    }

    // Photo / image chat.
    final image = ChatImageWire.tryParse(raw);
    if (image != null) {
      add(
        ChatLine(
          id: msg.id,
          peerId: msg.sourceId,
          groupId: image.groupId,
          text: image.caption.isEmpty
              ? '📷 ${image.fileName}'
              : MessageCensor.censor(image.caption),
          timestamp: msg.timestamp,
          isLocal: false,
          isBroadcast: image.groupId == null && msg.isBroadcast,
          senderName: senderName,
          imageBytes: image.bytes,
          imageMime: image.mimeType,
          imageName: image.fileName,
        ),
      );
      return;
    }

    final group = GroupChatWire.tryParse(raw);
    if (group != null) {
      add(
        ChatLine(
          id: msg.id,
          peerId: msg.sourceId,
          groupId: group.groupId,
          text: MessageCensor.censor(group.text),
          timestamp: msg.timestamp,
          isLocal: false,
          isBroadcast: false,
          senderName: senderName,
        ),
      );
      return;
    }

    add(
      ChatLine(
        id: msg.id,
        peerId: msg.sourceId,
        text: MessageCensor.censor(raw),
        timestamp: msg.timestamp,
        isLocal: false,
        isBroadcast: msg.isBroadcast,
        senderName: senderName,
      ),
    );
  }

  void addSystem(String text, {String? groupId}) {
    add(
      ChatLine(
        id: 'sys-${DateTime.now().microsecondsSinceEpoch}',
        text: text,
        timestamp: DateTime.now().toUtc(),
        isSystem: true,
        isBroadcast: groupId == null,
        groupId: groupId,
      ),
    );
  }

  /// Find a message by id across all threads.
  ChatLine? findById(String messageId) {
    for (final list in _threads.values) {
      for (final line in list) {
        if (line.id == messageId) return line;
      }
    }
    return null;
  }

  /// Apply reaction toggle; returns the updated line or null if missing.
  ChatLine? toggleReaction({
    required String messageId,
    required String emoji,
    required String reactorId,
  }) {
    for (final entry in _threads.entries) {
      final list = entry.value;
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != messageId) continue;
        final updated = list[i].copyWith(
          reactions: list[i].toggledReactions(
            emoji: emoji,
            reactorId: reactorId,
          ),
        );
        list[i] = updated;
        return updated;
      }
    }
    return null;
  }

  /// Replace reactions wholesale (e.g. from mesh sync of a peer's reaction).
  ChatLine? setReactions(
    String messageId,
    Map<String, List<String>> reactions,
  ) {
    for (final list in _threads.values) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].id != messageId) continue;
        final updated = list[i].copyWith(reactions: reactions);
        list[i] = updated;
        return updated;
      }
    }
    return null;
  }

  void clear([String? peerId]) {
    if (peerId == null) {
      _threads.clear();
    } else {
      _threads.remove(peerId);
    }
  }

  void clearGroup(String groupId) => _threads.remove(groupKey(groupId));
}

/// Encode plain chat text payload (censored).
Uint8List encodeChatText(String text) =>
    Uint8List.fromList(utf8.encode(MessageCensor.censor(text)));

/// Structured chat image payload (carried as [MessageKind.chat] UTF-8 JSON).
///
/// Photos are base64-embedded so they travel with the chat envelope on the mesh.
/// [maxBytes] caps decoded image size for BLE-friendly transfers.
abstract final class ChatImageWire {
  static const kind = 'chat_image';

  /// Max decoded image size (bytes). Larger picks should be compressed first.
  static const int maxBytes = 180 * 1024;

  static String encode({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
    String? groupId,
    String caption = '',
  }) {
    if (bytes.length > maxBytes) {
      throw StateError(
        'image too large (${bytes.length} B); max $maxBytes B',
      );
    }
    return jsonEncode({
      'v': 1,
      'kind': kind,
      if (groupId != null && groupId.isNotEmpty) 'gid': groupId,
      'fileName': fileName,
      'mime': mimeType,
      if (caption.trim().isNotEmpty) 'caption': caption.trim(),
      'data': base64Encode(bytes),
    });
  }

  static ChatImagePayload? tryParse(String raw) {
    final t = raw.trim();
    if (!t.startsWith('{')) return null;
    try {
      final map = jsonDecode(t) as Map<String, dynamic>;
      if (map['kind'] != kind) return null;
      final data = map['data'] as String?;
      if (data == null || data.isEmpty) return null;
      final bytes = base64Decode(data);
      if (bytes.isEmpty || bytes.length > maxBytes) return null;
      return ChatImagePayload(
        fileName: map['fileName'] as String? ?? 'photo.jpg',
        mimeType: map['mime'] as String? ?? 'image/jpeg',
        bytes: Uint8List.fromList(bytes),
        groupId: map['gid'] as String?,
        caption: map['caption'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  static bool looksLikeImageMime(String? mime) {
    if (mime == null) return false;
    final m = mime.toLowerCase();
    return m.startsWith('image/');
  }
}

final class ChatImagePayload {
  final String fileName;
  final String mimeType;
  final Uint8List bytes;
  final String? groupId;
  final String caption;

  const ChatImagePayload({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
    this.groupId,
    this.caption = '',
  });
}

/// Mesh control payload for RCS-style reactions on chat lines.
abstract final class ChatReactionWire {
  static const typeKey = 'type';
  static const reactionType = 'chat_reaction';

  /// Quick reaction strip (full catalog lives in UI [EmojiCatalog]).
  static const defaultEmojis = [
    '👍',
    '👎',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
    '🔥',
    '🎉',
    '💯',
    '👏',
    '🤔',
  ];

  static Uint8List encode({
    required String messageId,
    required String emoji,
    required String reactorId,
    String? groupId,
    String? threadPeerId,
  }) {
    final body = {
      typeKey: reactionType,
      'messageId': messageId,
      'emoji': emoji,
      'reactorId': reactorId,
      if (groupId != null) 'groupId': groupId,
      if (threadPeerId != null) 'threadPeerId': threadPeerId,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  static ChatReactionEvent? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      if (map[typeKey] != reactionType) return null;
      final messageId = map['messageId'] as String?;
      final emoji = map['emoji'] as String?;
      final reactorId = map['reactorId'] as String?;
      if (messageId == null || emoji == null || reactorId == null) return null;
      return ChatReactionEvent(
        messageId: messageId,
        emoji: emoji,
        reactorId: reactorId,
        groupId: map['groupId'] as String?,
        threadPeerId: map['threadPeerId'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

final class ChatReactionEvent {
  final String messageId;
  final String emoji;
  final String reactorId;
  final String? groupId;
  final String? threadPeerId;

  const ChatReactionEvent({
    required this.messageId,
    required this.emoji,
    required this.reactorId,
    this.groupId,
    this.threadPeerId,
  });
}

/// Mesh control payload for "is typing" indicators (DM + group).
abstract final class ChatTypingWire {
  static const typeKey = 'type';
  static const typingType = 'chat_typing';

  /// How long a peer is considered typing without a refresh.
  static const Duration defaultTtl = Duration(seconds: 4);

  static Uint8List encode({
    required String peerId,
    required bool typing,
    String? groupId,
    String? threadPeerId,
    String? displayName,
  }) {
    final body = {
      typeKey: typingType,
      'peerId': peerId,
      'typing': typing,
      if (groupId != null) 'groupId': groupId,
      if (threadPeerId != null) 'threadPeerId': threadPeerId,
      if (displayName != null && displayName.isNotEmpty)
        'displayName': displayName,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }

  static ChatTypingEvent? tryDecode(Uint8List payload) {
    try {
      final map = Map<String, Object?>.from(
        jsonDecode(utf8.decode(payload)) as Map,
      );
      if (map[typeKey] != typingType) return null;
      final peerId = map['peerId'] as String?;
      if (peerId == null || peerId.isEmpty) return null;
      return ChatTypingEvent(
        peerId: peerId,
        typing: map['typing'] == true,
        groupId: map['groupId'] as String?,
        threadPeerId: map['threadPeerId'] as String?,
        displayName: map['displayName'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

final class ChatTypingEvent {
  final String peerId;
  final bool typing;
  final String? groupId;
  final String? threadPeerId;
  final String? displayName;

  const ChatTypingEvent({
    required this.peerId,
    required this.typing,
    this.groupId,
    this.threadPeerId,
    this.displayName,
  });
}

/// Tracks who is currently typing in each conversation thread.
///
/// Thread keys match [ChatLog]: `*`, peer id, or `g:<groupId>`.
final class TypingPresence {
  final Map<String, Map<String, _TypingPeer>> _byThread = {};
  Duration ttl;

  TypingPresence({this.ttl = ChatTypingWire.defaultTtl});

  static String threadKey({String? peerId, String? groupId}) {
    if (groupId != null && groupId.isNotEmpty) {
      return ChatLog.groupKey(groupId);
    }
    return peerId ?? ChatLog.broadcastKey;
  }

  void setTyping({
    required String threadKey,
    required String peerId,
    required bool typing,
    String? displayName,
  }) {
    if (peerId.isEmpty) return;
    final map = _byThread.putIfAbsent(threadKey, () => {});
    if (!typing) {
      map.remove(peerId);
      if (map.isEmpty) _byThread.remove(threadKey);
      return;
    }
    map[peerId] = _TypingPeer(
      peerId: peerId,
      displayName: displayName ?? '',
      expiresAt: DateTime.now().toUtc().add(ttl),
    );
  }

  /// Active typers for [threadKey] (expired entries purged).
  List<({String peerId, String displayName})> typers(String threadKey) {
    _purge(threadKey);
    final map = _byThread[threadKey];
    if (map == null || map.isEmpty) return const [];
    return map.values
        .map(
          (e) => (
            peerId: e.peerId,
            displayName: e.displayName.isEmpty ? e.peerId : e.displayName,
          ),
        )
        .toList(growable: false);
  }

  /// Human label: "Alice is typing…", "Alice and Bob are typing…", etc.
  String? statusText(String threadKey) {
    final list = typers(threadKey);
    if (list.isEmpty) return null;
    String name(int i) {
      final n = list[i].displayName;
      if (n.length > 16) return '${n.substring(0, 14)}…';
      return n;
    }

    if (list.length == 1) return '${name(0)} is typing…';
    if (list.length == 2) return '${name(0)} and ${name(1)} are typing…';
    return '${name(0)} and ${list.length - 1} others are typing…';
  }

  void clearThread(String threadKey) => _byThread.remove(threadKey);

  void clear() => _byThread.clear();

  void _purge(String threadKey) {
    final map = _byThread[threadKey];
    if (map == null) return;
    final now = DateTime.now().toUtc();
    map.removeWhere((_, v) => v.expiresAt.isBefore(now));
    if (map.isEmpty) _byThread.remove(threadKey);
  }
}

final class _TypingPeer {
  final String peerId;
  final String displayName;
  final DateTime expiresAt;

  _TypingPeer({
    required this.peerId,
    required this.displayName,
    required this.expiresAt,
  });
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core/core.dart';

import 'emoji_picker.dart';

/// Scrollable chat transcript with time separators and RCS-style reactions.
class ChatMessageList extends StatelessWidget {
  final List<ChatLine> lines;
  final ScrollController? controller;

  /// Local device id (for highlighting own reactions).
  final String? localId;

  /// Resolve a friendlier name for [peerId] when [ChatLine.senderName] is empty.
  final String Function(String peerId)? resolveName;

  /// Called when the user picks a reaction emoji for a message.
  final void Function(ChatLine line, String emoji)? onReact;

  /// Long-press / details (optional).
  final void Function(ChatLine line)? onLongPress;

  const ChatMessageList({
    super.key,
    required this.lines,
    this.controller,
    this.localId,
    this.resolveName,
    this.onReact,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(
        child: Text(
          'No messages yet',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      );
    }

    final items = _buildItems(lines);

    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return switch (item) {
          _TimeSep(:final at) => _TimeSeparator(at: at),
          _Msg(
            :final line,
            :final showSender,
            :final clusteredTop,
            :final clusteredBottom,
          ) =>
            ChatBubble(
              line: line,
              showSender: showSender,
              clusteredTop: clusteredTop,
              clusteredBottom: clusteredBottom,
              localId: localId,
              resolveName: resolveName,
              onReact: onReact == null ? null : (e) => onReact!(line, e),
              onLongPress:
                  onLongPress == null ? null : () => onLongPress!(line),
            ),
        };
      },
    );
  }

  static List<_ChatItem> _buildItems(List<ChatLine> lines) {
    final out = <_ChatItem>[];
    ChatLine? prev;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1] : null;

      if (line.isSystem) {
        out.add(_Msg(
          line: line,
          showSender: false,
          clusteredTop: false,
          clusteredBottom: false,
        ));
        prev = line;
        continue;
      }

      final gapFromPrev = prev == null ||
          line.timestamp.difference(prev.timestamp).abs() >=
              chatTimeSeparatorGap ||
          prev.isSystem;
      if (gapFromPrev) {
        out.add(_TimeSep(at: line.timestamp));
      }

      final sameSenderAsPrev = prev != null &&
          !prev.isSystem &&
          prev.isLocal == line.isLocal &&
          prev.peerId == line.peerId &&
          !gapFromPrev;
      final sameSenderAsNext = next != null &&
          !next.isSystem &&
          next.isLocal == line.isLocal &&
          next.peerId == line.peerId &&
          next.timestamp.difference(line.timestamp).abs() <
              chatTimeSeparatorGap;

      // Show sender when remote and first in a cluster (or after time gap).
      final showSender = !line.isLocal && !sameSenderAsPrev;

      out.add(
        _Msg(
          line: line,
          showSender: showSender,
          clusteredTop: sameSenderAsPrev,
          clusteredBottom: sameSenderAsNext,
        ),
      );
      prev = line;
    }
    return out;
  }
}

sealed class _ChatItem {}

final class _TimeSep extends _ChatItem {
  final DateTime at;
  _TimeSep({required this.at});
}

final class _Msg extends _ChatItem {
  final ChatLine line;
  final bool showSender;
  final bool clusteredTop;
  final bool clusteredBottom;
  _Msg({
    required this.line,
    required this.showSender,
    required this.clusteredTop,
    required this.clusteredBottom,
  });
}

class _TimeSeparator extends StatelessWidget {
  final DateTime at;
  const _TimeSeparator({required this.at});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            formatChatTimestamp(at),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ),
    );
  }
}

/// Human-friendly chat timestamp (Today 3:42 PM / Yesterday / date).
String formatChatTimestamp(DateTime utc) {
  final t = utc.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final time = _formatTime(t);

  if (day == today) return time;
  if (day == today.subtract(const Duration(days: 1))) {
    return 'Yesterday · $time';
  }
  if (now.difference(t).inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[t.weekday - 1]} · $time';
  }
  return '${t.month}/${t.day}/${t.year} · $time';
}

String _formatTime(DateTime t) {
  final h24 = t.hour;
  final h = h24 % 12 == 0 ? 12 : h24 % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final ap = h24 >= 12 ? 'PM' : 'AM';
  return '$h:$m $ap';
}

/// Single chat bubble with optional sender label and reaction chips.
class ChatBubble extends StatelessWidget {
  final ChatLine line;
  final bool showSender;
  final bool clusteredTop;
  final bool clusteredBottom;
  final String? localId;
  final String Function(String peerId)? resolveName;
  final ValueChanged<String>? onReact;
  final VoidCallback? onLongPress;

  const ChatBubble({
    super.key,
    required this.line,
    this.showSender = true,
    this.clusteredTop = false,
    this.clusteredBottom = false,
    this.localId,
    this.resolveName,
    this.onReact,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (line.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
        child: Center(
          child: Text(
            line.text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final isLocal = line.isLocal;
    final bg = isLocal ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = isLocal ? scheme.onPrimary : scheme.onSurface;

    final top = clusteredTop ? 3.0 : 10.0;
    final bottom = clusteredBottom ? 3.0 : 10.0;
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isLocal ? 18 : (clusteredTop ? 6 : 18)),
      topRight: Radius.circular(isLocal ? (clusteredTop ? 6 : 18) : 18),
      bottomLeft: Radius.circular(isLocal ? 18 : (clusteredBottom ? 6 : 18)),
      bottomRight: Radius.circular(isLocal ? (clusteredBottom ? 6 : 18) : 18),
    );

    String? sender;
    if (showSender && !isLocal) {
      if (line.senderName != null && line.senderName!.isNotEmpty) {
        sender = line.senderName;
      } else if (line.peerId != null && resolveName != null) {
        sender = resolveName!(line.peerId!);
      } else {
        sender = line.displaySender;
      }
    }

    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: Column(
        crossAxisAlignment:
            isLocal ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (sender != null)
            Padding(
              padding: EdgeInsets.only(
                left: isLocal ? 0 : 14,
                right: isLocal ? 14 : 0,
                bottom: 3,
              ),
              child: Text(
                sender,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Align(
            alignment: isLocal ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78,
              ),
              child: GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  if (onReact != null) {
                    _showReactionPicker(context);
                  } else {
                    onLongPress?.call();
                  }
                },
                onDoubleTap: onReact == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onReact!('👍');
                      },
                child: Column(
                  crossAxisAlignment: isLocal
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: radius,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: line.isImage ? 6 : 14,
                          vertical: line.isImage ? 6 : 9,
                        ),
                        child: line.isImage
                            ? _ChatImageBody(
                                line: line,
                                fg: fg,
                                onOpen: () => _openImage(context, line),
                              )
                            : Text(
                                line.text,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: fg,
                                      height: 1.3,
                                    ),
                              ),
                      ),
                    ),
                    if (line.reactions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: _ReactionBar(
                          reactions: line.reactions,
                          localId: localId,
                          isLocal: isLocal,
                          onTap: onReact,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReactionPicker(BuildContext context) async {
    final emoji = await EmojiPicker.show(
      context,
      title: 'React',
      showQuickReactions: true,
    );
    if (emoji != null) onReact?.call(emoji);
  }

  void _openImage(BuildContext context, ChatLine line) {
    final bytes = line.imageBytes;
    if (bytes == null || bytes.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              InteractiveViewer(
                child: Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Icon(Icons.broken_image, color: Colors.white54),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              if (line.imageName != null && line.imageName!.isNotEmpty)
                Positioned(
                  left: 12,
                  right: 48,
                  bottom: 12,
                  child: Text(
                    line.imageName!,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatImageBody extends StatelessWidget {
  final ChatLine line;
  final Color fg;
  final VoidCallback onOpen;

  const _ChatImageBody({
    required this.line,
    required this.fg,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final bytes = line.imageBytes!;
    final caption = line.text;
    final showCaption = caption.isNotEmpty &&
        !caption.startsWith('📷 ') &&
        !caption.contains('(waiting for parent OK)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onOpen,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 260,
                maxHeight: 320,
                minWidth: 120,
                minHeight: 80,
              ),
              child: Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 160,
                  height: 100,
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: Icon(Icons.broken_image_outlined, color: fg),
                ),
              ),
            ),
          ),
        ),
        if (showCaption) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Text(
              caption,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: fg,
                    height: 1.25,
                  ),
            ),
          ),
        ] else if (line.imageName != null && line.imageName!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              line.imageName!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.8),
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _ReactionBar extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String? localId;
  final bool isLocal;
  final ValueChanged<String>? onTap;

  const _ReactionBar({
    required this.reactions,
    this.localId,
    required this.isLocal,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = reactions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: isLocal ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final e in entries)
          Material(
            color: e.value.contains(localId)
                ? scheme.primaryContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap == null ? null : () => onTap!(e.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  e.value.length > 1 ? '${e.key} ${e.value.length}' : e.key,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact “is typing…” bar above the composer.
class TypingStatusBar extends StatelessWidget {
  final String? text;

  const TypingStatusBar({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.isEmpty) {
      return const SizedBox(height: 0);
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: _TypingDots(color: scheme.primary),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text!,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (i) {
            final phase = (_c.value + i * 0.2) % 1.0;
            final o = 0.35 + 0.65 * (1 - (phase - 0.5).abs() * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Opacity(
                opacity: o.clamp(0.3, 1.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Composer row with emoji picker + photo attach + send (texting-style).
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final String hintText;
  final bool enabled;

  /// Fired while the user is composing (true) or idle/cleared (false).
  final ValueChanged<bool>? onTypingChanged;

  /// Pick and send a photo (parent handles picker + [MeshController.sendChatImage]).
  final VoidCallback? onAttachPhoto;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.hintText = 'Message',
    this.enabled = true,
    this.onTypingChanged,
    this.onAttachPhoto,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _emojiOpen = false;
  bool _notifiedTyping = false;

  @override
  void dispose() {
    if (_notifiedTyping) {
      widget.onTypingChanged?.call(false);
    }
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onTypingChanged?.call(false);
    _notifiedTyping = false;
    widget.onSend(text);
    _controller.clear();
    setState(() {});
  }

  void _onChanged(String value) {
    final has = value.trim().isNotEmpty;
    if (has) {
      widget.onTypingChanged?.call(true);
      _notifiedTyping = true;
    } else if (_notifiedTyping) {
      widget.onTypingChanged?.call(false);
      _notifiedTyping = false;
    }
    setState(() {});
  }

  void _insertEmoji(String emoji) {
    final t = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : t.length;
    final end = sel.isValid ? sel.end : t.length;
    final next = t.replaceRange(start, end, emoji);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    _onChanged(next);
  }

  Future<void> _toggleEmoji() async {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _focus.requestFocus();
      return;
    }
    setState(() => _emojiOpen = true);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasText = _controller.text.trim().isNotEmpty;

    return Material(
      color: scheme.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Emoji',
                    onPressed: widget.enabled ? _toggleEmoji : null,
                    icon: Icon(
                      _emojiOpen
                          ? Icons.keyboard_outlined
                          : Icons.emoji_emotions_outlined,
                    ),
                  ),
                  if (widget.onAttachPhoto != null)
                    IconButton(
                      tooltip: 'Photo',
                      onPressed: widget.enabled ? widget.onAttachPhoto : null,
                      icon: const Icon(Icons.image_outlined),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onTap: () {
                        if (_emojiOpen) setState(() => _emojiOpen = false);
                      },
                      onChanged: _onChanged,
                      decoration: InputDecoration(
                        hintText: widget.hintText,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: widget.enabled && hasText ? _submit : null,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
            if (_emojiOpen)
              EmojiPicker(
                height: 260,
                showQuickReactions: true,
                onSelected: _insertEmoji,
              ),
          ],
        ),
      ),
    );
  }
}

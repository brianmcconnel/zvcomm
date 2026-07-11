import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Scrollable chat transcript.
class ChatMessageList extends StatelessWidget {
  final List<ChatLine> lines;
  final ScrollController? controller;

  const ChatMessageList({
    super.key,
    required this.lines,
    this.controller,
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
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, i) => ChatBubble(line: lines[i]),
    );
  }
}

/// Single chat bubble.
class ChatBubble extends StatelessWidget {
  final ChatLine line;

  const ChatBubble({super.key, required this.line});

  @override
  Widget build(BuildContext context) {
    if (line.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(
            line.text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                  fontStyle: FontStyle.italic,
                ),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final align = line.isLocal ? Alignment.centerRight : Alignment.centerLeft;
    final bg =
        line.isLocal ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = line.isLocal ? scheme.onPrimaryContainer : scheme.onSurface;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Card(
          color: bg,
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!line.isLocal && line.peerId != null)
                  Text(
                    line.peerId!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: fg.withValues(alpha: 0.7),
                        ),
                  ),
                Text(line.text, style: TextStyle(color: fg)),
                const SizedBox(height: 2),
                Text(
                  _formatTime(line.timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.6),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    final l = t.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Composer row with send button.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final String hintText;
  final bool enabled;

  const ChatComposer({
    super.key,
    required this.onSend,
    this.hintText = 'Message',
    this.enabled = true,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: widget.enabled,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.enabled ? _submit : null,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

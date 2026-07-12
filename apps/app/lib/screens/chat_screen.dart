import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

/// Full-featured texting-style chat with reactions and smart timestamps.
class ChatScreen extends StatefulWidget {
  final MeshController mesh;

  const ChatScreen({super.key, required this.mesh});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();

  MeshController get mesh => widget.mesh;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String get _title {
    final groupId = mesh.selectedGroupId;
    if (groupId != null) {
      return mesh.groups[groupId]?.name ?? 'Group';
    }
    final peerId = mesh.selectedPeerId;
    if (peerId == null) return 'Everyone';
    final p = mesh.peers[peerId];
    if (p?.displayName.isNotEmpty == true) return p!.displayName;
    return peerId.length > 10 ? '${peerId.substring(0, 10)}…' : peerId;
  }

  IconData get _icon {
    if (mesh.selectedGroupId != null) return Icons.groups;
    if (mesh.selectedPeerId == null) return Icons.campaign;
    return Icons.person;
  }

  String _resolveName(String peerId) {
    final p = mesh.peers[peerId];
    if (p != null && p.displayName.isNotEmpty) return p.displayName;
    final cred = mesh.trustedCredentials[peerId];
    if (cred != null && cred.displayName.isNotEmpty) return cred.displayName;
    return peerId.length > 10 ? '${peerId.substring(0, 10)}…' : peerId;
  }

  Future<void> _pickConversation() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Everyone'),
                selected:
                    mesh.selectedPeerId == null && mesh.selectedGroupId == null,
                onTap: () {
                  mesh.selectPeer(null);
                  Navigator.pop(context);
                },
              ),
              if (mesh.groups.all.isNotEmpty) ...[
                const Divider(height: 1),
                for (final g in mesh.groups.all)
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(g.name),
                    selected: mesh.selectedGroupId == g.id,
                    onTap: () {
                      mesh.selectGroup(g.id);
                      Navigator.pop(context);
                    },
                  ),
              ],
              if (mesh.visiblePeers.isNotEmpty) ...[
                const Divider(height: 1),
                for (final p in mesh.visiblePeers)
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(
                      p.displayName.isEmpty ? p.id : p.displayName,
                    ),
                    selected: mesh.selectedPeerId == p.id,
                    onTap: () {
                      mesh.selectPeer(p.id);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _scrollToEnd() async {
    if (!_scroll.hasClients) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  Future<void> _composeDiscussNoteFromChat() async {
    final textCtrl = TextEditingController();
    var discretion = NoteDiscretion.parents;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('Discuss first'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Tell your parents what you want to talk about before you send a message. Teachers never see this.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: textCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Note',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 3,
                      maxLines: 5,
                    ),
                    for (final d in NoteDiscretion.values)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          discretion == d
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        title: Text(d.shortLabel),
                        subtitle: Text(
                          d.blurb,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onTap: () => setLocal(() => discretion = d),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok == true && textCtrl.text.trim().isNotEmpty) {
      try {
        await mesh.sendDiscussNote(
          text: textCtrl.text,
          discretion: discretion,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Discuss note sent to parents')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$e')),
          );
        }
      }
    }
    textCtrl.dispose();
  }

  Future<void> _pickAndSendPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Could not read image bytes')),
        );
        return;
      }
      var mime = 'image/jpeg';
      final name = file.name;
      final lower = name.toLowerCase();
      if (lower.endsWith('.png')) {
        mime = 'image/png';
      } else if (lower.endsWith('.gif')) {
        mime = 'image/gif';
      } else if (lower.endsWith('.webp')) {
        mime = 'image/webp';
      } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        mime = 'image/jpeg';
      } else if (file.extension != null) {
        mime = 'image/${file.extension}';
      }

      await mesh.sendChatImage(
        bytes: bytes,
        fileName: name.isEmpty ? 'photo.jpg' : name,
        mimeType: mime,
      );
      await _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not send photo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final peerId = mesh.selectedPeerId;
    final groupId = mesh.selectedGroupId;
    final group = groupId != null ? mesh.groups[groupId] : null;
    final lines = group != null
        ? mesh.chat.groupThread(group.id)
        : mesh.chat.thread(peerId);

    final policy = mesh.familySafety.myPolicy;
    final pendingForParent = mesh.familySafety.pendingApprovals.length;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            dense: true,
            leading: Icon(_icon),
            title: Text(_title),
            onTap: _pickConversation,
            trailing: PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) async {
                switch (v) {
                  case 'switch':
                    await _pickConversation();
                  case 'broadcast':
                    setState(() => mesh.selectPeer(null));
                  case 'file':
                    await mesh.sendDemoFile();
                  case 'discuss':
                    await _composeDiscussNoteFromChat();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'switch',
                  child: Text('Switch chat…'),
                ),
                const PopupMenuItem(
                  value: 'broadcast',
                  child: Text('Everyone'),
                ),
                if (policy?.mode == SafetyMode.teen &&
                    !(policy?.grounded ?? false))
                  const PopupMenuItem(
                    value: 'discuss',
                    child: Text('Discuss with parents first…'),
                  ),
                const PopupMenuItem(
                  value: 'file',
                  child: Text('Send demo file'),
                ),
              ],
            ),
          ),
        ),
        if (policy != null)
          Material(
            color: policy.grounded
                ? Theme.of(context).colorScheme.errorContainer
                : Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    policy.grounded
                        ? Icons.block
                        : policy.mode == SafetyMode.child
                            ? Icons.child_care
                            : Icons.visibility,
                    size: 18,
                    color: policy.grounded
                        ? Theme.of(context).colorScheme.onErrorContainer
                        : Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      policy.grounded
                          ? 'Grounded · chat and walkie paused by parent'
                          : policy.mode == SafetyMode.child
                              ? 'Kid mode · parent approves your messages'
                              : 'Teen mode · parent can see your messages',
                      style: TextStyle(
                        fontSize: 12,
                        color: policy.grounded
                            ? Theme.of(context).colorScheme.onErrorContainer
                            : Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (pendingForParent > 0)
          Material(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 18,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$pendingForParent message${pendingForParent == 1 ? '' : 's'} waiting for your OK (Settings → Family safety)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context)
                            .colorScheme
                            .onTertiaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ChatMessageList(
            lines: lines,
            controller: _scroll,
            localId: mesh.identity?.id,
            resolveName: _resolveName,
            onReact: (line, emoji) {
              mesh.reactToMessage(line.id, emoji);
            },
          ),
        ),
        TypingStatusBar(text: mesh.typingStatusForCurrentChat()),
        ChatComposer(
          enabled: mesh.running && !(policy?.grounded ?? false),
          hintText: policy?.grounded == true
              ? 'Grounded — messaging paused'
              : policy?.mode == SafetyMode.child
                  ? 'Message (parent must OK)'
                  : 'Text message',
          onTypingChanged: (typing) {
            mesh.setLocalTyping(typing);
          },
          onAttachPhoto: mesh.running && !(policy?.grounded ?? false)
              ? _pickAndSendPhoto
              : null,
          onSend: (text) async {
            await mesh.sendChat(text);
            await _scrollToEnd();
          },
        ),
      ],
    );
  }
}

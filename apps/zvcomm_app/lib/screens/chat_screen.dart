import 'package:flutter/material.dart';
import 'package:zvcomm_ui/zvcomm_ui.dart';

import '../services/mesh_controller.dart';

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

  @override
  Widget build(BuildContext context) {
    final peerId = mesh.selectedPeerId;
    final title = peerId == null
        ? 'Broadcast'
        : (mesh.peers[peerId]?.displayName.isNotEmpty == true
            ? mesh.peers[peerId]!.displayName
            : peerId);
    final lines = mesh.chat.thread(peerId);

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(peerId == null ? Icons.campaign : Icons.person),
            title: Text(title),
            subtitle: Text(
              peerId == null
                  ? 'Everyone on the mesh'
                  : 'Direct / multi-hop chat',
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'broadcast') mesh.selectPeer(null);
                if (v == 'file') mesh.sendDemoFile();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'broadcast',
                  child: Text('Switch to broadcast'),
                ),
                const PopupMenuItem(
                  value: 'file',
                  child: Text('Send demo file'),
                ),
              ],
            ),
          ),
        ),
        if (mesh.peers.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: peerId == null,
                    onSelected: (_) => setState(() => mesh.selectPeer(null)),
                  ),
                ),
                for (final p in mesh.peers.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(
                        p.displayName.isEmpty ? p.id.substring(0, 6) : p.displayName,
                      ),
                      selected: peerId == p.id,
                      onSelected: (_) => setState(() => mesh.selectPeer(p.id)),
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ChatMessageList(lines: lines, controller: _scroll),
        ),
        ChatComposer(
          enabled: mesh.running,
          hintText: peerId == null ? 'Broadcast message' : 'Message peer',
          onSend: (text) async {
            await mesh.sendChat(text);
            if (_scroll.hasClients) {
              await Future<void>.delayed(const Duration(milliseconds: 50));
              _scroll.jumpTo(_scroll.position.maxScrollExtent);
            }
          },
        ),
      ],
    );
  }
}

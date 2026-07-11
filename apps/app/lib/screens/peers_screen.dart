import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

class PeersScreen extends StatelessWidget {
  final MeshController mesh;
  final ValueChanged<String?> onOpenChat;

  const PeersScreen({
    super.key,
    required this.mesh,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final id = mesh.identity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local identity',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(
                  id?.displayName ?? '…',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (id != null)
                  SelectableText(
                    id.id,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                const SizedBox(height: 12),
                TransportStatusBar(
                  available: mesh.available,
                  powerMode: mesh.powerMode,
                ),
                if (mesh.status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    mesh.status!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Text(
                'Peers (${mesh.peers.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => onOpenChat(null),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Broadcast chat'),
              ),
            ],
          ),
        ),
        Expanded(
          child: PeerListView(
            peers: mesh.peers.values.toList(),
            emptyMessage: mesh.running
                ? 'Listening for peers…\nTap a peer to chat or send files.'
                : 'Discovery stopped',
            onPeerTap: (peer) {
              mesh.selectPeer(peer.id);
              onOpenChat(peer.id);
            },
          ),
        ),
      ],
    );
  }
}

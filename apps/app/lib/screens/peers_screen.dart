import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

class PeersScreen extends StatelessWidget {
  final MeshController mesh;
  final ValueChanged<String?> onOpenChat;

  /// Optional: jump to Settings (e.g. transport plugins) when a link icon is tapped.
  final VoidCallback? onOpenSettings;

  const PeersScreen({
    super.key,
    required this.mesh,
    required this.onOpenChat,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
          child: Row(
            children: [
              TransportLinkIcons(
                available: mesh.available,
                showMock: mesh.useMockDemo,
                onTap: (_) => onOpenSettings?.call(),
              ),
              const Spacer(),
              if (mesh.running)
                Icon(
                  Icons.sensors,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                )
              else
                Icon(
                  Icons.sensors_off,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
              const SizedBox(width: 4),
              Text(
                mesh.running ? 'Listening' : 'Stopped',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: mesh.running
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => onOpenChat(null),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Broadcast'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Peers (${mesh.peers.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: PeerListView(
            peers: mesh.peers.values.toList(),
            emptyMessage: mesh.running
                ? 'Listening for peers…\nTap a peer to chat or send files.'
                : 'Discovery stopped — start it in Settings.',
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

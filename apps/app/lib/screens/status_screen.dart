import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

class StatusScreen extends StatelessWidget {
  final MeshController mesh;

  const StatusScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final stats = mesh.node?.stats ?? MeshStats();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Network', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TransportStatusBar(
          available: mesh.available,
          powerMode: mesh.powerMode,
        ),
        const SizedBox(height: 8),
        Text(
          mesh.status ?? (mesh.running ? 'Running' : 'Stopped'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text('Mesh stats', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        MeshStatsView(
          stats: stats,
          peerCount: mesh.peers.length,
          presenceCount: mesh.livePresence.length,
        ),
        const SizedBox(height: 16),
        Text('Presence', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (mesh.livePresence.isEmpty)
          const Text('No presence advertisements yet')
        else
          ...mesh.livePresence.map(
            (p) => ListTile(
              dense: true,
              leading: const Icon(Icons.radar),
              title: Text(p.displayName.isEmpty ? p.peerId : p.displayName),
              subtitle: Text('seq ${p.sequence} · ${p.peerId}'),
            ),
          ),
        const SizedBox(height: 16),
        Text('File transfers', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (mesh.transferHistory.isEmpty)
          const Text('No transfers yet — use Chat → Send demo file')
        else
          ...mesh.transferHistory.map((p) => FileTransferTile(progress: p)),
        const SizedBox(height: 16),
        Text('Battery policy', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'Backgrounding the app enables transport power-saver and stretches '
          'presence heartbeats. Foreground restores your selected power mode.',
        ),
      ],
    );
  }
}

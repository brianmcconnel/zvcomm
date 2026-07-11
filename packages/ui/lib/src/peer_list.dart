import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Scrollable list of discovered [Peer]s.
class PeerListView extends StatelessWidget {
  final List<Peer> peers;
  final ValueChanged<Peer>? onPeerTap;
  final String emptyMessage;

  const PeerListView({
    super.key,
    required this.peers,
    this.onPeerTap,
    this.emptyMessage = 'No peers discovered yet',
  });

  @override
  Widget build(BuildContext context) {
    if (peers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.radar,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = [...peers]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView.separated(
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final peer = sorted[index];
        final title = peer.displayName.isNotEmpty ? peer.displayName : peer.id;
        final transports = peer.transports.map((t) => t.name).join(', ');
        final rssi = peer.rssi != null ? '${peer.rssi} dBm' : 'RSSI n/a';

        return ListTile(
          leading: CircleAvatar(
            child: Text(
              title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
            ),
          ),
          title: Text(title),
          subtitle: Text('$transports · $rssi · ${peer.id}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: onPeerTap == null ? null : () => onPeerTap!(peer),
        );
      },
    );
  }
}

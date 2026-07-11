import 'package:flutter/material.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

/// Transport availability chips.
class TransportStatusBar extends StatelessWidget {
  final Map<TransportKind, bool> available;
  final TransportPowerMode powerMode;

  const TransportStatusBar({
    super.key,
    required this.available,
    required this.powerMode,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final kind in [
          TransportKind.ble,
          TransportKind.nfc,
          TransportKind.wifi,
          TransportKind.mock,
        ])
          _chip(
            context,
            label: kind.name.toUpperCase(),
            on: available[kind] ?? false,
          ),
        Chip(
          avatar: const Icon(Icons.battery_saver_outlined, size: 18),
          label: Text(powerMode.name),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, {required String label, required bool on}) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(
        on ? Icons.check_circle : Icons.cancel,
        size: 18,
        color: on ? scheme.primary : scheme.outline,
      ),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Compact mesh statistics table.
class MeshStatsView extends StatelessWidget {
  final MeshStats stats;
  final int peerCount;
  final int presenceCount;

  const MeshStatsView({
    super.key,
    required this.stats,
    required this.peerCount,
    this.presenceCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final rows = {
      'Peers discovered': '$peerCount',
      'Presence live': '$presenceCount',
      ...stats.toMap().map((k, v) => MapEntry(k, '$v')),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            for (final e in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(e.key)),
                    Text(
                      e.value,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Linear progress for a file transfer.
class FileTransferTile extends StatelessWidget {
  final FileTransferProgress progress;

  const FileTransferTile({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    final label = p.failed
        ? 'Failed: ${p.error ?? "error"}'
        : p.done
            ? 'Done'
            : '${(p.fraction * 100).toStringAsFixed(0)}%';
    return ListTile(
      leading: Icon(
        p.failed
            ? Icons.error_outline
            : p.done
                ? Icons.check_circle_outline
                : Icons.upload_file,
      ),
      title: Text(p.info.fileName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${p.bytesTransferred} / ${p.info.totalBytes} B · $label',
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: p.fraction),
        ],
      ),
    );
  }
}

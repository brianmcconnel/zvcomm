import 'package:flutter/material.dart';
import 'package:core/core.dart';

/// Compact link icons for active transports (BLE / NFC / Wi‑Fi / mock).
///
/// Active links use the primary color; inactive are muted. Optional [onTap]
/// is called with the transport kind (e.g. open Settings plugins).
class TransportLinkIcons extends StatelessWidget {
  final Map<TransportKind, bool> available;
  final ValueChanged<TransportKind>? onTap;
  final bool showMock;
  final double iconSize;
  final bool showLabels;

  const TransportLinkIcons({
    super.key,
    required this.available,
    this.onTap,
    this.showMock = false,
    this.iconSize = 22,
    this.showLabels = false,
  });

  static IconData iconFor(TransportKind kind) => switch (kind) {
        TransportKind.ble => Icons.bluetooth,
        TransportKind.nfc => Icons.nfc,
        TransportKind.wifi => Icons.wifi,
        TransportKind.mock => Icons.science_outlined,
        TransportKind.uwb => Icons.cell_tower,
        TransportKind.lora => Icons.settings_input_antenna,
        TransportKind.custom => Icons.extension_outlined,
      };

  static String labelFor(TransportKind kind) => switch (kind) {
        TransportKind.ble => 'Bluetooth',
        TransportKind.nfc => 'NFC',
        TransportKind.wifi => 'Wi‑Fi',
        TransportKind.mock => 'Mock',
        TransportKind.uwb => 'UWB',
        TransportKind.lora => 'LoRa',
        TransportKind.custom => 'Custom',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kinds = <TransportKind>[
      TransportKind.ble,
      TransportKind.nfc,
      TransportKind.wifi,
      if (showMock || (available[TransportKind.mock] ?? false))
        TransportKind.mock,
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final kind in kinds) ...[
          if (kind != kinds.first) const SizedBox(width: 4),
          _LinkIcon(
            kind: kind,
            active: available[kind] ?? false,
            iconSize: iconSize,
            showLabel: showLabels,
            activeColor: scheme.primary,
            inactiveColor: scheme.outline.withValues(alpha: 0.55),
            onTap: onTap == null ? null : () => onTap!(kind),
          ),
        ],
      ],
    );
  }
}

class _LinkIcon extends StatelessWidget {
  final TransportKind kind;
  final bool active;
  final double iconSize;
  final bool showLabel;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback? onTap;

  const _LinkIcon({
    required this.kind,
    required this.active,
    required this.iconSize,
    required this.showLabel,
    required this.activeColor,
    required this.inactiveColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : inactiveColor;
    final icon = Icon(
      TransportLinkIcons.iconFor(kind),
      size: iconSize,
      color: color,
    );
    final child = showLabel
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 2),
              Text(
                TransportLinkIcons.labelFor(kind),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontSize: 10,
                    ),
              ),
            ],
          )
        : icon;

    final tooltip =
        '${TransportLinkIcons.labelFor(kind)} · ${active ? "active" : "off"}';

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Transport availability chips (full labels + power mode). Prefer
/// [TransportLinkIcons] on compact surfaces.
class TransportStatusBar extends StatelessWidget {
  final Map<TransportKind, bool> available;
  final TransportPowerMode powerMode;
  final bool showMock;

  const TransportStatusBar({
    super.key,
    required this.available,
    required this.powerMode,
    this.showMock = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TransportLinkIcons(
          available: available,
          showMock: showMock,
          showLabels: true,
          iconSize: 20,
        ),
        Chip(
          avatar: const Icon(Icons.battery_saver_outlined, size: 18),
          label: Text(powerMode.name),
          visualDensity: VisualDensity.compact,
        ),
      ],
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

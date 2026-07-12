import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

/// Task Manager–style performance dashboard with live time series.
class StatusScreen extends StatelessWidget {
  final MeshController mesh;

  const StatusScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final samples = mesh.statsHistory.samples;
    final latest = mesh.statsHistory.latest;
    final stats = mesh.node?.stats ?? MeshStats();
    final uptime = mesh.sessionUptime;
    final now = DateTime.now();

    final peerSpark = samples.map((s) => s.peerCount.toDouble()).toList();
    final activitySpark = samples.map((s) => s.activityPerSec).toList();
    final failSpark = samples.map((s) => s.failuresPerSec).toList();

    final oRate = latest?.originatedPerSec ?? 0;
    final dRate = latest?.deliveredPerSec ?? 0;
    final fRate = latest?.forwardedPerSec ?? 0;
    final act = latest?.activityPerSec ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        // ── Header: clock + uptime + status ───────────────────────────
        Card(
          color: scheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: mesh.running
                        ? Colors.greenAccent.shade400
                        : scheme.outline,
                    boxShadow: mesh.running
                        ? [
                            BoxShadow(
                              color: Colors.greenAccent.withValues(alpha: 0.5),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mesh.running ? 'Mesh running' : 'Mesh stopped',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        mesh.status ?? mesh.powerMode.name,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatClock(now),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Up ${formatUptime(uptime)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── KPI row ───────────────────────────────────────────────────
        LayoutBuilder(
          builder: (context, c) {
            final wide = c.maxWidth > 420;
            final cards = [
              MetricCard(
                label: 'Peers',
                value: '${mesh.peers.length}',
                icon: Icons.people_outline,
                accent: scheme.tertiary,
                sparkline: peerSpark,
              ),
              MetricCard(
                label: 'Activity',
                value:
                    act >= 10 ? act.toStringAsFixed(0) : act.toStringAsFixed(1),
                unit: '/s',
                icon: Icons.speed,
                accent: scheme.primary,
                sparkline: activitySpark,
              ),
              MetricCard(
                label: 'Originated',
                value: '${stats.originated}',
                unit: oRate > 0 ? '+${oRate.toStringAsFixed(1)}/s' : null,
                icon: Icons.upload_outlined,
                accent: Colors.lightBlueAccent,
              ),
              MetricCard(
                label: 'Failures',
                value: '${stats.sendFailures}',
                unit: (latest?.failuresPerSec ?? 0) > 0 ? '/s' : null,
                icon: Icons.error_outline,
                accent: scheme.error,
                sparkline: failSpark,
              ),
            ];
            if (wide) {
              return Row(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(child: cards[i]),
                  ],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 8),
                    Expanded(child: cards[1]),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: cards[2]),
                    const SizedBox(width: 8),
                    Expanded(child: cards[3]),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),

        // ── Main performance chart ────────────────────────────────────
        TimeSeriesChart(
          title: 'Mesh throughput',
          subtitle: samples.length >= 2
              ? 'last ${formatUptime(samples.last.at.difference(samples.first.at))}'
              : 'sampling…',
          height: 140,
          samples: samples,
          lines: [
            TimeSeriesLine(
              label: 'Originated/s',
              color: Colors.lightBlueAccent,
              value: (s) => s.originatedPerSec,
            ),
            TimeSeriesLine(
              label: 'Delivered/s',
              color: scheme.primary,
              value: (s) => s.deliveredPerSec,
            ),
            TimeSeriesLine(
              label: 'Forwarded/s',
              color: scheme.tertiary,
              value: (s) => s.forwardedPerSec,
            ),
          ],
        ),
        const SizedBox(height: 10),

        TimeSeriesChart(
          title: 'Topology',
          subtitle: 'peers & presence',
          height: 100,
          samples: samples,
          lines: [
            TimeSeriesLine(
              label: 'Peers',
              color: scheme.tertiary,
              value: (s) => s.peerCount.toDouble(),
            ),
            TimeSeriesLine(
              label: 'Presence',
              color: Colors.amberAccent,
              value: (s) => s.presenceCount.toDouble(),
              fill: false,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Transports (process list) ─────────────────────────────────
        Text(
          'Transports',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                for (final kind in [
                  TransportKind.ble,
                  TransportKind.wifi,
                  TransportKind.nfc,
                  if (mesh.useMockDemo) TransportKind.mock,
                ])
                  ActivityRow(
                    icon: TransportLinkIcons.iconFor(kind),
                    title: TransportLinkIcons.labelFor(kind),
                    subtitle: (mesh.available[kind] ?? false)
                        ? 'Active · ${mesh.powerMode.name}'
                        : 'Offline',
                    active: mesh.available[kind] ?? false,
                    activity: (mesh.available[kind] ?? false)
                        ? (0.15 + (act / 20).clamp(0.0, 0.85))
                        : 0,
                    color: TransportLinkIcons.iconFor(kind) == Icons.bluetooth
                        ? Colors.blueAccent
                        : null,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Lifetime counters ─────────────────────────────────────────
        Text(
          'Lifetime',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _counterRow(context, 'Delivered', stats.delivered, dRate),
                _counterRow(context, 'Forwarded', stats.forwarded, fRate),
                _counterRow(context, 'Flooded', stats.flooded, null),
                _counterRow(
                    context, 'Unicast routed', stats.unicastRouted, null),
                _counterRow(
                  context,
                  'Duplicates dropped',
                  stats.duplicatesDropped,
                  null,
                ),
                _counterRow(context, 'TTL expired', stats.ttlExpired, null),
                _counterRow(context, 'Presence sent', stats.presenceSent, null),
                _counterRow(
                  context,
                  'Presence received',
                  stats.presenceReceived,
                  null,
                ),
              ],
            ),
          ),
        ),

        // ── Presence / transfers (collapsed) ──────────────────────────
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Presence (${mesh.livePresence.length})'),
          children: [
            if (mesh.livePresence.isEmpty)
              const ListTile(
                dense: true,
                title: Text('None yet'),
              )
            else
              for (final p in mesh.livePresence)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.radar, size: 18),
                  title: Text(
                    p.displayName.isEmpty ? p.peerId : p.displayName,
                  ),
                  subtitle: Text('seq ${p.sequence}'),
                ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Transfers (${mesh.transferHistory.length})'),
          children: [
            if (mesh.transferHistory.isEmpty)
              const ListTile(
                dense: true,
                title: Text('None yet'),
              )
            else
              for (final p in mesh.transferHistory)
                FileTransferTile(progress: p),
          ],
        ),
      ],
    );
  }

  Widget _counterRow(
    BuildContext context,
    String label,
    int total,
    double? rate,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          if (rate != null && rate > 0.05)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                '+${rate.toStringAsFixed(1)}/s',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          SizedBox(
            width: 56,
            child: Text(
              '$total',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

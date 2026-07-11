import 'package:flutter/material.dart';
import 'package:core/core.dart';

import '../services/mesh_controller.dart';

class SettingsScreen extends StatelessWidget {
  final MeshController mesh;

  const SettingsScreen({super.key, required this.mesh});

  @override
  Widget build(BuildContext context) {
    final plugins = mesh.plugins;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Discovery', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('Mesh discovery'),
          subtitle: Text(mesh.running ? 'Active' : 'Stopped'),
          value: mesh.running,
          onChanged: (_) => mesh.toggleDiscovery(),
        ),
        SwitchListTile(
          title: const Text('Mock demo peer'),
          subtitle: const Text('In-process peer for UI demos without radios'),
          value: mesh.useMockDemo,
          onChanged: mesh.setUseMockDemo,
        ),
        const SizedBox(height: 16),
        Text(
          'Transport plugins',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Enable or disable backends at runtime (Phase 5). Stubs stay off until '
          'real hardware plugins replace them.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final p in plugins)
          SwitchListTile(
            title: Text(p.name),
            subtitle: Text(
              '${p.id} · ${p.kind.name}'
              '${p.description.isNotEmpty ? "\n${p.description}" : ""}',
            ),
            isThreeLine: p.description.isNotEmpty,
            value: mesh.pluginEnabled[p.id] ?? p.enabledByDefault,
            onChanged: (v) => mesh.setPluginEnabled(p.id, v),
          ),
        const SizedBox(height: 8),
        Text('Power mode', style: Theme.of(context).textTheme.titleMedium),
        for (final mode in TransportPowerMode.values)
          ListTile(
            title: Text(mode.name),
            leading: Icon(
              mesh.powerMode == mode
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
            ),
            selected: mesh.powerMode == mode,
            onTap: () => mesh.setPowerMode(mode),
          ),
        const SizedBox(height: 16),
        Text('About', style: Theme.of(context).textTheme.titleMedium),
        const ListTile(
          title: Text('ZVComm'),
          subtitle: Text(
            'Short-range mesh · Apache-2.0 · Phase 5\n'
            'Pluggable transports · hardware adapters',
          ),
        ),
        ListTile(
          title: const Text('Local ID'),
          subtitle: SelectableText(mesh.identity?.id ?? '—'),
        ),
        ListTile(
          title: const Text('Active transports'),
          subtitle: Text(
            '${mesh.transportManager?.transports.length ?? 0} · '
            '${mesh.transportManager?.transports.map((t) => t.name).join(", ") ?? "—"}',
          ),
        ),
      ],
    );
  }
}

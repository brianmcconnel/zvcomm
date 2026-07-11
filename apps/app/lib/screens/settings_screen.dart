import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

class SettingsScreen extends StatelessWidget {
  final MeshController mesh;
  final ThemeController themeController;

  const SettingsScreen({
    super.key,
    required this.mesh,
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    final plugins = mesh.plugins;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => ThemePicker(controller: themeController),
        ),
        const SizedBox(height: 24),
        Text('Discovery', style: Theme.of(context).textTheme.titleMedium),
        SwitchListTile(
          title: const Text('Mesh discovery'),
          subtitle: Text(mesh.running ? 'Active' : 'Stopped'),
          value: mesh.running,
          onChanged: (_) => mesh.toggleDiscovery(),
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
            'Themes aligned with ZVBible · pluggable transports',
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
        const SizedBox(height: 16),
        ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.developer_mode_outlined),
          title: const Text('Developer'),
          subtitle: const Text('Diagnostics and in-process mock radio'),
          children: [
            SwitchListTile(
              title: const Text('Mock demo peer'),
              subtitle: const Text(
                'Off by default. Adds an in-process peer for UI demos '
                'without real radios (BLE/NFC/Wi‑Fi).',
              ),
              value: mesh.useMockDemo,
              onChanged: (v) => mesh.setUseMockDemo(v),
            ),
          ],
        ),
      ],
    );
  }
}

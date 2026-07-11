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
    final id = mesh.identity;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => ThemePicker(controller: themeController),
        ),
        const SizedBox(height: 24),
        Text('This device', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id?.displayName.isNotEmpty == true
                      ? id!.displayName
                      : 'This device',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  id?.id ?? '—',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Links',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                TransportLinkIcons(
                  available: mesh.available,
                  showMock: mesh.useMockDemo,
                  showLabels: true,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    mesh.running ? Icons.sensors : Icons.sensors_off,
                    color: mesh.running ? scheme.primary : scheme.outline,
                  ),
                  title: Text(
                      mesh.running ? 'Discovery active' : 'Discovery stopped'),
                  subtitle: Text(
                    mesh.status ??
                        (mesh.running
                            ? 'Foreground · ${mesh.powerMode.name}'
                            : 'Start discovery to scan for peers'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
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
          'Enable or disable backends at runtime. Stubs stay off until '
          'real hardware plugins replace them.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final p in plugins)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: Icon(
              TransportLinkIcons.iconFor(p.kind),
              color: (mesh.available[p.kind] ?? false)
                  ? scheme.primary
                  : scheme.outline,
            ),
            title: Text(p.name),
            subtitle: Text(
              '${p.kind.name}'
              '${p.description.isNotEmpty ? " · ${p.description}" : ""}',
            ),
            value: mesh.pluginEnabled[p.id] ?? p.enabledByDefault,
            onChanged: (v) => mesh.setPluginEnabled(p.id, v),
          ),
        const SizedBox(height: 8),
        Text('Power mode', style: Theme.of(context).textTheme.titleMedium),
        Text(
          'Controls scan duty cycle and battery use. Backgrounding the app '
          'forces power-saver until you return to the foreground.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (final mode in TransportPowerMode.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
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
          contentPadding: EdgeInsets.zero,
          title: ZvcommTitle(
            'ZVComm',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          subtitle: Text(
            'Short-range mesh · Apache-2.0 · Phase 5\n'
            'Themes aligned with ZVBible · pluggable transports',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active transports'),
          subtitle: Text(
            '${mesh.transportManager?.transports.length ?? 0} · '
            '${mesh.transportManager?.transports.map((t) => t.name).join(", ") ?? "—"}',
          ),
        ),
        const SizedBox(height: 8),
        ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.zero,
          leading: const Icon(Icons.developer_mode_outlined),
          title: const Text('Developer'),
          subtitle: const Text('Diagnostics and in-process mock radio'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
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

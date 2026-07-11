import 'package:flutter/material.dart';

import '../services/mesh_controller.dart';
import 'chat_screen.dart';
import 'peers_screen.dart';
import 'settings_screen.dart';
import 'status_screen.dart';

class HomeShell extends StatefulWidget {
  final MeshController mesh;

  const HomeShell({super.key, required this.mesh});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  MeshController get mesh => widget.mesh;

  @override
  Widget build(BuildContext context) {
    final pages = [
      PeersScreen(
        mesh: mesh,
        onOpenChat: (peerId) {
          mesh.selectPeer(peerId);
          setState(() => _index = 1);
        },
      ),
      ChatScreen(mesh: mesh),
      StatusScreen(mesh: mesh),
      SettingsScreen(mesh: mesh),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZVComm'),
        actions: [
          IconButton(
            tooltip: 'Cycle power mode',
            onPressed: mesh.cyclePowerMode,
            icon: const Icon(Icons.battery_saver_outlined),
          ),
          IconButton(
            tooltip: mesh.running ? 'Stop discovery' : 'Start discovery',
            onPressed: mesh.toggleDiscovery,
            icon: Icon(
              mesh.running
                  ? Icons.stop_circle_outlined
                  : Icons.play_circle_outline,
            ),
          ),
        ],
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.radar_outlined),
            selectedIcon: Icon(Icons.radar),
            label: 'Peers',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Status',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

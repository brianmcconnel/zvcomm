import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';
import 'calendar_screen.dart';
import 'chat_screen.dart';
import 'credentials_screen.dart';
import 'peers_screen.dart';
import 'settings_screen.dart';
import 'status_screen.dart';
import 'walkie_screen.dart';

class HomeShell extends StatefulWidget {
  final MeshController mesh;
  final ThemeController themeController;

  const HomeShell({
    super.key,
    required this.mesh,
    required this.themeController,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  /// Visible body:
  /// 0 Peers · 1 Chat · 2 Walkie · 3 Calendar · 4 Creds · 5 Status · 6 Settings
  int _page = 0;

  /// Bottom-nav highlight (primary destinations 0–3).
  int _nav = 0;

  MeshController get mesh => widget.mesh;

  static const _pageCreds = 4;
  static const _pageStatus = 5;
  static const _pageSettings = 6;

  void _openPrimary(int i) {
    setState(() {
      _nav = i;
      _page = i;
    });
  }

  void _openPage(int page) {
    setState(() => _page = page);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      PeersScreen(
        mesh: mesh,
        onOpenChat: (peerId) {
          mesh.selectPeer(peerId);
          _openPrimary(1);
        },
        onOpenSettings: () => _openPage(_pageSettings),
      ),
      ChatScreen(mesh: mesh),
      WalkieScreen(mesh: mesh),
      CalendarScreen(mesh: mesh),
      CredentialsScreen(mesh: mesh),
      StatusScreen(mesh: mesh),
      SettingsScreen(
        mesh: mesh,
        themeController: widget.themeController,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const ZvcommTitle.appBar(),
        actions: [
          IconButton(
            tooltip: 'Share credentials',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () => _openPage(_pageCreds),
          ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu),
            position: PopupMenuPosition.under,
            onSelected: (v) {
              switch (v) {
                case 'creds':
                  _openPage(_pageCreds);
                case 'status':
                  _openPage(_pageStatus);
                case 'settings':
                  _openPage(_pageSettings);
                case 'theme':
                  widget.themeController.cycle();
                case 'power':
                  mesh.cyclePowerMode();
                case 'discovery':
                  mesh.toggleDiscovery();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'creds',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.qr_code_2_outlined),
                  title: Text('Credentials'),
                ),
              ),
              const PopupMenuItem(
                value: 'status',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insights_outlined),
                  title: Text('Status'),
                ),
              ),
              const PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.settings_outlined),
                  title: Text('Settings'),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'discovery',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    mesh.running
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outline,
                  ),
                  title: Text(
                    mesh.running ? 'Stop discovery' : 'Start discovery',
                  ),
                ),
              ),
              PopupMenuItem(
                value: 'power',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.battery_saver_outlined),
                  title: Text('Power: ${mesh.powerMode.name}'),
                ),
              ),
              const PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.palette_outlined),
                  title: Text('Cycle theme'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: IndexedStack(index: _page, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _nav.clamp(0, 3),
        onDestinationSelected: _openPrimary,
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
            icon: Icon(Icons.wifi_tethering_outlined),
            selectedIcon: Icon(Icons.wifi_tethering),
            label: 'Walkie',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Calendar',
          ),
        ],
      ),
    );
  }
}

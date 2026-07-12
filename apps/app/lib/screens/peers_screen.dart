import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

class PeersScreen extends StatefulWidget {
  final MeshController mesh;
  final ValueChanged<String?> onOpenChat;

  /// Optional: jump to Settings (e.g. transport plugins) when a link icon is tapped.
  final VoidCallback? onOpenSettings;

  const PeersScreen({
    super.key,
    required this.mesh,
    required this.onOpenChat,
    this.onOpenSettings,
  });

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// 0 = list, 1 = map (People tab only).
  int _peopleView = 0;

  MeshController get mesh => widget.mesh;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'People'),
            Tab(text: 'Groups'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildPeers(),
              _buildGroups(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPeers() {
    final peers = mesh.visiblePeers;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              SegmentedButton<int>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.list, size: 18),
                    label: Text('List'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.radar, size: 18),
                    label: Text('Map'),
                  ),
                ],
                selected: {_peopleView},
                onSelectionChanged: (s) =>
                    setState(() => _peopleView = s.first),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) {
                  switch (v) {
                    case 'broadcast':
                      mesh.selectPeer(null);
                      widget.onOpenChat(null);
                    case 'blocked':
                      _showBlockedSheet();
                    case 'links':
                      widget.onOpenSettings?.call();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'broadcast',
                    child: Text('Chat with everyone'),
                  ),
                  PopupMenuItem(
                    value: 'blocked',
                    child: Text(
                      'Blocked${mesh.blockList.length == 0 ? '' : ' (${mesh.blockList.length})'}',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'links',
                    child: Text('Transport links…'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_peopleView == 1) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: PeerMapView(
              peers: peers,
              selectedPeerId: mesh.selectedPeerId,
              height: 300,
              onPeerTap: (peer) {
                mesh.selectPeer(peer.id);
                widget.onOpenChat(peer.id);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              peers.any((p) => p.metadata.containsKey('x'))
                  ? 'Sim positions · tap a peer to chat'
                  : 'RSSI proximity · tap a peer to chat',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
        ],
        Expanded(
          child: _peopleView == 1
              ? (peers.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      // Compact list under map for names.
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) =>
                          _peerTile(peers[index], dense: true),
                    ))
              : (peers.isEmpty
                  ? Center(
                      child: Text(
                        mesh.running
                            ? 'No peers yet'
                            : 'Start discovery in menu',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: peers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _peerTile(peers[index]),
                    )),
        ),
      ],
    );
  }

  Widget _peerTile(Peer peer, {bool dense = false}) {
    final title = peer.displayName.isNotEmpty ? peer.displayName : peer.id;
    return ListTile(
      dense: dense,
      selected: mesh.selectedPeerId == peer.id,
      leading: CircleAvatar(
        radius: dense ? 14 : 20,
        child: Text(
          title.isNotEmpty ? title.characters.first.toUpperCase() : '?',
        ),
      ),
      title: Text(title),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _onPeerAction(v, peer),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'chat', child: Text('Chat')),
          const PopupMenuItem(value: 'walkie', child: Text('Walkie')),
          const PopupMenuItem(value: 'add_group', child: Text('Add to group…')),
          const PopupMenuItem(value: 'details', child: Text('Details…')),
          const PopupMenuItem(value: 'block', child: Text('Block')),
          const PopupMenuItem(value: 'report', child: Text('Report…')),
        ],
      ),
      onTap: () {
        mesh.selectPeer(peer.id);
        widget.onOpenChat(peer.id);
      },
    );
  }

  Widget _buildGroups() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 0),
          child: Row(
            children: [
              Text(
                'Groups',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'New group',
                onPressed: _createGroupDialog,
                icon: const Icon(Icons.group_add),
              ),
            ],
          ),
        ),
        Expanded(
          child: mesh.groups.length == 0
              ? Center(
                  child: Text(
                    'No groups',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                )
              : ListView.separated(
                  itemCount: mesh.groups.all.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final g = mesh.groups.all[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        child: const Icon(Icons.groups),
                      ),
                      title: Text(g.name),
                      subtitle: Text('${g.memberCount} members'),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'chat') {
                            mesh.selectGroup(g.id);
                            widget.onOpenChat(null);
                          } else if (v == 'manage') {
                            _showGroupSheet(g);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                              value: 'chat', child: Text('Open chat')),
                          PopupMenuItem(
                            value: 'manage',
                            child: Text('Manage…'),
                          ),
                        ],
                      ),
                      onTap: () {
                        mesh.selectGroup(g.id);
                        widget.onOpenChat(null);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _showBlockedSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final entries = mesh.blockList.entries;
        return SafeArea(
          child: entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No blocked peers'),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(title: Text('Blocked'), dense: true),
                    for (final e in entries)
                      ListTile(
                        title: Text(
                          e.displayName?.isNotEmpty == true
                              ? e.displayName!
                              : e.subjectId,
                        ),
                        trailing: TextButton(
                          onPressed: () {
                            mesh.unblockPeer(e.subjectId);
                            Navigator.pop(context);
                            setState(() {});
                          },
                          child: const Text('Unblock'),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _onPeerAction(String action, Peer peer) async {
    switch (action) {
      case 'chat':
        mesh.selectPeer(peer.id);
        widget.onOpenChat(peer.id);
      case 'walkie':
        mesh.selectPeer(peer.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Walkie channel set')),
          );
        }
      case 'add_group':
        await _addPeerToGroup(peer);
      case 'details':
        await _showPeerSheet(peer);
      case 'block':
        await _blockPeerDialog(peer);
      case 'report':
        await _reportPeerDialog(peer);
    }
  }

  Future<void> _showPeerSheet(Peer peer) async {
    final title = peer.displayName.isNotEmpty ? peer.displayName : peer.id;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(title),
              subtitle: Text(peer.id),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Open chat'),
              onTap: () {
                Navigator.pop(context);
                mesh.selectPeer(peer.id);
                widget.onOpenChat(peer.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add_outlined),
              title: const Text('Add to group'),
              onTap: () {
                Navigator.pop(context);
                _addPeerToGroup(peer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('Block'),
              onTap: () {
                Navigator.pop(context);
                _blockPeerDialog(peer);
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Report'),
              onTap: () {
                Navigator.pop(context);
                _reportPeerDialog(peer);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showGroupSheet(MeshGroup g) async {
    final me = mesh.identity?.id;
    final isAdmin = me != null && g.isAdmin(me);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (context, scroll) {
            return ListView(
              controller: scroll,
              children: [
                ListTile(
                  title: Text(g.name),
                  subtitle: Text(
                    '${g.memberCount} members · ${g.description ?? g.id}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.chat),
                  title: const Text('Open group chat'),
                  onTap: () {
                    Navigator.pop(context);
                    mesh.selectGroup(g.id);
                    widget.onOpenChat(null);
                  },
                ),
                if (isAdmin)
                  ListTile(
                    leading: const Icon(Icons.person_add_alt),
                    title: const Text('Invite peer…'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _inviteToGroup(g);
                    },
                  ),
                if (isAdmin)
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Rename'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _renameGroup(g);
                    },
                  ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                for (final mid in g.memberIds)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      mid == g.ownerId
                          ? Icons.star
                          : g.isAdmin(mid)
                              ? Icons.shield
                              : Icons.person,
                    ),
                    title: Text(mesh.peers[mid]?.displayName.isNotEmpty == true
                        ? mesh.peers[mid]!.displayName
                        : mid),
                    subtitle: Text(
                      mid == g.ownerId
                          ? 'Owner · $mid'
                          : g.isAdmin(mid)
                              ? 'Admin · $mid'
                              : mid,
                    ),
                    trailing: isAdmin && mid != g.ownerId && mid != me
                        ? IconButton(
                            tooltip: 'Remove',
                            icon: const Icon(Icons.person_remove),
                            onPressed: () async {
                              await mesh.kickFromGroup(g.id, mid);
                              if (context.mounted) Navigator.pop(context);
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                const Divider(),
                ListTile(
                  leading: Icon(
                    Icons.logout,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    'Leave group',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await mesh.leaveGroup(g.id);
                    setState(() {});
                  },
                ),
                if (me != null && g.isOwner(me))
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Delete locally'),
                    onTap: () {
                      Navigator.pop(context);
                      mesh.deleteGroupLocally(g.id);
                      setState(() {});
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createGroupDialog() async {
    final nameCtrl = TextEditingController();
    final selected = <String>{};
    final peers = mesh.visiblePeers;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: const Text('New group'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Group name',
                        hintText: 'Field ops',
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Members',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: peers.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No peers nearby to invite yet'),
                            )
                          : ListView(
                              shrinkWrap: true,
                              children: [
                                for (final p in peers)
                                  CheckboxListTile(
                                    dense: true,
                                    value: selected.contains(p.id),
                                    title: Text(
                                      p.displayName.isEmpty
                                          ? p.id
                                          : p.displayName,
                                    ),
                                    onChanged: (v) {
                                      setLocal(() {
                                        if (v == true) {
                                          selected.add(p.id);
                                        } else {
                                          selected.remove(p.id);
                                        }
                                      });
                                    },
                                  ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      mesh.createGroup(name: nameCtrl.text, members: selected);
      setState(() => _tabs.index = 1);
      widget.onOpenChat(null);
    }
    nameCtrl.dispose();
  }

  Future<void> _addPeerToGroup(Peer peer) async {
    final mine = mesh.groups.all
        .where((g) => mesh.identity != null && g.isAdmin(mesh.identity!.id))
        .toList();
    if (mine.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Create a group first (you must be admin)'),
          ),
        );
      }
      return;
    }
    final chosen = await showDialog<MeshGroup>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(
          'Add ${peer.displayName.isEmpty ? peer.id : peer.displayName}',
        ),
        children: [
          for (final g in mine)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, g),
              child: Text(g.name),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await mesh.inviteToGroup(chosen.id, peer.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Invited to ${chosen.name}')),
        );
        setState(() {});
      }
    }
  }

  Future<void> _inviteToGroup(MeshGroup g) async {
    final peers = mesh.visiblePeers.where((p) => !g.isMember(p.id)).toList();
    if (peers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new peers to invite')),
        );
      }
      return;
    }
    final peer = await showDialog<Peer>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Invite to ${g.name}'),
        children: [
          for (final p in peers)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(
                p.displayName.isEmpty ? p.id : p.displayName,
              ),
            ),
        ],
      ),
    );
    if (peer != null) {
      await mesh.inviteToGroup(g.id, peer.id);
      setState(() {});
    }
  }

  Future<void> _renameGroup(MeshGroup g) async {
    final ctrl = TextEditingController(text: g.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true) {
      mesh.renameGroup(g.id, ctrl.text);
      setState(() {});
    }
    ctrl.dispose();
  }

  Future<void> _blockPeerDialog(Peer peer) async {
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Block ${peer.displayName.isEmpty ? peer.id : peer.displayName}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They will be hidden from peers and their messages, files, '
              'and walkie traffic will be ignored on this device.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok == true) {
      mesh.blockPeer(
        peer.id,
        displayName: peer.displayName,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      setState(() {});
    }
    reasonCtrl.dispose();
  }

  Future<void> _reportPeerDialog(Peer peer) async {
    var category = ReportCategory.spam;
    final detailsCtrl = TextEditingController();
    String? forwardTo;
    final moderators = mesh.visiblePeers.where((p) => p.id != peer.id).toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(
                'Report ${peer.displayName.isEmpty ? peer.id : peer.displayName}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Reports are stored on this device. Optionally forward '
                      'to a trusted peer (moderator).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final c in ReportCategory.values)
                          ChoiceChip(
                            label: Text(c.label),
                            selected: category == c,
                            onSelected: (_) => setLocal(() => category = c),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: detailsCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Details',
                        hintText: 'What happened?',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    if (moderators.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String?>(
                        initialValue: forwardTo,
                        decoration: const InputDecoration(
                          labelText: 'Forward to (optional)',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Local only'),
                          ),
                          for (final p in moderators)
                            DropdownMenuItem(
                              value: p.id,
                              child: Text(
                                p.displayName.isEmpty ? p.id : p.displayName,
                              ),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => forwardTo = v),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Submit report'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok == true) {
      await mesh.reportPeer(
        subjectId: peer.id,
        category: category,
        details: detailsCtrl.text,
        forwardToPeerId: forwardTo,
      );
      if (!mounted) return;
      final alsoBlock = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Also block?'),
          content: const Text(
            'Block this peer so you no longer see their traffic?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (alsoBlock == true) {
        mesh.blockPeer(
          peer.id,
          displayName: peer.displayName,
          reason: 'Reported: ${category.label}',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report saved')),
        );
        setState(() {});
      }
    }
    detailsCtrl.dispose();
  }
}

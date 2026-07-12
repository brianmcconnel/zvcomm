import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

import '../services/mesh_controller.dart';

/// Settings with primary toggles up front; plugins/safety/dev behind expanders.
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
    final family = mesh.familySafety;
    final pendingCount = family.pendingApprovals.length;
    final wardCount = family.wards.length;
    final groundedCount =
        family.wards.values.where((w) => w.grounded).length;
    final openNotes = family.openDiscussNotes.length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListenableBuilder(
          listenable: themeController,
          builder: (context, _) => ThemePicker(controller: themeController),
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            id?.displayName.isNotEmpty == true
                ? id!.displayName
                : 'This device',
          ),
          subtitle: Text(
            id?.id ?? '—',
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          trailing: Icon(
            mesh.running ? Icons.sensors : Icons.sensors_off,
            color: mesh.running ? scheme.primary : scheme.outline,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Discovery'),
          value: mesh.running,
          onChanged: (_) => mesh.toggleDiscovery(),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          initiallyExpanded: pendingCount > 0 ||
              family.isWard ||
              family.hasOpenDiscussNotes,
          title: Text(
            'Family safety'
            '${pendingCount > 0 ? ' · $pendingCount need OK' : ''}'
            '${openNotes > 0 ? ' · $openNotes discuss' : ''}'
            '${groundedCount > 0 ? ' · $groundedCount grounded' : ''}'
            '${pendingCount == 0 && openNotes == 0 && groundedCount == 0 && wardCount > 0 ? ' · $wardCount' : ''}',
          ),
          subtitle: const Text(
            'Mom & Dad same page · Teen notes · Kid · Ground',
          ),
          children: [
            // ── This device is supervised ──────────────────────────────
            if (family.myPolicy != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  family.myPolicy!.grounded
                      ? Icons.block
                      : family.myPolicy!.mode == SafetyMode.child
                          ? Icons.child_care
                          : Icons.visibility,
                  color: family.myPolicy!.grounded
                      ? scheme.error
                      : scheme.primary,
                ),
                title: Text(
                  family.myPolicy!.grounded
                      ? 'Grounded · ${family.myPolicy!.mode.shortLabel}'
                      : family.myPolicy!.mode.label,
                ),
                subtitle: Text(
                  family.myPolicy!.grounded
                      ? 'Messaging paused by family'
                      : 'Parents: ${family.myPolicy!.parentsLabel}'
                          '${family.myPolicy!.sharedWithIds.isEmpty ? '' : ' · ${family.myPolicy!.sharedWithIds.length} teacher(s)'}',
                ),
                trailing: TextButton(
                  onPressed: () => mesh.clearMySafetyPolicy(),
                  child: const Text('Clear'),
                ),
              ),
              const Divider(height: 8),
            ],

            // ── Pending approvals (parent) ─────────────────────────────
            if (family.pendingApprovals.isNotEmpty) ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Waiting for a parent OK',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('Either co-parent can approve — both stay synced'),
              ),
              for (final p in family.pendingApprovals)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p.fromName} → ${p.toLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('“${p.text}”'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => mesh.denyMediated(p.requestId),
                              child: const Text('No'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () =>
                                  mesh.approveMediated(p.requestId),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(height: 8),
            ],

            // ── Discuss-first notes (teen → parent) ────────────────────
            if (family.myPolicy?.mode == SafetyMode.teen &&
                !(family.myPolicy?.grounded ?? false)) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Discuss with parents first',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Send a private note before you send a real message',
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => _composeDiscussNote(context, mesh),
                  child: const Text('New note'),
                ),
              ),
              const Divider(height: 8),
            ],
            if (family.discussNotes.isNotEmpty) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Discuss notes'
                  '${family.openDiscussNotes.isEmpty ? '' : ' · ${family.openDiscussNotes.length} open'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Teens can talk things through with discretion settings',
                ),
              ),
              for (final n in family.discussNotes.take(12))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${n.fromName} · ${n.discretion.shortLabel} · ${n.status.label}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text('“${n.text}”'),
                        if (n.acknowledgedByName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${n.status == DiscussNoteStatus.closed ? 'Discussed' : 'Seen'} by ${n.acknowledgedByName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (family.isGuardian && n.isOpen) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => mesh.acknowledgeDiscussNote(
                                  n.id,
                                  status: DiscussNoteStatus.acknowledged,
                                ),
                                child: const Text('Got it'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => mesh.acknowledgeDiscussNote(
                                  n.id,
                                  status: DiscussNoteStatus.closed,
                                ),
                                child: const Text('Discussed'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              const Divider(height: 8),
            ],

            // ── Privilege board (shared Mom/Dad view) ──────────────────
            if (family.wards.isEmpty && family.myPolicy == null)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('No kids or teens set up yet'),
                subtitle: Text(
                  'Add a nearby device as Teen or Kid. Add a co-parent so Mom and Dad stay on the same privilege page.',
                ),
              )
            else if (family.wards.isNotEmpty) ...[
              const ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Family privilege status',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  'Same view for every co-parent — mode, grounded, who can approve',
                ),
              ),
              for (final w in family.wards.values)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: w.grounded
                      ? scheme.errorContainer.withValues(alpha: 0.45)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          w.grounded
                              ? Icons.block
                              : w.mode == SafetyMode.child
                                  ? Icons.child_care
                                  : Icons.visibility,
                          color: w.grounded ? scheme.error : scheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                w.displayName.isNotEmpty
                                    ? w.displayName
                                    : w.wardId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                w.privilegeLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: w.grounded
                                      ? scheme.error
                                      : scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Parents: ${w.parentsLabel(selfId: id?.id)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (w.sharedWithIds.isNotEmpty)
                                Text(
                                  'Shared: ${w.sharedWithIds.length} teacher(s)/leader(s)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              if (w.statusByName != null &&
                                  w.statusByName!.isNotEmpty)
                                Text(
                                  'Last change: ${w.statusByName}'
                                  '${w.statusById == id?.id ? ' (you)' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            switch (v) {
                              case 'teen':
                                await mesh.updateWardMode(
                                  w.wardId,
                                  SafetyMode.teen,
                                );
                              case 'kid':
                                await mesh.updateWardMode(
                                  w.wardId,
                                  SafetyMode.child,
                                );
                              case 'ground':
                                await mesh.setWardGrounded(w.wardId, true);
                              case 'unground':
                                await mesh.setWardGrounded(w.wardId, false);
                              case 'coparent':
                                if (context.mounted) {
                                  await _pickCoParent(context, mesh, w);
                                }
                              case 'share':
                                if (context.mounted) {
                                  await _pickShared(context, mesh, w);
                                }
                              case 'remove':
                                await mesh.removeWard(w.wardId);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'teen',
                              child: Text('Mode: Teen (see chats)'),
                            ),
                            const PopupMenuItem(
                              value: 'kid',
                              child: Text('Mode: Kid (approve first)'),
                            ),
                            if (w.grounded)
                              const PopupMenuItem(
                                value: 'unground',
                                child: Text('Unground (restore messaging)'),
                              )
                            else
                              const PopupMenuItem(
                                value: 'ground',
                                child: Text('Ground (pause messaging)'),
                              ),
                            const PopupMenuItem(
                              value: 'coparent',
                              child: Text('Add co-parent (Mom/Dad)…'),
                            ),
                            const PopupMenuItem(
                              value: 'share',
                              child: Text('Share with teachers…'),
                            ),
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Stop supervising'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],

            // ── Recent activity (copies) ───────────────────────────────
            if (family.activityFeed.isNotEmpty) ...[
              const Divider(height: 8),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Recent messages',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final c in family.activityFeed.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${c.fromName} → ${c.toLabel}'),
                  subtitle: Text(
                    c.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],

            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: FilledButton.tonalIcon(
                  onPressed: mesh.visiblePeers.isEmpty
                      ? null
                      : () => _setupWard(context, mesh),
                  icon: const Icon(Icons.family_restroom),
                  label: const Text('Add kid or teen'),
                ),
              ),
            ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Transports'),
          children: [
            for (final p in plugins)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: Icon(TransportLinkIcons.iconFor(p.kind)),
                title: Text(p.name),
                value: mesh.pluginEnabled[p.id] ?? p.enabledByDefault,
                onChanged: (v) => mesh.setPluginEnabled(p.id, v),
              ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Power · ${mesh.powerMode.name}'),
          children: [
            for (final mode in TransportPowerMode.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(mode.name),
                leading: Icon(
                  mesh.powerMode == mode
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                ),
                onTap: () => mesh.setPowerMode(mode),
              ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(
            'Safety'
            '${mesh.blockList.length + mesh.reports.all.length == 0 ? '' : ' (${mesh.blockList.length} blocked · ${mesh.reports.all.length} reports)'}',
          ),
          children: [
            if (mesh.blockList.entries.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('No blocked peers'),
              )
            else
              for (final e in mesh.blockList.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    e.displayName?.isNotEmpty == true
                        ? e.displayName!
                        : e.subjectId,
                  ),
                  trailing: TextButton(
                    onPressed: () => mesh.unblockPeer(e.subjectId),
                    child: const Text('Unblock'),
                  ),
                ),
            if (mesh.reports.all.isNotEmpty) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('Reports (${mesh.reports.all.length})'),
                trailing: TextButton(
                  onPressed: () => mesh.clearReports(),
                  child: const Text('Clear'),
                ),
              ),
              for (final r in mesh.reports.all.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(r.category.label),
                  subtitle: Text(
                    r.subjectDisplayName?.isNotEmpty == true
                        ? r.subjectDisplayName!
                        : r.subjectId,
                  ),
                ),
            ],
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Developer'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mock demo peer'),
              value: mesh.useMockDemo,
              onChanged: (v) => mesh.setUseMockDemo(v),
            ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('About'),
          children: [
            const ListTile(
              contentPadding: EdgeInsets.zero,
              title: ZvcommTitle(
                'ZVComm',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text('Short-range mesh · © Brian McConnel 2026'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Active transports'),
              subtitle: Text(
                mesh.transportManager?.transports
                        .map((t) => t.name)
                        .join(', ') ??
                    '—',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _composeDiscussNote(
  BuildContext context,
  MeshController mesh,
) async {
  final textCtrl = TextEditingController();
  var discretion = NoteDiscretion.parents;

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Discuss with parents first'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Write what you want to talk about before you send a real message. '
                    'Teachers never see these notes.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      border: OutlineInputBorder(),
                      hintText: 'I want to check with you before I…',
                    ),
                    minLines: 3,
                    maxLines: 6,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Discretion',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final d in NoteDiscretion.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        discretion == d
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(d.shortLabel),
                      subtitle: Text(d.blurb),
                      onTap: () => setLocal(() => discretion = d),
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
                child: const Text('Send to parents'),
              ),
            ],
          );
        },
      );
    },
  );

  if (ok != true) {
    textCtrl.dispose();
    return;
  }
  try {
    await mesh.sendDiscussNote(
      text: textCtrl.text,
      discretion: discretion,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Discuss note sent (${discretion.shortLabel})'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send note: $e')),
      );
    }
  } finally {
    textCtrl.dispose();
  }
}

Future<void> _setupWard(BuildContext context, MeshController mesh) async {
  // Family safety only for QR/NFC-trusted contacts — never radio-only peers.
  final peers = mesh.trustedVisiblePeers
      .where((p) => !mesh.familySafety.wards.containsKey(p.id))
      .toList();
  if (peers.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No QR/NFC-trusted peers. Open Credentials and exchange public keys first.',
          ),
        ),
      );
    }
    return;
  }

  Peer? selected;
  var mode = SafetyMode.teen;
  final shared = <String>{};
  final coParents = <String>{};

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Add kid or teen'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Only people you already trusted via QR or NFC appear here. '
                    'Radio proximity alone is never enough.',
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selected?.id,
                    decoration: const InputDecoration(
                      labelText: 'Trusted person',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in peers)
                        DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.displayName.isNotEmpty ? p.displayName : p.id,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setLocal(() {
                        Peer? match;
                        for (final p in peers) {
                          if (p.id == v) {
                            match = p;
                            break;
                          }
                        }
                        selected = match;
                        if (match != null) {
                          shared.remove(match.id);
                          coParents.remove(match.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  for (final m in SafetyMode.values)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(
                        mode == m
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      title: Text(m.shortLabel),
                      subtitle: Text(m.blurb),
                      onTap: () => setLocal(() => mode = m),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Co-parent (Mom / Dad) — must be QR/NFC trusted',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  for (final p in mesh.trustedVisiblePeers)
                    if (p.id != selected?.id)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: coParents.contains(p.id),
                        title: Text(
                          p.displayName.isNotEmpty ? p.displayName : p.id,
                        ),
                        subtitle: const Text('Can approve & change privileges'),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              coParents.add(p.id);
                              shared.remove(p.id);
                            } else {
                              coParents.remove(p.id);
                            }
                          });
                        },
                      ),
                  const SizedBox(height: 8),
                  const Text(
                    'Also share with teachers / leaders (QR/NFC trusted)',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  for (final p in mesh.trustedVisiblePeers)
                    if (p.id != selected?.id && !coParents.contains(p.id))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: shared.contains(p.id),
                        title: Text(
                          p.displayName.isNotEmpty ? p.displayName : p.id,
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          setLocal(() {
                            if (v == true) {
                              shared.add(p.id);
                            } else {
                              shared.remove(p.id);
                            }
                          });
                        },
                      ),
                  if (mesh.trustedVisiblePeers
                      .where((p) => p.id != selected?.id)
                      .isEmpty)
                    const Text(
                      'No other trusted peers for co-parent or share.',
                      style: TextStyle(fontSize: 12),
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
                onPressed: selected == null
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Set up'),
              ),
            ],
          );
        },
      );
    },
  );

  if (ok != true || selected == null) return;
  try {
    await mesh.setupWard(
      wardId: selected!.id,
      mode: mode,
      displayName: selected!.displayName,
      sharedWithIds: shared.toList(),
      coParentIds: coParents.toList(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${mode.shortLabel} set for '
            '${selected!.displayName.isNotEmpty ? selected!.displayName : selected!.id}',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not set up: $e')),
      );
    }
  }
}

Future<void> _pickCoParent(
  BuildContext context,
  MeshController mesh,
  WardProfile ward,
) async {
  final candidates = mesh.trustedVisiblePeers
      .where(
        (p) =>
            p.id != ward.wardId &&
            !ward.parentIds.contains(p.id) &&
            p.id != mesh.identity?.id,
      )
      .toList();
  if (candidates.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No QR/NFC-trusted peers for co-parent. Exchange keys in Credentials first.',
          ),
        ),
      );
    }
    return;
  }

  final picked = await showDialog<Peer>(
    context: context,
    builder: (context) {
      return SimpleDialog(
        title: Text('Add co-parent for ${ward.displayName}'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'They get the same privilege status (Teen/Kid/Grounded) '
              'and can approve kid messages. Mom and Dad stay on the same page.',
            ),
          ),
          for (final p in candidates)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, p),
              child: Text(
                p.displayName.isNotEmpty ? p.displayName : p.id,
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
  if (picked == null) return;
  try {
    await mesh.addCoParent(
      wardId: ward.wardId,
      parentId: picked.id,
      parentName: picked.displayName,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Co-parent ${picked.displayName.isNotEmpty ? picked.displayName : picked.id} '
            'added — privilege status synced',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add co-parent: $e')),
      );
    }
  }
}

Future<void> _pickShared(
  BuildContext context,
  MeshController mesh,
  WardProfile ward,
) async {
  final selected = {...ward.sharedWithIds};
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text('Share ${ward.displayName}'),
            content: SizedBox(
              width: 360,
              child: mesh.trustedVisiblePeers.isEmpty
                  ? const Text(
                      'No QR/NFC-trusted peers. Exchange keys in Credentials first.',
                    )
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Teachers and leaders can see messages. '
                            'Only you approve Kid messages.',
                          ),
                          const SizedBox(height: 8),
                          for (final p in mesh.trustedVisiblePeers)
                            if (p.id != ward.wardId)
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                value: selected.contains(p.id),
                                title: Text(
                                  p.displayName.isNotEmpty
                                      ? p.displayName
                                      : p.id,
                                ),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
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
            ),
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
          );
        },
      );
    },
  );
  if (ok == true) {
    await mesh.updateWardShared(ward.wardId, selected.toList());
  }
}

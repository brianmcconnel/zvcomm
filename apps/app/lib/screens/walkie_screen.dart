import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mesh_controller.dart';
import '../services/voice_audio.dart';

/// Minimal push-to-talk walkie — channel + PTT; details in menus.
class WalkieScreen extends StatefulWidget {
  final MeshController mesh;

  const WalkieScreen({super.key, required this.mesh});

  @override
  State<WalkieScreen> createState() => _WalkieScreenState();
}

class _WalkieScreenState extends State<WalkieScreen> {
  final VoiceAudio _audio = VoiceAudio();
  bool _pttHeld = false;
  bool _busy = false;
  bool _autoPlay = true;
  String? _status;
  int _seenInbox = 0;

  MeshController get mesh => widget.mesh;

  @override
  void initState() {
    super.initState();
    _seenInbox = mesh.walkieInbox.length;
    mesh.addListener(_onMesh);
  }

  void _onMesh() {
    if (!mounted) return;
    if (_autoPlay &&
        mesh.walkieInbox.length > _seenInbox &&
        !mesh.walkieTransmitting &&
        !_pttHeld) {
      final clip = mesh.walkieInbox.first;
      _seenInbox = mesh.walkieInbox.length;
      unawaited(_playClip(clip));
    } else {
      _seenInbox = mesh.walkieInbox.length;
    }
    setState(() {});
  }

  @override
  void dispose() {
    mesh.removeListener(_onMesh);
    _audio.dispose();
    super.dispose();
  }

  Future<void> _onPttDown() async {
    if (_pttHeld || _busy) return;
    if (mesh.familySafety.iAmGrounded) {
      setState(() => _status = 'Grounded — walkie paused');
      return;
    }
    if (mesh.voice?.channelBusy == true && !mesh.walkieTransmitting) {
      setState(() => _status = 'Channel busy');
      return;
    }
    setState(() {
      _pttHeld = true;
      _busy = true;
      _status = null;
    });
    try {
      await _audio.startCapture();
      if (mounted) setState(() => _status = 'Recording…');
    } catch (e) {
      if (mounted) {
        setState(() {
          _pttHeld = false;
          _status = 'Mic error';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPttUp() async {
    if (!_pttHeld) return;
    setState(() {
      _pttHeld = false;
      _busy = true;
    });
    try {
      final pcm = await _audio.stopCapture();
      if (pcm.isEmpty) {
        setState(() => _status = null);
        return;
      }
      setState(() => _status = 'Sending…');
      await mesh.walkieSendBurst(pcm);
      if (mounted) setState(() => _status = 'Sent');
    } catch (e) {
      if (mounted) setState(() => _status = 'Send failed');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _playClip(WalkieClip clip) async {
    try {
      await _audio.playPcm(
        clip.pcm,
        sampleRate: clip.transmission.sampleRate,
        channels: clip.transmission.channels,
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'Play failed');
    }
  }

  String get _channelLabel {
    final gId = mesh.selectedGroupId;
    if (gId != null) {
      return mesh.groups[gId]?.name ?? 'Group';
    }
    final p = mesh.selectedPeerId;
    if (p == null) return 'Everyone';
    final peer = mesh.peers[p];
    if (peer?.displayName.isNotEmpty == true) return peer!.displayName;
    return p.length > 8 ? '${p.substring(0, 8)}…' : p;
  }

  IconData get _channelIcon {
    if (mesh.selectedGroupId != null) return Icons.groups;
    if (mesh.selectedPeerId == null) return Icons.campaign;
    return Icons.person;
  }

  Future<void> _pickChannel() async {
    if (_pttHeld || mesh.walkieTransmitting) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text('Channel'),
                dense: true,
              ),
              ListTile(
                leading: const Icon(Icons.campaign),
                title: const Text('Everyone'),
                selected:
                    mesh.selectedPeerId == null && mesh.selectedGroupId == null,
                onTap: () {
                  mesh.selectPeer(null);
                  Navigator.pop(context);
                },
              ),
              if (mesh.groups.all.isNotEmpty) ...[
                const Divider(height: 1),
                const ListTile(
                  title: Text('Groups'),
                  dense: true,
                ),
                for (final g in mesh.groups.all)
                  ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(g.name),
                    subtitle: Text('${g.memberCount} members'),
                    selected: mesh.selectedGroupId == g.id,
                    onTap: () {
                      mesh.selectGroup(g.id);
                      Navigator.pop(context);
                    },
                  ),
              ],
              if (mesh.visiblePeers.isNotEmpty) ...[
                const Divider(height: 1),
                const ListTile(
                  title: Text('Peers'),
                  dense: true,
                ),
                for (final p in mesh.visiblePeers)
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(
                      p.displayName.isEmpty ? p.id : p.displayName,
                    ),
                    selected: mesh.selectedPeerId == p.id,
                    onTap: () {
                      mesh.selectPeer(p.id);
                      Navigator.pop(context);
                    },
                  ),
              ],
            ],
          ),
        );
      },
    );
    if (mounted) setState(() {});
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final inbox = mesh.walkieInbox;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.45,
          maxChildSize: 0.85,
          builder: (context, scroll) {
            if (inbox.isEmpty) {
              return const Center(child: Text('No received clips yet'));
            }
            return ListView.builder(
              controller: scroll,
              itemCount: inbox.length,
              itemBuilder: (context, i) {
                final c = inbox[i];
                final from = c.transmission.sourceId;
                final name = from == null
                    ? '?'
                    : (mesh.peers[from]?.displayName.isNotEmpty == true
                        ? mesh.peers[from]!.displayName
                        : from.substring(0, from.length.clamp(0, 8)));
                final gName = c.transmission.groupId != null
                    ? mesh.groups[c.transmission.groupId!]?.name
                    : null;
                return ListTile(
                  leading: Icon(
                    gName != null ? Icons.groups : Icons.record_voice_over,
                  ),
                  title: Text(gName != null ? '$name · $gName' : name),
                  subtitle: Text(
                    c.receivedAt.toLocal().toIso8601String().substring(11, 19),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      Navigator.pop(context);
                      unawaited(_playClip(c));
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final grounded = mesh.familySafety.iAmGrounded;
    final transmitting = _pttHeld || mesh.walkieTransmitting;
    final receiving = mesh.walkieReceiving;
    final statusText = grounded
        ? 'Grounded — walkie paused by parent'
        : transmitting
            ? (_status ?? mesh.walkieStatus ?? 'Transmitting')
            : receiving
                ? (mesh.walkieStatus ?? 'Receiving')
                : _status;

    return Column(
      children: [
        // Compact channel bar — one row, actions in menu.
        Material(
          color: grounded
              ? scheme.errorContainer
              : scheme.surfaceContainerHighest,
          child: ListTile(
            leading: Icon(
              grounded ? Icons.block : _channelIcon,
              color: grounded
                  ? scheme.onErrorContainer
                  : transmitting
                      ? scheme.error
                      : receiving
                          ? scheme.primary
                          : null,
            ),
            title: Text(_channelLabel),
            subtitle: statusText != null ? Text(statusText) : null,
            onTap: transmitting ? null : _pickChannel,
            trailing: PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) {
                switch (v) {
                  case 'channel':
                    unawaited(_pickChannel());
                  case 'history':
                    unawaited(_showHistory());
                  case 'autoplay':
                    setState(() => _autoPlay = !_autoPlay);
                  case 'play':
                    if (mesh.walkieInbox.isNotEmpty) {
                      unawaited(_playClip(mesh.walkieInbox.first));
                    }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'channel',
                  child: Text('Change channel…'),
                ),
                PopupMenuItem(
                  value: 'history',
                  child: Text(
                    'History${mesh.walkieInbox.isEmpty ? '' : ' (${mesh.walkieInbox.length})'}',
                  ),
                ),
                if (mesh.walkieInbox.isNotEmpty)
                  const PopupMenuItem(
                    value: 'play',
                    child: Text('Play latest'),
                  ),
                CheckedPopupMenuItem(
                  value: 'autoplay',
                  checked: _autoPlay,
                  child: const Text('Auto-play'),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Listener(
                  onPointerDown: (_) => _onPttDown(),
                  onPointerUp: (_) => _onPttUp(),
                  onPointerCancel: (_) => _onPttUp(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: transmitting ? 160 : 144,
                    height: transmitting ? 160 : 144,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: transmitting
                          ? scheme.error
                          : receiving
                              ? scheme.primaryContainer
                              : scheme.primary,
                      boxShadow: [
                        BoxShadow(
                          color: (transmitting ? scheme.error : scheme.primary)
                              .withValues(alpha: 0.4),
                          blurRadius: transmitting ? 24 : 12,
                        ),
                      ],
                    ),
                    child: Icon(
                      transmitting ? Icons.mic : Icons.mic_none,
                      size: 56,
                      color: transmitting
                          ? scheme.onError
                          : receiving
                              ? scheme.onPrimaryContainer
                              : scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  transmitting
                      ? 'Release to send'
                      : receiving
                          ? 'Incoming…'
                          : 'Hold to talk',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ble/ble.dart';
import 'package:core/core.dart';
import 'package:nfc/nfc.dart';
import 'package:pki/pki.dart';
import 'package:wifi/wifi.dart';

/// How a public key entered the local trust store.
///
/// **Policy:** trust is only granted via [qr] or [nfc] exchange of public keys.
/// Radio proximity / mesh advertisements never establish trust.
enum TrustChannel {
  qr,
  nfc,
}

/// App-wide mesh lifecycle, chat log, transfers, plugins, and battery policy.
final class MeshController extends ChangeNotifier with WidgetsBindingObserver {
  DeviceIdentity? identity;
  MeshNode? node;
  FileTransferService? transfers;
  VoiceChannelService? voice;
  final ChatLog chat = ChatLog();
  final TransportRegistry registry = TransportRegistry.instance;

  late final MockMedium medium;
  MockTransport? mockTransport;
  MockTransport? demoPeer;
  TransportManager? transportManager;

  final Map<String, Peer> peers = {};
  final Map<TransportKind, bool> available = {};
  final List<FileTransferProgress> transferHistory = [];
  final List<PresenceInfo> livePresence = [];

  /// Plugin id → enabled for the next stack rebuild / current session.
  final Map<String, bool> pluginEnabled = {};

  /// Live transports created from plugins (for hot enable/disable).
  final Map<String, Transport> pluginTransports = {};

  /// Credentials imported via QR / short code / mesh offer.
  final Map<String, PublicCredential> trustedCredentials = {};

  /// Local chat groups (create / invite / membership).
  final GroupStore groups = GroupStore();

  /// Remote "is typing" state per conversation.
  final TypingPresence typing = TypingPresence();

  /// Local block list (hides peers and drops their messages).
  final BlockList blockList = BlockList();

  /// Local user-report log (+ optional mesh forward).
  final ReportStore reports = ReportStore();

  /// Family safety: teen transparency, kid mediation, shared with teachers.
  final FamilySafetyStore familySafety = FamilySafetyStore();

  /// Multi-scope calendars: personal, family, group, organization.
  final CalendarStore calendars = CalendarStore();

  /// Personal 24-hour time recording (prompt to log each hour).
  final TimeLogStore timeLog = TimeLogStore();

  /// Kid-mode outbound photos waiting for parent OK (local device only).
  final Map<String, ({Uint8List bytes, String mime, String name, String? caption})>
      _pendingOutboundImages = {};

  /// Organization roots + org-issued external certificates.
  final TrustStore trustStore = TrustStore();

  /// Local CAs that can issue for an org. Keyed by **org root** id.
  ///
  /// Root-hosted: CA root id == org id.
  /// Delegated issuer: CA root is this device; authority lives in
  /// [issuerAuthorities].
  final Map<String, LocalCa> hostedOrgCas = {};

  /// Our delegated-issuer grants (org root id → authority cert). Empty when we
  /// host the root CA for that org.
  final Map<String, MeshCertificate> issuerAuthorities = {};

  /// Transient peer credential offers keyed by short code.
  final CredentialOfferCache offerCache = CredentialOfferCache();

  /// Transient organization offers keyed by short code.
  final OrganizationOfferCache orgOfferCache = OrganizationOfferCache();

  /// Cached local share payload (QR + short code).
  PublicCredential? localCredential;

  /// Organization currently selected for share (QR / NFC / short code).
  Organization? sharingOrganization;

  StreamSubscription<Peer>? _peerSub;
  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<PresenceInfo>? _presenceSub;
  StreamSubscription<FileTransferProgress>? _xferSub;
  StreamSubscription<({FileTransferInfo info, Uint8List bytes})>? _xferDoneSub;
  StreamSubscription<PublicCredential>? _nfcCredSub;
  StreamSubscription<String>? _nfcUriSub;
  StreamSubscription<VoiceEvent>? _voiceSub;
  Timer? _typingPurgeTimer;
  Timer? _statsSampleTimer;
  Timer? _localTypingIdleTimer;
  bool _localTypingActive = false;
  DateTime? _lastTypingSentAt;

  /// Rolling mesh performance samples for the Status dashboard.
  final StatsHistory statsHistory = StatsHistory(capacity: 180);

  /// When this mesh session became ready (for uptime display).
  DateTime? sessionStartedAt;

  bool ready = false;
  bool running = false;

  /// In-process mock radio + demo peer. Off by default; enable in Settings → Developer.
  bool useMockDemo = false;
  TransportPowerMode powerMode = TransportPowerMode.balanced;
  String? status;
  String? selectedPeerId;

  /// Active group chat target (mutually exclusive with [selectedPeerId]).
  String? selectedGroupId;
  String displayName = 'This device';

  /// True while an NFC credential share/receive session is armed.
  bool nfcCredentialArmed = false;

  /// Walkie-talkie / PTT state for UI.
  bool walkieTransmitting = false;
  bool walkieReceiving = false;
  String? walkieRemotePeerId;
  String? walkieStatus;
  int walkieBytes = 0;

  /// Recent received clips (newest first), for replay.
  final List<WalkieClip> walkieInbox = [];

  Future<void> bootstrap() async {
    _registerPlugins();
    medium = MockMedium();

    final id = await DeviceIdentity.generate(displayName: displayName);
    identity = id;

    mockTransport = MockTransport(
      medium: medium,
      localId: id.id,
      displayName: id.displayName,
      position: const SimPoint(0, 0),
    );
    demoPeer = MockTransport(
      medium: medium,
      localId: 'demo-peer-01',
      displayName: 'Demo Peer',
      position: const SimPoint(8, 0),
    );

    final ctx = TransportPluginContext(
      localId: id.id,
      displayName: id.displayName,
    );

    final stack = <Transport>[];
    pluginTransports.clear();
    for (final plugin in registry.plugins) {
      final on = pluginEnabled[plugin.id] ?? plugin.enabledByDefault;
      pluginEnabled[plugin.id] = on;
      if (!on) continue;
      if (plugin.id == BuiltinCorePlugins.mockId ||
          plugin.id == BuiltinCorePlugins.hardwareAdapterId) {
        continue;
      }
      try {
        final t = plugin.create(ctx);
        stack.add(t);
        pluginTransports[plugin.id] = t;
      } catch (e) {
        chat.addSystem('Plugin ${plugin.id} failed: $e');
      }
    }
    // Always include local mock radio for demo/LAN-less UX when enabled.
    if (useMockDemo) {
      stack.add(mockTransport!);
    }

    transportManager = TransportManager(stack);
    node = MeshNode(
      localId: id.id,
      displayName: id.displayName,
      transports: transportManager!,
    );
    transfers = FileTransferService(node: node!)..start();
    voice = VoiceChannelService(node: node!)..start();
    voice!.acceptIncoming = _acceptWalkieIncoming;
    _voiceSub = voice!.events.listen(_onVoiceEvent);

    _peerSub = node!.peerUpdates.listen((p) {
      if (blockList.isBlocked(p.id)) return;
      peers[p.id] = p;
      notifyListeners();
    });
    _msgSub = node!.messages.listen((m) {
      if (m.sourceId != null && blockList.isBlocked(m.sourceId!)) {
        return; // Drop traffic from blocked peers.
      }
      if (m.kind == MessageKind.chat) {
        _onChatMessage(m);
      } else if (m.kind == MessageKind.control) {
        unawaited(_onControlMessage(m));
      }
    });

    // Pre-build shareable credential for QR / short code / NFC.
    localCredential = await PublicCredential.fromIdentity(id);
    _listenNfcCredentials();
    _listenNfcUris();

    _presenceSub = node!.presenceUpdates.listen((p) {
      livePresence.removeWhere((e) => e.peerId == p.peerId);
      livePresence.add(p);
      notifyListeners();
    });
    _xferSub = transfers!.progress.listen((p) {
      final i = transferHistory.indexWhere(
        (e) => e.info.transferId == p.info.transferId,
      );
      if (i >= 0) {
        transferHistory[i] = p;
      } else {
        transferHistory.insert(0, p);
      }
      if (transferHistory.length > 20) {
        transferHistory.removeRange(20, transferHistory.length);
      }
      notifyListeners();
    });
    _xferDoneSub = transfers!.completed.listen((event) {
      // Image files land in chat as photos when mime looks like an image.
      final mime = event.info.mimeType ?? '';
      final name = event.info.fileName;
      final isImage = ChatImageWire.looksLikeImageMime(mime) ||
          RegExp(r'\.(jpe?g|png|gif|webp|bmp|heic)$', caseSensitive: false)
              .hasMatch(name);
      if (isImage &&
          event.bytes.isNotEmpty &&
          event.bytes.length <= ChatImageWire.maxBytes) {
        final from = event.info.sourceId;
        final me = identity?.id;
        final isLocal = from != null && me != null && from == me;
        if (!isLocal) {
          chat.add(
            ChatLine(
              id: 'img-${event.info.transferId}',
              peerId: from,
              text: '📷 $name',
              timestamp: DateTime.now().toUtc(),
              isLocal: false,
              isBroadcast: event.info.destinationId == null,
              senderName: from != null ? _peerLabel(from) : null,
              imageBytes: event.bytes,
              imageMime: mime.isEmpty ? 'image/jpeg' : mime,
              imageName: name,
            ),
          );
        }
      }
      chat.addSystem(
        'Received file ${event.info.fileName} (${event.bytes.length} B)'
        '${event.info.sourceId != null ? " from ${event.info.sourceId}" : ""}',
      );
      notifyListeners();
    });

    WidgetsBinding.instance.addObserver(this);
    sessionStartedAt = DateTime.now().toUtc();
    // Expire remote typing indicators periodically.
    _typingPurgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Trigger UI refresh so TTL expiry is visible without new events.
      if (typing.statusText(_currentChatThreadKey()) != null ||
          _localTypingActive) {
        notifyListeners();
      }
    });
    // Task Manager–style 1 Hz stats sampling for charts.
    _statsSampleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _sampleStats();
    });
    _sampleStats();
    ready = true;
    await probeAvailability();
    await startDiscovery();
    notifyListeners();
  }

  void _sampleStats() {
    final s = node?.stats ?? MeshStats();
    statsHistory.record(
      stats: s,
      peerCount: peers.length,
      presenceCount: livePresence.length,
    );
    notifyListeners();
  }

  /// Wall-clock session uptime.
  Duration get sessionUptime {
    final start = sessionStartedAt;
    if (start == null) return Duration.zero;
    return DateTime.now().toUtc().difference(start);
  }

  /// Thread key for the currently selected chat (DM / group / broadcast).
  String _currentChatThreadKey() => TypingPresence.threadKey(
        peerId: selectedPeerId,
        groupId: selectedGroupId,
      );

  /// Label for the typing bar in the current conversation, or null.
  String? typingStatusForCurrentChat() =>
      typing.statusText(_currentChatThreadKey());

  /// Called from the composer while the user types (debounced on the mesh).
  Future<void> setLocalTyping(bool isTyping) async {
    final id = identity;
    if (id == null) return;

    if (!isTyping) {
      _localTypingIdleTimer?.cancel();
      _localTypingIdleTimer = null;
      if (_localTypingActive) {
        _localTypingActive = false;
        await _broadcastTyping(false);
      }
      return;
    }

    // Refresh idle timer — stop advertising after quiet period.
    _localTypingIdleTimer?.cancel();
    _localTypingIdleTimer = Timer(const Duration(seconds: 3), () {
      unawaited(setLocalTyping(false));
    });

    final now = DateTime.now();
    final shouldSend = !_localTypingActive ||
        _lastTypingSentAt == null ||
        now.difference(_lastTypingSentAt!) > const Duration(seconds: 2);
    _localTypingActive = true;
    if (shouldSend) {
      _lastTypingSentAt = now;
      await _broadcastTyping(true);
    }
  }

  Future<void> _broadcastTyping(bool typingOn) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;

    final gid = selectedGroupId;
    final peer = selectedPeerId;
    final payload = ChatTypingWire.encode(
      peerId: id.id,
      typing: typingOn,
      groupId: gid,
      threadPeerId: gid == null ? peer : null,
      displayName: id.displayName,
    );

    Future<void> sendTo(String? dest) async {
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: dest,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }

    if (gid != null) {
      final group = groups[gid];
      if (group == null) return;
      for (final mid in group.memberIds) {
        if (mid == id.id || blockList.isBlocked(mid)) continue;
        await sendTo(mid);
      }
      return;
    }

    if (peer != null) {
      if (!blockList.isBlocked(peer)) await sendTo(peer);
      return;
    }

    // Broadcast channel.
    await sendTo(null);
  }

  void _registerPlugins() {
    // Idempotent re-register of known plugins.
    BuiltinCorePlugins.registerAll(registry);
    registerBlePlugin(registry);
    registerNfcPlugin(registry);
    registerWifiPlugin(registry);
  }

  List<TransportPlugin> get plugins => registry.plugins;

  Future<void> setPluginEnabled(String pluginId, bool enabled) async {
    pluginEnabled[pluginId] = enabled;
    final mgr = transportManager;
    final id = identity;
    if (mgr == null || id == null) {
      notifyListeners();
      return;
    }

    final plugin = registry[pluginId];
    if (plugin == null) {
      notifyListeners();
      return;
    }

    // Options-only plugins are configured programmatically, not toggled here.
    if (pluginId == BuiltinCorePlugins.mockId ||
        pluginId == BuiltinCorePlugins.hardwareAdapterId) {
      notifyListeners();
      return;
    }

    final existing = pluginTransports[pluginId];

    if (enabled) {
      if (existing != null) {
        notifyListeners();
        return;
      }
      try {
        final t = plugin.create(
          TransportPluginContext(
            localId: id.id,
            displayName: id.displayName,
          ),
        );
        await mgr.register(t);
        pluginTransports[pluginId] = t;
        chat.addSystem('Enabled transport plugin ${plugin.name}');
        if (pluginId == nfcPluginId) {
          _listenNfcCredentials();
          _listenNfcUris();
        }
      } catch (e) {
        chat.addSystem('Failed to enable ${plugin.name}: $e');
      }
    } else if (existing != null) {
      await mgr.unregister(existing);
      pluginTransports.remove(pluginId);
      if (pluginId == nfcPluginId) {
        unawaited(_nfcCredSub?.cancel());
        unawaited(_nfcUriSub?.cancel());
        _nfcCredSub = null;
        _nfcUriSub = null;
        nfcCredentialArmed = false;
      }
      chat.addSystem('Disabled transport plugin ${plugin.name}');
    }

    await probeAvailability();
    notifyListeners();
  }

  Future<void> probeAvailability() async {
    Future<bool> safe(Future<bool> Function() check) async {
      try {
        return await check().timeout(const Duration(milliseconds: 800));
      } catch (_) {
        return false;
      }
    }

    available.clear();
    final mgr = transportManager;
    if (mgr != null) {
      for (final t in mgr.transports) {
        available[t.kind] = await safe(t.isAvailable);
      }
    }
    available[TransportKind.mock] = useMockDemo;
    notifyListeners();
  }

  Future<void> startDiscovery() async {
    final n = node;
    if (n == null) return;
    status = 'Starting discovery…';
    notifyListeners();
    try {
      if (useMockDemo) {
        await demoPeer?.startAdvertising(
          localId: 'demo-peer-01',
          displayName: 'Demo Peer',
          metadata: {'demo': 'true'},
        );
      }
      await n.transports.setPowerMode(powerMode);
      await n.start().timeout(const Duration(seconds: 5));
      running = true;
      final active = available.entries
          .where((e) => e.value)
          .map((e) => e.key.name.toUpperCase())
          .join(', ');
      status =
          'Scanning: ${active.isEmpty ? "none" : active}${useMockDemo ? " + mock" : ""}';
      chat.addSystem(
          'Mesh started (${transportManager?.transports.length ?? 0} transports)');
    } catch (e) {
      running = true;
      status = 'Mesh started (some transports unavailable)';
      chat.addSystem('Mesh start partial: $e');
    }
    notifyListeners();
  }

  Future<void> stopDiscovery() async {
    await node?.stop();
    await demoPeer?.stopAdvertising();
    running = false;
    status = 'Stopped';
    chat.addSystem('Mesh stopped');
    notifyListeners();
  }

  Future<void> toggleDiscovery() async {
    if (running) {
      await stopDiscovery();
    } else {
      await startDiscovery();
    }
  }

  Future<void> setPowerMode(TransportPowerMode mode) async {
    powerMode = mode;
    await node?.transports.setPowerMode(mode);
    status = 'Power mode → ${mode.name}';
    notifyListeners();
  }

  Future<void> cyclePowerMode() async {
    const modes = TransportPowerMode.values;
    final next = modes[(powerMode.index + 1) % modes.length];
    await setPowerMode(next);
  }

  void selectPeer(String? peerId) {
    if (_localTypingActive) unawaited(setLocalTyping(false));
    selectedPeerId = peerId;
    selectedGroupId = null;
    notifyListeners();
  }

  void selectGroup(String? groupId) {
    if (_localTypingActive) unawaited(setLocalTyping(false));
    selectedGroupId = groupId;
    selectedPeerId = null;
    notifyListeners();
  }

  /// Peers visible in UI (excludes blocked).
  List<Peer> get visiblePeers {
    final list = peers.values.where((p) => !blockList.isBlocked(p.id)).toList();
    list.sort((a, b) => a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        ));
    return list;
  }

  // ── Groups ─────────────────────────────────────────────────────────────

  MeshGroup createGroup({
    required String name,
    Iterable<String> members = const [],
    String? description,
  }) {
    final id = identity;
    if (id == null) throw StateError('no identity');
    final group = groups.create(
      name: name,
      ownerId: id.id,
      members: members,
      description: description,
    );
    selectGroup(group.id);
    chat.addSystem('Created group “${group.name}”', groupId: group.id);
    // Invite members over the mesh.
    for (final mid in group.memberIds) {
      if (mid == id.id) continue;
      unawaited(inviteToGroup(group.id, mid));
    }
    notifyListeners();
    return group;
  }

  Future<void> inviteToGroup(String groupId, String peerId) async {
    final n = node;
    final id = identity;
    final group = groups[groupId];
    if (n == null || id == null || group == null) return;
    if (!group.isAdmin(id.id) && !group.isOwner(id.id)) {
      throw StateError('only admins can invite');
    }
    requireTrustedContact(peerId, action: 'group invite');
    groups.addMember(groupId, peerId);
    final updated = groups[groupId]!;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: peerId,
        kind: MessageKind.control,
        payload: GroupWire.encodeInvite(updated),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    // Catch new members up on the group calendar.
    unawaited(
      pushScopeCalendar(
        scope: CalendarScope.group,
        scopeId: groupId,
        peerId: peerId,
      ),
    );
    chat.addSystem(
      'Invited ${_peerLabel(peerId)} to “${updated.name}”'
      ' · group calendar shared',
      groupId: groupId,
    );
    notifyListeners();
  }

  Future<void> leaveGroup(String groupId) async {
    final n = node;
    final id = identity;
    final group = groups[groupId];
    if (n == null || id == null || group == null) return;
    final payload = GroupWire.encodeLeave(
      groupId: groupId,
      memberId: id.id,
    );
    for (final mid in group.memberIds) {
      if (mid == id.id) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: mid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    groups.remove(groupId);
    if (selectedGroupId == groupId) selectedGroupId = null;
    final cleared = calendars.removeScope(CalendarScope.group, groupId);
    chat.addSystem(
      'Left group “${group.name}”'
      '${cleared > 0 ? " · $cleared calendar event(s) cleared" : ""}',
    );
    notifyListeners();
  }

  Future<void> kickFromGroup(String groupId, String memberId) async {
    final n = node;
    final id = identity;
    final group = groups[groupId];
    if (n == null || id == null || group == null) return;
    if (!group.isAdmin(id.id)) {
      throw StateError('only admins can remove members');
    }
    if (memberId == group.ownerId) {
      throw StateError('cannot remove the group owner');
    }
    groups.removeMember(groupId, memberId);
    final updated = groups[groupId]!;
    final kickPayload = GroupWire.encodeKick(
      groupId: groupId,
      memberId: memberId,
      byId: id.id,
    );
    final updatePayload = GroupWire.encodeUpdate(updated);
    for (final mid in {...updated.memberIds, memberId}) {
      if (mid == id.id) continue;
      final isKickTarget = mid == memberId;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: mid,
          kind: MessageKind.control,
          payload: isKickTarget ? kickPayload : updatePayload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      'Removed ${_peerLabel(memberId)} from “${updated.name}”',
      groupId: groupId,
    );
    notifyListeners();
  }

  void renameGroup(String groupId, String name) {
    final id = identity;
    final group = groups[groupId];
    if (id == null || group == null) return;
    if (!group.isAdmin(id.id)) {
      throw StateError('only admins can rename');
    }
    final updated = groups.rename(groupId, name);
    if (updated == null) return;
    unawaited(_broadcastGroupUpdate(updated));
    chat.addSystem('Renamed group to “${updated.name}”', groupId: groupId);
    notifyListeners();
  }

  Future<void> _broadcastGroupUpdate(MeshGroup group) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    final payload = GroupWire.encodeUpdate(group);
    for (final mid in group.memberIds) {
      if (mid == id.id) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: mid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  void deleteGroupLocally(String groupId) {
    final g = groups[groupId];
    groups.remove(groupId);
    chat.clearGroup(groupId);
    if (selectedGroupId == groupId) selectedGroupId = null;
    if (g != null) chat.addSystem('Deleted group “${g.name}” locally');
    notifyListeners();
  }

  // ── Block / report ─────────────────────────────────────────────────────

  void blockPeer(
    String subjectId, {
    String? displayName,
    String? reason,
  }) {
    if (identity != null && subjectId == identity!.id) return;
    blockList.block(
      subjectId,
      displayName: displayName ?? peers[subjectId]?.displayName,
      reason: reason,
    );
    peers.remove(subjectId);
    trustedCredentials.remove(subjectId);
    trustStore.untrustDirect(subjectId);
    if (selectedPeerId == subjectId) selectedPeerId = null;
    // Remove from groups we own/admin (local only; mesh update best-effort).
    for (final g in groups.all) {
      if (g.isMember(subjectId) &&
          identity != null &&
          g.isAdmin(identity!.id)) {
        groups.removeMember(g.id, subjectId);
        final updated = groups[g.id];
        if (updated != null) unawaited(_broadcastGroupUpdate(updated));
      }
    }
    chat.addSystem('Blocked ${_peerLabel(subjectId)}'
        '${reason != null && reason.isNotEmpty ? " ($reason)" : ""}');
    status = 'Blocked ${subjectId.substring(0, subjectId.length.clamp(0, 8))}';
    notifyListeners();
  }

  void unblockPeer(String subjectId) {
    blockList.unblock(subjectId);
    chat.addSystem('Unblocked ${_peerLabel(subjectId)}');
    notifyListeners();
  }

  Future<UserReport> reportPeer({
    required String subjectId,
    required ReportCategory category,
    String details = '',
    String? groupId,
    String? forwardToPeerId,
  }) async {
    final id = identity;
    if (id == null) throw StateError('no identity');
    final report = UserReport(
      id: 'r-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
      subjectId: subjectId,
      subjectDisplayName: peers[subjectId]?.displayName,
      reporterId: id.id,
      category: category,
      details: details.trim(),
      createdAt: DateTime.now().toUtc(),
      groupId: groupId,
      status:
          forwardToPeerId != null ? ReportStatus.submitted : ReportStatus.local,
    );
    reports.add(report);
    chat.addSystem(
      'Reported ${_peerLabel(subjectId)} · ${category.label}'
      '${forwardToPeerId != null ? " → ${_peerLabel(forwardToPeerId)}" : " (local)"}',
    );

    if (forwardToPeerId != null) {
      final n = node;
      if (n != null) {
        await n.send(
          MeshMessage(
            id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
            sourceId: id.id,
            destinationId: forwardToPeerId,
            kind: MessageKind.control,
            payload: ReportWire.encode(report),
            timestamp: DateTime.now().toUtc(),
          ),
        );
      }
    }
    notifyListeners();
    return report;
  }

  void clearReports() {
    reports.clear();
    notifyListeners();
  }

  /// Enable/disable the in-process mock radio and demo peer (developer only).
  Future<void> setUseMockDemo(bool value) async {
    if (useMockDemo == value) return;
    useMockDemo = value;
    final mgr = transportManager;
    final mock = mockTransport;
    if (mgr != null && mock != null) {
      final already = mgr.transports.contains(mock);
      if (value && !already) {
        // register() starts discovery on the transport if the mesh is already scanning.
        await mgr.register(mock);
        if (running) {
          await mock.startAdvertising(
            localId: identity?.id ?? mock.localId,
            displayName: identity?.displayName ?? mock.displayName,
          );
          await demoPeer?.startAdvertising(
            localId: 'demo-peer-01',
            displayName: 'Demo Peer',
            metadata: const {'demo': 'true'},
          );
        }
        chat.addSystem('Mock demo peer enabled');
      } else if (!value && already) {
        await demoPeer?.stopAdvertising();
        await mock.stopAdvertising();
        await mgr.unregister(mock);
        peers.removeWhere((id, _) => id == 'demo-peer-01');
        chat.addSystem('Mock demo peer disabled');
      }
    }
    status = useMockDemo ? 'Mock demo on' : 'Mock demo off';
    notifyListeners();
  }

  // ── Walkie-talkie / PTT ────────────────────────────────────────────────

  /// Resolve current walkie target: group fan-out, peer unicast, or broadcast.
  ({
    String? to,
    List<String>? recipients,
    String? groupId,
    String label,
  }) walkieTarget() {
    final gid = selectedGroupId;
    if (gid != null) {
      final g = groups[gid];
      final me = identity?.id;
      if (g == null) {
        throw StateError('unknown group');
      }
      if (me == null || !g.isMember(me)) {
        throw StateError('not a member of “${g.name}”');
      }
      final recips =
          g.memberIds.where((m) => m != me && !blockList.isBlocked(m)).toList();
      if (recips.isEmpty) {
        throw StateError('no reachable members in “${g.name}”');
      }
      return (
        to: null,
        recipients: recips,
        groupId: gid,
        label: 'group “${g.name}” (${recips.length})',
      );
    }
    final peer = selectedPeerId;
    if (peer != null) {
      if (blockList.isBlocked(peer)) {
        throw StateError('peer is blocked');
      }
      return (
        to: peer,
        recipients: null,
        groupId: null,
        label: _peerLabel(peer),
      );
    }
    return (
      to: null,
      recipients: null,
      groupId: null,
      label: 'broadcast',
    );
  }

  bool _acceptWalkieIncoming(VoiceTransmission info) {
    final from = info.sourceId;
    if (from != null && blockList.isBlocked(from)) return false;
    final gid = info.groupId;
    if (gid == null || gid.isEmpty) return true;
    // Group-scoped talk: only members accept.
    final g = groups[gid];
    final me = identity?.id;
    if (g == null || me == null) return false;
    return g.isMember(me);
  }

  /// Begin push-to-talk (group / peer / broadcast from selection).
  Future<void> walkiePttDown() async {
    final v = voice;
    if (v == null) throw StateError('voice channel not ready');
    if (v.isTransmitting) return;
    if (familySafety.iAmGrounded) {
      walkieStatus = 'Grounded — walkie paused by parent';
      notifyListeners();
      return;
    }
    final target = walkieTarget();
    await v.beginTalk(
      to: target.to,
      recipients: target.recipients,
      groupId: target.groupId,
    );
    walkieTransmitting = true;
    walkieStatus = 'Transmitting to ${target.label}…';
    walkieBytes = 0;
    notifyListeners();
  }

  /// Send captured PCM while PTT is held (or once on release in burst mode).
  Future<void> walkieSendPcm(Uint8List pcm) async {
    final v = voice;
    if (v == null || !v.isTransmitting) return;
    await v.sendPcmChunk(pcm);
  }

  /// End push-to-talk and flush talk_end.
  Future<void> walkiePttUp() async {
    final v = voice;
    if (v == null) return;
    if (!v.isTransmitting) {
      walkieTransmitting = false;
      notifyListeners();
      return;
    }
    final done = await v.endTalk();
    walkieTransmitting = false;
    walkieStatus = done == null
        ? 'Idle'
        : 'Sent ${(done.totalBytes ?? 0)} B'
            '${done.duration.inMilliseconds > 0 ? " · ${done.duration.inMilliseconds} ms" : ""}';
    notifyListeners();
  }

  Future<void> walkieAbort() async {
    final v = voice;
    if (v == null) return;
    await v.abortTalk();
    walkieTransmitting = false;
    walkieStatus = 'Aborted';
    notifyListeners();
  }

  /// One-shot: send a full PCM clip as a PTT burst.
  Future<void> walkieSendBurst(Uint8List pcm) async {
    final v = voice;
    if (v == null) throw StateError('voice channel not ready');
    if (familySafety.iAmGrounded) {
      walkieStatus = 'Grounded — walkie paused by parent';
      notifyListeners();
      return;
    }
    final target = walkieTarget();
    walkieTransmitting = true;
    walkieStatus = 'Sending to ${target.label}…';
    walkieBytes = pcm.length;
    notifyListeners();
    try {
      final done = await v.sendPcmBurst(
        pcm,
        to: target.to,
        recipients: target.recipients,
        groupId: target.groupId,
      );
      walkieStatus =
          'Sent ${done.totalBytes ?? pcm.length} B · ${done.duration.inMilliseconds} ms'
          ' → ${target.label}';
      chat.addSystem(
        'Walkie TX ${done.totalBytes ?? pcm.length} B → ${target.label}',
      );
    } finally {
      walkieTransmitting = false;
      notifyListeners();
    }
  }

  void _onVoiceEvent(VoiceEvent e) {
    final from = e.transmission?.sourceId;
    if (from != null &&
        blockList.isBlocked(from) &&
        (e.kind == VoiceEventKind.rxStart ||
            e.kind == VoiceEventKind.rxProgress ||
            e.kind == VoiceEventKind.rxComplete ||
            e.kind == VoiceEventKind.rxAbort)) {
      return;
    }
    // Membership filter also applied in acceptIncoming; re-check completes.
    final gid = e.transmission?.groupId;
    if (gid != null &&
        gid.isNotEmpty &&
        (e.kind == VoiceEventKind.rxStart ||
            e.kind == VoiceEventKind.rxComplete)) {
      if (!_acceptWalkieIncoming(e.transmission!)) return;
    }
    final groupName = gid != null ? groups[gid]?.name : null;
    final fromLabel = _peerLabel(e.transmission?.sourceId);
    final via = groupName != null ? ' in “$groupName”' : '';

    switch (e.kind) {
      case VoiceEventKind.txStart:
        walkieTransmitting = true;
        walkieStatus = 'Transmitting…';
      case VoiceEventKind.txProgress:
        walkieBytes = e.bytesTransferred;
        walkieStatus = 'Transmitting… ${e.bytesTransferred} B';
      case VoiceEventKind.txEnd:
        walkieTransmitting = false;
        walkieStatus = 'Sent ${e.bytesTransferred} B';
      case VoiceEventKind.txAbort:
        walkieTransmitting = false;
        walkieStatus = e.detail ?? 'TX aborted';
      case VoiceEventKind.rxStart:
        walkieReceiving = true;
        walkieRemotePeerId = e.transmission?.sourceId;
        walkieStatus = 'Receiving from $fromLabel$via…';
      case VoiceEventKind.rxProgress:
        walkieBytes = e.bytesTransferred;
        walkieStatus = 'Receiving… ${e.bytesTransferred} B';
      case VoiceEventKind.rxComplete:
        walkieReceiving = false;
        walkieRemotePeerId = e.transmission?.sourceId;
        walkieBytes = e.bytesTransferred;
        walkieStatus = 'Received ${e.bytesTransferred} B from $fromLabel$via';
        if (e.pcm != null && e.transmission != null) {
          walkieInbox.insert(
            0,
            WalkieClip(
              transmission: e.transmission!,
              pcm: e.pcm!,
              receivedAt: DateTime.now().toUtc(),
            ),
          );
          if (walkieInbox.length > 20) {
            walkieInbox.removeRange(20, walkieInbox.length);
          }
          chat.addSystem(
            'Walkie RX ${e.bytesTransferred} B from $fromLabel$via',
          );
        }
      case VoiceEventKind.rxAbort:
        walkieReceiving = false;
        walkieStatus = e.detail ?? 'RX aborted';
      case VoiceEventKind.busy:
        walkieStatus = e.detail ?? 'Channel busy';
      case VoiceEventKind.error:
        walkieStatus = e.detail ?? 'Voice error';
    }
    notifyListeners();
  }

  String _peerLabel(String? id) {
    if (id == null || id.isEmpty) return 'broadcast';
    final p = peers[id];
    if (p != null && p.displayName.isNotEmpty) return p.displayName;
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}…';
  }

  Future<void> sendChat(String text) async {
    final n = node;
    final id = identity;
    if (n == null || id == null || text.trim().isEmpty) return;
    final trimmed = text.trim();

    // Sending ends local typing advertisement.
    unawaited(setLocalTyping(false));

    final policy = familySafety.myPolicy;
    // Grounded: no outbound chat until a parent lifts it.
    if (policy != null && policy.grounded) {
      chat.addSystem('Grounded — messaging is paused by your parent.');
      status = 'Grounded';
      notifyListeners();
      return;
    }

    // Kid mode: hold outbound until a parent approves.
    if (policy != null && policy.mode == SafetyMode.child) {
      await _requestMediatedChat(trimmed, policy);
      return;
    }

    await _deliverChat(trimmed);

    // Teen mode: free send + copy to parent and shared teachers/leaders.
    if (policy != null && policy.mode == SafetyMode.teen) {
      await _sendFamilyCopies(text: MessageCensor.censor(trimmed));
    }
  }

  /// Send a photo in the current conversation (DM, group, or broadcast).
  ///
  /// [bytes] must be ≤ [ChatImageWire.maxBytes]. Prefer JPEG/PNG/WebP/GIF.
  Future<void> sendChatImage({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/jpeg',
    String caption = '',
  }) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    if (bytes.isEmpty) throw StateError('empty image');
    if (bytes.length > ChatImageWire.maxBytes) {
      throw StateError(
        'Photo is too large (${(bytes.length / 1024).round()} KB). '
        'Max ${(ChatImageWire.maxBytes / 1024).round()} KB — try a smaller image.',
      );
    }
    if (!ChatImageWire.looksLikeImageMime(mimeType) &&
        !fileName.toLowerCase().contains('.')) {
      mimeType = 'image/jpeg';
    }

    unawaited(setLocalTyping(false));

    final policy = familySafety.myPolicy;
    if (policy != null && policy.grounded) {
      chat.addSystem('Grounded — messaging is paused by your parent.');
      status = 'Grounded';
      notifyListeners();
      return;
    }

    final name = fileName.trim().isEmpty ? 'photo.jpg' : fileName.trim();
    final mime = mimeType.trim().isEmpty ? 'image/jpeg' : mimeType.trim();
    final cap = caption.trim();

    if (policy != null && policy.mode == SafetyMode.child) {
      await _requestMediatedImage(
        bytes: bytes,
        fileName: name,
        mimeType: mime,
        caption: cap,
        policy: policy,
      );
      return;
    }

    await _deliverChatImage(
      bytes: bytes,
      fileName: name,
      mimeType: mime,
      caption: cap,
    );

    if (policy != null && policy.mode == SafetyMode.teen) {
      await _sendFamilyCopies(
        text: cap.isEmpty ? '📷 $name' : '📷 $name · $cap',
      );
    }
  }

  Future<void> _deliverChatImage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String caption = '',
    String? toPeerId,
    String? toGroupId,
    bool useSelection = true,
  }) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    final msgId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final now = DateTime.now().toUtc();
    final String? gid;
    final String? to;
    if (useSelection) {
      gid = toGroupId ?? selectedGroupId;
      to = toPeerId ?? (gid != null ? null : selectedPeerId);
    } else {
      gid = toGroupId;
      to = toPeerId;
    }

    final label = caption.isEmpty ? '📷 $fileName' : caption;
    final payloadStr = ChatImageWire.encode(
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      groupId: gid,
      caption: caption,
    );
    final body = Uint8List.fromList(utf8.encode(payloadStr));

    if (gid != null) {
      final group = groups[gid];
      if (group == null || !group.isMember(id.id)) {
        throw StateError('not a member of this group');
      }
      chat.addLocalChat(
        text: label,
        messageId: msgId,
        groupId: gid,
        senderName: id.displayName,
        imageBytes: bytes,
        imageMime: mimeType,
        imageName: fileName,
      );
      for (final mid in group.memberIds) {
        if (mid == id.id) continue;
        if (blockList.isBlocked(mid)) continue;
        await n.send(
          MeshMessage(
            id: msgId,
            sourceId: id.id,
            destinationId: mid,
            kind: MessageKind.chat,
            payload: body,
            timestamp: now,
          ),
        );
      }
      notifyListeners();
      return;
    }

    if (to != null && blockList.isBlocked(to)) {
      throw StateError('peer is blocked');
    }
    chat.addLocalChat(
      text: label,
      to: to,
      messageId: msgId,
      senderName: id.displayName,
      imageBytes: bytes,
      imageMime: mimeType,
      imageName: fileName,
    );
    await n.send(
      MeshMessage(
        id: msgId,
        sourceId: id.id,
        destinationId: to,
        kind: MessageKind.chat,
        payload: body,
        timestamp: now,
      ),
    );
    notifyListeners();
  }

  Future<void> _requestMediatedImage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    required String caption,
    required MySafetyPolicy policy,
  }) async {
    final label = caption.isEmpty ? '📷 $fileName' : '📷 $fileName · $caption';
    // Reuse text mediation; keep bytes until parent OK.
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    final gid = selectedGroupId;
    final to = selectedPeerId;
    final toLabel = gid != null
        ? (groups[gid]?.name ?? 'group')
        : (to == null ? 'Everyone' : _peerLabel(to));
    final pending = PendingMediatedMessage(
      requestId: 'fm-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
      fromId: id.id,
      fromName: id.displayName,
      toPeerId: gid == null ? to : null,
      toGroupId: gid,
      toLabel: toLabel,
      text: label,
      createdAt: DateTime.now().toUtc(),
    );
    _pendingOutboundImages[pending.requestId] = (
      bytes: bytes,
      mime: mimeType,
      name: fileName,
      caption: caption,
    );
    final payload = FamilySafetyWire.encodeMediateRequest(pending);
    for (final parentId in policy.allParentIds) {
      if (parentId == id.id || blockList.isBlocked(parentId)) continue;
      await n.send(
        MeshMessage(
          id: '${pending.requestId}-$parentId',
          sourceId: id.id,
          destinationId: parentId,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      'Waiting for a parent to approve photo to $toLabel: $label',
      groupId: gid,
    );
    status = 'Waiting for parent OK…';
    notifyListeners();
  }

  /// Actually put [text] on the mesh (DM, group, or broadcast).
  ///
  /// When [useSelection] is true (default), falls back to the current
  /// conversation. When false, uses only the explicit destinations
  /// (e.g. a parent-approved kid message).
  Future<void> _deliverChat(
    String text, {
    String? toPeerId,
    String? toGroupId,
    bool useSelection = true,
  }) async {
    final n = node;
    final id = identity;
    if (n == null || id == null || text.trim().isEmpty) return;
    final trimmed = text.trim();
    final msgId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final now = DateTime.now().toUtc();
    final String? gid;
    final String? to;
    if (useSelection) {
      gid = toGroupId ?? selectedGroupId;
      to = toPeerId ?? (gid != null ? null : selectedPeerId);
    } else {
      gid = toGroupId;
      to = toPeerId;
    }

    if (gid != null) {
      final group = groups[gid];
      if (group == null || !group.isMember(id.id)) {
        throw StateError('not a member of this group');
      }
      final safeText = MessageCensor.censor(trimmed);
      chat.addLocalChat(
        text: safeText,
        messageId: msgId,
        groupId: gid,
        senderName: id.displayName,
      );
      final body = Uint8List.fromList(
        utf8.encode(GroupChatWire.encode(groupId: gid, text: safeText)),
      );
      for (final mid in group.memberIds) {
        if (mid == id.id) continue;
        if (blockList.isBlocked(mid)) continue;
        await n.send(
          MeshMessage(
            id: msgId,
            sourceId: id.id,
            destinationId: mid,
            kind: MessageKind.chat,
            payload: body,
            timestamp: now,
          ),
        );
      }
      notifyListeners();
      return;
    }

    if (to != null && blockList.isBlocked(to)) {
      throw StateError('peer is blocked');
    }
    final safeText = MessageCensor.censor(trimmed);
    chat.addLocalChat(
      text: safeText,
      to: to,
      messageId: msgId,
      senderName: id.displayName,
    );
    await n.send(
      MeshMessage(
        id: msgId,
        sourceId: id.id,
        destinationId: to,
        kind: MessageKind.chat,
        payload: Uint8List.fromList(utf8.encode(safeText)),
        timestamp: now,
      ),
    );
    notifyListeners();
  }

  Future<void> _requestMediatedChat(
    String text,
    MySafetyPolicy policy,
  ) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    final safeText = MessageCensor.censor(text.trim());
    final gid = selectedGroupId;
    final to = selectedPeerId;
    final toLabel = gid != null
        ? (groups[gid]?.name ?? 'group')
        : (to == null ? 'Everyone' : _peerLabel(to));
    final pending = PendingMediatedMessage(
      requestId: 'fm-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
      fromId: id.id,
      fromName: id.displayName,
      toPeerId: gid == null ? to : null,
      toGroupId: gid,
      toLabel: toLabel,
      text: safeText,
      createdAt: DateTime.now().toUtc(),
    );
    final payload = FamilySafetyWire.encodeMediateRequest(pending);
    // Fan-out to every co-parent so Mom and Dad both see the request.
    for (final parentId in policy.allParentIds) {
      if (parentId == id.id || blockList.isBlocked(parentId)) continue;
      await n.send(
        MeshMessage(
          id: '${pending.requestId}-$parentId',
          sourceId: id.id,
          destinationId: parentId,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      'Waiting for a parent to approve message to $toLabel: “$safeText”',
      groupId: gid,
    );
    status = 'Waiting for parent OK…';
    notifyListeners();
  }

  Future<void> _sendFamilyCopies({
    required String text,
    String? toPeerId,
    String? toGroupId,
    bool useSelection = true,
  }) async {
    final n = node;
    final id = identity;
    final policy = familySafety.myPolicy;
    if (n == null || id == null || policy == null) return;
    final String? gid;
    final String? to;
    if (useSelection) {
      gid = toGroupId ?? selectedGroupId;
      to = toPeerId ?? (gid != null ? null : selectedPeerId);
    } else {
      gid = toGroupId;
      to = toPeerId;
    }
    final toLabel = gid != null
        ? (groups[gid]?.name ?? 'group')
        : (to == null ? 'Everyone' : _peerLabel(to));
    final payload = FamilySafetyWire.encodeCopy(
      fromId: id.id,
      fromName: id.displayName,
      toLabel: toLabel,
      text: text,
      toPeerId: to,
      toGroupId: gid,
    );
    // All co-parents + teachers/leaders stay informed.
    final recipients = <String>{
      ...policy.allParentIds,
      ...policy.sharedWithIds,
    }..remove(id.id);
    for (final rid in recipients) {
      if (blockList.isBlocked(rid)) continue;
      await n.send(
        MeshMessage(
          id: 'fc-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
          sourceId: id.id,
          destinationId: rid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  // ── Family safety ──────────────────────────────────────────────────────

  /// Parent: put [wardId] under Teen (transparent) or Kid (mediated) care.
  ///
  /// Optional [sharedWithIds] = teachers / coaches / leaders who also see
  /// copies (they do not approve kid messages).
  ///
  /// Optional [coParentIds] = other parents (e.g. Mom/Dad) who share the same
  /// privilege status and can approve.
  Future<void> setupWard({
    required String wardId,
    required SafetyMode mode,
    String? displayName,
    List<String> sharedWithIds = const [],
    List<String> coParentIds = const [],
  }) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    if (wardId == id.id) {
      throw StateError('cannot supervise yourself');
    }
    // Family safety only for QR/NFC-trusted devices — never radio-only peers.
    requireTrustedContact(wardId, action: 'family safety setup');
    for (final sid in sharedWithIds) {
      requireTrustedContact(sid, action: 'teacher/leader share');
    }
    for (final pid in coParentIds) {
      requireTrustedContact(pid, action: 'co-parent setup');
    }
    final shareNames = <String, String>{
      for (final sid in sharedWithIds) sid: _peerLabel(sid),
    };
    final parentIds = <String>{id.id, ...coParentIds}
      ..remove(wardId);
    final parentNames = <String, String>{
      id.id: id.displayName,
      for (final pid in parentIds)
        if (pid != id.id) pid: _peerLabel(pid),
    };
    final now = DateTime.now().toUtc();
    final ward = WardProfile(
      wardId: wardId,
      displayName: displayName ?? _peerLabel(wardId),
      mode: mode,
      grounded: false,
      parentIds: parentIds.toList(),
      parentNames: parentNames,
      sharedWithIds: List<String>.from(sharedWithIds),
      sharedWithNames: shareNames,
      createdAt: now,
      statusUpdatedAt: now,
      statusById: id.id,
      statusByName: id.displayName,
    );
    familySafety.putWard(ward);
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    chat.addSystem(
      'Family safety: ${ward.displayName} → ${ward.privilegeLabel}'
      ' · parents: ${ward.parentsLabel(selfId: id.id)}'
      '${sharedWithIds.isEmpty ? '' : ' · shared with ${sharedWithIds.length}'}',
    );
    status = '${ward.privilegeLabel} for ${ward.displayName}';
    notifyListeners();
  }

  Future<void> updateWardMode(String wardId, SafetyMode mode) async {
    final id = identity;
    final w = familySafety.wards[wardId];
    if (id == null || w == null) return;
    familySafety.putWard(
      w.copyWith(mode: mode).withStatusTouch(
            byId: id.id,
            byName: id.displayName,
          ),
    );
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    final updated = familySafety.wards[wardId]!;
    chat.addSystem(
      '${updated.displayName} privilege → ${updated.privilegeLabel}'
      ' (synced with co-parents)',
    );
    notifyListeners();
  }

  /// Parent: freeze or unfreeze outbound chat/walkie for a kid or teen.
  ///
  /// Base mode (Teen/Kid) is kept; grounded is an overlay parents can toggle.
  /// Co-parents receive the same privilege status immediately.
  Future<void> setWardGrounded(String wardId, bool grounded) async {
    final id = identity;
    final w = familySafety.wards[wardId];
    if (id == null || w == null) return;
    familySafety.putWard(
      w.copyWith(grounded: grounded).withStatusTouch(
            byId: id.id,
            byName: id.displayName,
          ),
    );
    if (grounded) {
      familySafety.clearPendingForWard(wardId);
    }
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    final updated = familySafety.wards[wardId]!;
    chat.addSystem(
      grounded
          ? 'Grounded ${updated.displayName} — messaging paused (family synced)'
          : 'Ungrounded ${updated.displayName} — messaging restored (family synced)',
    );
    status = '${updated.displayName}: ${updated.privilegeLabel}';
    notifyListeners();
  }

  Future<void> updateWardShared(
    String wardId,
    List<String> sharedWithIds,
  ) async {
    final id = identity;
    final w = familySafety.wards[wardId];
    if (id == null || w == null) return;
    for (final sid in sharedWithIds) {
      requireTrustedContact(sid, action: 'teacher/leader share');
    }
    final names = <String, String>{
      for (final sid in sharedWithIds) sid: _peerLabel(sid),
    };
    familySafety.putWard(
      w
          .copyWith(sharedWithIds: sharedWithIds, sharedWithNames: names)
          .withStatusTouch(byId: id.id, byName: id.displayName),
    );
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    chat.addSystem(
      'Shared ${w.displayName} with ${sharedWithIds.length} teacher(s)/leader(s)'
      ' (family synced)',
    );
    notifyListeners();
  }

  /// Add another parent (Mom/Dad) so both share privilege status.
  Future<void> addCoParent({
    required String wardId,
    required String parentId,
    String? parentName,
  }) async {
    final id = identity;
    final w = familySafety.wards[wardId];
    if (id == null || w == null) return;
    if (parentId == wardId || parentId == id.id) {
      throw StateError('invalid co-parent');
    }
    requireTrustedContact(parentId, action: 'adding co-parent');
    if (w.parentIds.contains(parentId)) return;
    final names = Map<String, String>.from(w.parentNames)
      ..[parentId] = parentName ?? _peerLabel(parentId)
      ..[id.id] = id.displayName;
    final parents = [...w.parentIds, parentId];
    if (!parents.contains(id.id)) parents.insert(0, id.id);
    familySafety.putWard(
      w
          .copyWith(parentIds: parents, parentNames: names)
          .withStatusTouch(byId: id.id, byName: id.displayName),
    );
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    final updated = familySafety.wards[wardId]!;
    chat.addSystem(
      'Co-parent ${names[parentId]} added for ${updated.displayName}'
      ' — same privilege page: ${updated.privilegeLabel}',
    );
    status = 'Co-parent added for ${updated.displayName}';
    notifyListeners();
  }

  Future<void> removeCoParent({
    required String wardId,
    required String parentId,
  }) async {
    final id = identity;
    final w = familySafety.wards[wardId];
    if (id == null || w == null) return;
    if (parentId == id.id) {
      throw StateError('cannot remove yourself this way — use Stop supervising');
    }
    final parents = w.parentIds.where((p) => p != parentId).toList();
    final names = Map<String, String>.from(w.parentNames)..remove(parentId);
    familySafety.putWard(
      w
          .copyWith(parentIds: parents, parentNames: names)
          .withStatusTouch(byId: id.id, byName: id.displayName),
    );
    await _pushWardLink(wardId);
    await _syncPrivilegeToCoParents(wardId);
    // Tell removed parent they no longer supervise (status without them).
    final n = node;
    final updated = familySafety.wards[wardId]!;
    if (n != null) {
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: parentId,
          kind: MessageKind.control,
          payload: FamilySafetyWire.encodeStatus(
            ward: updated,
            updatedById: id.id,
            updatedByName: id.displayName,
          ),
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      'Removed co-parent from ${updated.displayName}',
    );
    notifyListeners();
  }

  Future<void> removeWard(String wardId) async {
    final w = familySafety.wards[wardId];
    familySafety.removeWard(wardId);
    if (w != null) {
      chat.addSystem('Stopped supervising ${w.displayName}');
    }
    notifyListeners();
  }

  Future<void> _pushWardLink(String wardId) async {
    final n = node;
    final id = identity;
    final w = familySafety.wards[wardId];
    if (n == null || id == null || w == null) return;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: wardId,
        kind: MessageKind.control,
        payload: FamilySafetyWire.encodeLink(
          guardianId: id.id,
          guardianName: id.displayName,
          mode: w.mode,
          sharedWithIds: w.sharedWithIds,
          grounded: w.grounded,
          parentIds: w.parentIds,
          parentNames: w.parentNames,
        ),
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  /// Push privilege snapshot to every co-parent so Mom/Dad stay aligned.
  Future<void> _syncPrivilegeToCoParents(String wardId) async {
    final n = node;
    final id = identity;
    final w = familySafety.wards[wardId];
    if (n == null || id == null || w == null) return;
    final payload = FamilySafetyWire.encodeStatus(
      ward: w,
      updatedById: id.id,
      updatedByName: id.displayName,
    );
    for (final pid in w.parentIds) {
      if (pid == id.id || blockList.isBlocked(pid)) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: pid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<void> _notifyCoParentsSettled({
    required PendingMediatedMessage pending,
    required bool approved,
  }) async {
    final n = node;
    final id = identity;
    final ward = familySafety.wards[pending.fromId];
    if (n == null || id == null || ward == null) return;
    final payload = FamilySafetyWire.encodeSettle(
      requestId: pending.requestId,
      approved: approved,
      byId: id.id,
      byName: id.displayName,
      fromId: pending.fromId,
      fromName: pending.fromName,
      toLabel: pending.toLabel,
      text: pending.text,
    );
    for (final pid in ward.parentIds) {
      if (pid == id.id || blockList.isBlocked(pid)) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: pid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// Parent: allow a held kid message (child then sends it).
  Future<void> approveMediated(String requestId) async {
    final n = node;
    final id = identity;
    final pending = familySafety.takePending(requestId);
    if (n == null || id == null || pending == null) return;
    final ward = familySafety.wards[pending.fromId];
    if (ward != null && ward.grounded) {
      chat.addSystem(
        '${pending.fromName} is grounded — cannot approve messages',
      );
      status = '${pending.fromName} is grounded';
      notifyListeners();
      return;
    }
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: pending.fromId,
        kind: MessageKind.control,
        payload: FamilySafetyWire.encodeMediateDecision(
          requestId: pending.requestId,
          approved: true,
          guardianId: id.id,
          toPeerId: pending.toPeerId,
          toGroupId: pending.toGroupId,
          text: pending.text,
        ),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    // Keep co-parents on the same page (drop their pending card).
    await _notifyCoParentsSettled(pending: pending, approved: true);
    // Also notify shared teachers/leaders of the released message.
    final wardForCopy = familySafety.wards[pending.fromId];
    if (wardForCopy != null) {
      final copy = FamilySafetyWire.encodeCopy(
        fromId: pending.fromId,
        fromName: pending.fromName,
        toLabel: pending.toLabel,
        text: pending.text,
        toPeerId: pending.toPeerId,
        toGroupId: pending.toGroupId,
      );
      final extra = <String>{
        ...wardForCopy.sharedWithIds,
        // Other parents also get the released copy in activity.
        ...wardForCopy.parentIds,
      }..remove(id.id);
      for (final sid in extra) {
        if (blockList.isBlocked(sid)) continue;
        await n.send(
          MeshMessage(
            id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
            sourceId: id.id,
            destinationId: sid,
            kind: MessageKind.control,
            payload: copy,
            timestamp: DateTime.now().toUtc(),
          ),
        );
      }
    }
    familySafety.addCopy(
      SafetyCopy(
        id: pending.requestId,
        fromId: pending.fromId,
        fromName: pending.fromName,
        toLabel: pending.toLabel,
        text: pending.text,
        at: DateTime.now().toUtc(),
        mediatedRelease: true,
      ),
    );
    chat.addSystem(
      'Approved ${pending.fromName} → ${pending.toLabel}: “${pending.text}”'
      ' (co-parents notified)',
    );
    status = 'Approved message from ${pending.fromName}';
    notifyListeners();
  }

  /// Parent: block a held kid message.
  Future<void> denyMediated(String requestId) async {
    final n = node;
    final id = identity;
    final pending = familySafety.takePending(requestId);
    if (n == null || id == null || pending == null) return;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: pending.fromId,
        kind: MessageKind.control,
        payload: FamilySafetyWire.encodeMediateDecision(
          requestId: pending.requestId,
          approved: false,
          guardianId: id.id,
          toPeerId: pending.toPeerId,
          toGroupId: pending.toGroupId,
          text: pending.text,
        ),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    await _notifyCoParentsSettled(pending: pending, approved: false);
    chat.addSystem(
      'Declined ${pending.fromName} → ${pending.toLabel}: “${pending.text}”'
      ' (co-parents notified)',
    );
    status = 'Declined message from ${pending.fromName}';
    notifyListeners();
  }

  void clearMySafetyPolicy() {
    familySafety.setMyPolicy(null);
    chat.addSystem('Family safety policy cleared on this device');
    notifyListeners();
  }

  // ── Teen discuss-first notes ───────────────────────────────────────────

  /// Teen: send parents a private note to discuss *before* sending a real message.
  ///
  /// [discretion] controls who receives it (never teachers/leaders).
  Future<DiscussNote> sendDiscussNote({
    required String text,
    NoteDiscretion discretion = NoteDiscretion.parents,
  }) async {
    final n = node;
    final id = identity;
    final policy = familySafety.myPolicy;
    if (n == null || id == null) throw StateError('not ready');
    if (policy == null || policy.mode != SafetyMode.teen) {
      throw StateError('discuss notes are for Teen mode');
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw StateError('write a note first');

    final note = DiscussNote(
      id: 'dn-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}',
      fromId: id.id,
      fromName: id.displayName,
      text: trimmed,
      discretion: discretion,
      status: DiscussNoteStatus.open,
      createdAt: DateTime.now().toUtc(),
    );
    familySafety.putDiscussNote(note);

    final recipients = <String>{};
    switch (discretion) {
      case NoteDiscretion.private:
        recipients.add(policy.guardianId);
      case NoteDiscretion.parents:
      case NoteDiscretion.family:
        recipients.addAll(policy.allParentIds);
    }
    recipients.remove(id.id);

    final payload = FamilySafetyWire.encodeDiscussNote(note);
    for (final rid in recipients) {
      if (blockList.isBlocked(rid)) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: rid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      'Discuss note sent (${discretion.shortLabel}): “$trimmed”',
    );
    status = 'Discuss note sent';
    notifyListeners();
    return note;
  }

  /// Parent: mark a discuss note as seen or fully discussed.
  Future<void> acknowledgeDiscussNote(
    String noteId, {
    DiscussNoteStatus status = DiscussNoteStatus.acknowledged,
  }) async {
    final n = node;
    final id = identity;
    final note = familySafety.discussNote(noteId);
    if (n == null || id == null || note == null) return;
    if (status == DiscussNoteStatus.open) return;

    final updated = note.copyWith(
      status: status,
      acknowledgedAt: DateTime.now().toUtc(),
      acknowledgedById: id.id,
      acknowledgedByName: id.displayName,
    );
    familySafety.putDiscussNote(updated);

    final payload = FamilySafetyWire.encodeDiscussAck(
      noteId: noteId,
      status: status,
      byId: id.id,
      byName: id.displayName,
    );
    // Notify teen + co-parents (except self).
    final targets = <String>{note.fromId};
    final ward = familySafety.wards[note.fromId];
    if (ward != null) targets.addAll(ward.parentIds);
    targets.remove(id.id);
    for (final tid in targets) {
      if (blockList.isBlocked(tid)) continue;
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: tid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
    chat.addSystem(
      status == DiscussNoteStatus.closed
          ? 'Discussed note from ${note.fromName}'
          : 'Acknowledged note from ${note.fromName}',
    );
    notifyListeners();
  }

  // ── Time log (24-hour schedule) ────────────────────────────────────────

  void logTimeSlot({
    required DateTime localDay,
    required int hour,
    required String activity,
    String? notes,
  }) {
    timeLog.setSlot(
      localDay: localDay,
      hour: hour,
      activity: activity,
      notes: notes,
    );
    notifyListeners();
  }

  void clearTimeSlot(DateTime localDay, int hour) {
    timeLog.clearSlot(localDay, hour);
    notifyListeners();
  }

  bool get shouldPromptTimeLog => timeLog.shouldPromptNow();

  // ── Calendars (personal / family / group / organization) ───────────────

  /// Build audience list for a calendar scope (who gets mesh copies).
  ///
  /// Group calendars go to **current group members**. Organization calendars
  /// go to **known trusted org subjects** plus nearby peers that trust the org
  /// (receivers still filter on local trust).
  List<String> calendarAudience({
    required CalendarScope scope,
    required String scopeId,
  }) {
    final id = identity?.id;
    final out = <String>{};
    if (id != null) out.add(id);

    switch (scope) {
      case CalendarScope.individual:
        if (scopeId.isNotEmpty && scopeId != id) out.add(scopeId);
      case CalendarScope.family:
        for (final w in familySafety.wards.values) {
          out.add(w.wardId);
          out.addAll(w.parentIds);
        }
        final pol = familySafety.myPolicy;
        if (pol != null) {
          out.addAll(pol.allParentIds);
        }
        if (scopeId.isNotEmpty && scopeId != 'family') {
          out.add(scopeId);
        }
      case CalendarScope.group:
        final g = groups[scopeId];
        if (g != null) {
          out.addAll(g.memberIds);
        }
      case CalendarScope.organization:
        // Only QR/NFC-trusted contacts and known org subjects — never all radio peers.
        out.addAll(trustStore.subjectsForOrganization(scopeId));
        for (final sid in trustedCredentials.keys) {
          out.add(sid);
        }
        for (final sid in trustStore.directPeers.keys) {
          out.add(sid);
        }
    }
    out.removeWhere(blockList.isBlocked);
    return out.toList();
  }

  String calendarScopeLabel(CalendarEvent e) {
    switch (e.scope) {
      case CalendarScope.individual:
        if (e.scopeId.isEmpty || e.scopeId == identity?.id) {
          return 'Personal';
        }
        return 'With ${_peerLabel(e.scopeId)}';
      case CalendarScope.family:
        return 'Family';
      case CalendarScope.group:
        return groups[e.scopeId]?.name ?? 'Group';
      case CalendarScope.organization:
        return trustStore.organizations[e.scopeId]?.name ?? 'Organization';
    }
  }

  Future<CalendarEvent> upsertCalendarEvent({
    String? id,
    required String title,
    String? description,
    String? location,
    required DateTime start,
    DateTime? end,
    bool allDay = false,
    required CalendarScope scope,
    String scopeId = '',
  }) async {
    final me = identity;
    if (me == null) throw StateError('no identity');
    final trimmed = title.trim();
    if (trimmed.isEmpty) throw StateError('title required');

    var resolvedScopeId = scopeId;
    switch (scope) {
      case CalendarScope.individual:
        break;
      case CalendarScope.family:
        if (resolvedScopeId.isEmpty) resolvedScopeId = 'family';
      case CalendarScope.group:
        if (resolvedScopeId.isEmpty) {
          throw StateError('pick a group');
        }
        final g = groups[resolvedScopeId];
        if (g == null || !g.isMember(me.id)) {
          throw StateError('not a member of this group');
        }
      case CalendarScope.organization:
        if (resolvedScopeId.isEmpty) {
          throw StateError('pick an organization');
        }
        if (!trustStore.organizations.containsKey(resolvedScopeId)) {
          throw StateError('organization not trusted');
        }
    }

    final startUtc = start.toUtc();
    final endUtc = (end ?? start.add(const Duration(hours: 1))).toUtc();
    if (!endUtc.isAfter(startUtc) && !allDay) {
      throw StateError('end must be after start');
    }

    final audience = calendarAudience(scope: scope, scopeId: resolvedScopeId);
    final existing = id != null ? calendars[id] : null;
    final event = CalendarEvent(
      id: id ?? existing?.id ?? CalendarEvent.newId(),
      title: trimmed,
      description: description?.trim().isEmpty == true
          ? null
          : description?.trim(),
      location:
          location?.trim().isEmpty == true ? null : location?.trim(),
      start: allDay
          ? DateTime.utc(startUtc.year, startUtc.month, startUtc.day)
          : startUtc,
      end: allDay
          ? DateTime.utc(endUtc.year, endUtc.month, endUtc.day)
              .add(const Duration(days: 1))
          : endUtc,
      allDay: allDay,
      scope: scope,
      scopeId: resolvedScopeId,
      creatorId: existing?.creatorId ?? me.id,
      creatorName: existing?.creatorName ?? me.displayName,
      audienceIds: audience,
      updatedAt: DateTime.now().toUtc(),
    );
    calendars.putForce(event);
    await _fanoutCalendarUpsert(event);
    chat.addSystem(
      'Calendar: ${event.title} · ${calendarScopeLabel(event)}'
      ' · synced to ${audience.length - (audience.contains(me.id) ? 1 : 0)}',
    );
    status = 'Saved ${event.title}';
    notifyListeners();
    return event;
  }

  Future<void> deleteCalendarEvent(String eventId) async {
    final me = identity;
    final n = node;
    final existing = calendars.remove(eventId);
    if (existing == null) {
      notifyListeners();
      return;
    }
    if (me != null && n != null) {
      final payload = CalendarWire.encodeDelete(
        eventId: eventId,
        byId: me.id,
        scope: existing.scope.name,
        scopeId: existing.scopeId,
      );
      // Live audience (membership may have changed since create).
      final targets = <String>{
        ...existing.audienceIds,
        ...calendarAudience(
          scope: existing.scope,
          scopeId: existing.scopeId,
        ),
      }..remove(me.id);
      for (final tid in targets) {
        if (blockList.isBlocked(tid)) continue;
        await n.send(
          MeshMessage(
            id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
            sourceId: me.id,
            destinationId: tid,
            kind: MessageKind.control,
            payload: payload,
            timestamp: DateTime.now().toUtc(),
          ),
        );
      }
    }
    chat.addSystem('Calendar removed: ${existing.title}');
    notifyListeners();
  }

  /// Push all local events for a scope to [peerId] (membership catch-up).
  Future<void> pushScopeCalendar({
    required CalendarScope scope,
    required String scopeId,
    required String peerId,
  }) async {
    final n = node;
    final me = identity;
    if (n == null || me == null) return;
    if (peerId == me.id || blockList.isBlocked(peerId)) return;
    if (!_mayShareScopeWith(scope: scope, scopeId: scopeId, peerId: peerId)) {
      return;
    }
    final events = calendars.forScope(scope, scopeId: scopeId);
    for (final e in events) {
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: me.id,
          destinationId: peerId,
          kind: MessageKind.control,
          payload: CalendarWire.encodeUpsert(e),
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// Ask [peerId] for their copy of a group/org/family calendar.
  Future<void> requestScopeCalendar({
    required CalendarScope scope,
    required String scopeId,
    required String peerId,
  }) async {
    final n = node;
    final me = identity;
    if (n == null || me == null) return;
    if (peerId == me.id || blockList.isBlocked(peerId)) return;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: me.id,
        destinationId: peerId,
        kind: MessageKind.control,
        payload: CalendarWire.encodeSyncRequest(
          scope: scope,
          scopeId: scopeId,
          fromId: me.id,
        ),
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  /// Re-sync group calendars with all current members (and pull from them).
  Future<void> resyncGroupCalendars(String groupId) async {
    final me = identity;
    final g = groups[groupId];
    if (me == null || g == null || !g.isMember(me.id)) return;
    var pushed = 0;
    for (final mid in g.memberIds) {
      if (mid == me.id || blockList.isBlocked(mid)) continue;
      await pushScopeCalendar(
        scope: CalendarScope.group,
        scopeId: groupId,
        peerId: mid,
      );
      await requestScopeCalendar(
        scope: CalendarScope.group,
        scopeId: groupId,
        peerId: mid,
      );
      pushed++;
    }
    chat.addSystem(
      'Group calendar sync for “${g.name}” with $pushed member(s)',
      groupId: groupId,
    );
    status = 'Synced group calendar';
    notifyListeners();
  }

  /// Re-sync organization calendars with known/visible org participants.
  Future<void> resyncOrganizationCalendars(String orgId) async {
    final me = identity;
    if (me == null) return;
    if (!trustStore.organizations.containsKey(orgId)) {
      throw StateError('organization not trusted');
    }
    final targets = <String>{
      ...trustStore.subjectsForOrganization(orgId),
      ...trustedCredentials.keys,
      ...trustStore.directPeers.keys,
    }..remove(me.id);
    var n = 0;
    for (final tid in targets) {
      if (blockList.isBlocked(tid)) continue;
      await pushScopeCalendar(
        scope: CalendarScope.organization,
        scopeId: orgId,
        peerId: tid,
      );
      await requestScopeCalendar(
        scope: CalendarScope.organization,
        scopeId: orgId,
        peerId: tid,
      );
      n++;
    }
    final name = trustStore.organizations[orgId]?.name ?? orgId;
    chat.addSystem('Org calendar sync for “$name” with $n peer(s)');
    status = 'Synced org calendar';
    notifyListeners();
  }

  /// Whether we are allowed to share [scope]/[scopeId] events with [peerId].
  bool _mayShareScopeWith({
    required CalendarScope scope,
    required String scopeId,
    required String peerId,
  }) {
    final me = identity?.id;
    if (me == null) return false;
    switch (scope) {
      case CalendarScope.individual:
        return peerId == scopeId || scopeId == me || scopeId.isEmpty;
      case CalendarScope.family:
        return true; // family graph filtered at accept
      case CalendarScope.group:
        final g = groups[scopeId];
        return g != null && g.isMember(me) && g.isMember(peerId);
      case CalendarScope.organization:
        // We only push if we trust the org; peer filters on receive.
        return trustStore.organizations.containsKey(scopeId);
    }
  }

  Future<void> _fanoutCalendarUpsert(CalendarEvent event) async {
    final n = node;
    final me = identity;
    if (n == null || me == null) return;
    if (event.scope == CalendarScope.individual &&
        (event.scopeId.isEmpty || event.scopeId == me.id)) {
      return;
    }
    final payload = CalendarWire.encodeUpsert(event);
    // Always recompute live audience so group/org membership stays current.
    final targets = <String>{
      ...event.audienceIds,
      ...calendarAudience(scope: event.scope, scopeId: event.scopeId),
    }..remove(me.id);
    for (final tid in targets) {
      if (blockList.isBlocked(tid)) continue;
      if (!_mayShareScopeWith(
        scope: event.scope,
        scopeId: event.scopeId,
        peerId: tid,
      )) {
        // Org still fans out to visible peers for discovery.
        if (event.scope != CalendarScope.organization) continue;
      }
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: me.id,
          destinationId: tid,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
    }
  }

  bool _acceptCalendarEvent(CalendarEvent event, {String? meshSourceId}) {
    final me = identity?.id;
    if (me == null) return false;
    if (event.creatorId == me) return true;
    // Mesh source must be QR/NFC-trusted (never radio-only identity).
    final src = meshSourceId ?? event.creatorId;
    if (!_isTrustedSource(src) && !isTrustedContact(event.creatorId)) {
      return false;
    }

    switch (event.scope) {
      case CalendarScope.individual:
        return event.scopeId == me ||
            isTrustedContact(event.creatorId) ||
            isTrustedContact(event.scopeId);
      case CalendarScope.family:
        if (!isTrustedContact(event.creatorId) &&
            !_isTrustedSource(src)) {
          return false;
        }
        if (familySafety.wards.containsKey(event.creatorId)) return true;
        if (familySafety.myPolicy != null &&
            familySafety.myPolicy!.allParentIds.contains(src)) {
          return true;
        }
        for (final w in familySafety.wards.values) {
          if (w.parentIds.contains(event.creatorId) ||
              w.parentIds.contains(src)) {
            return true;
          }
        }
        return false;
      case CalendarScope.group:
        final g = groups[event.scopeId];
        return g != null && g.isMember(me) && g.isMember(src);
      case CalendarScope.organization:
        // Org root trusted via QR/NFC; sender trusted or known org subject.
        if (!trustStore.organizations.containsKey(event.scopeId)) {
          return false;
        }
        return isTrusted(src) ||
            trustStore.isOrgSubject(event.scopeId, src);
    }
  }

  bool _acceptCalendarDelete(CalendarEvent existing, String? byId) {
    final by = byId;
    if (by == null) return false;
    if (by == existing.creatorId) return true;
    if (existing.audienceIds.contains(by)) return true;
    switch (existing.scope) {
      case CalendarScope.family:
        return familySafety.isGuardian;
      case CalendarScope.group:
        final g = groups[existing.scopeId];
        return g != null && g.isAdmin(by);
      case CalendarScope.organization:
        // Org root, delegated issuer, or known org member may delete.
        return trustStore.organizations.containsKey(existing.scopeId) &&
            (trustStore.isOrgSubject(existing.scopeId, by) ||
                by == existing.scopeId);
      case CalendarScope.individual:
        return by == existing.scopeId;
    }
  }

  void _onCalendarWire(CalendarWireEvent event, MeshMessage m) {
    switch (event.type) {
      case CalendarWire.upsertType:
        final cal = event.event;
        if (cal == null) return;
        if (!_acceptCalendarEvent(cal, meshSourceId: m.sourceId)) return;
        final prev = calendars[cal.id];
        final isNew = prev == null;
        final isNewer =
            prev == null || !prev.updatedAt.isAfter(cal.updatedAt);
        if (!isNewer) return;
        calendars.put(cal);
        chat.addSystem(
          'Calendar ${isNew ? 'shared' : 'update'}: ${cal.title}'
          ' · ${calendarScopeLabel(cal)}'
          ' (from ${_peerLabel(m.sourceId)})',
        );
      case CalendarWire.deleteType:
        final eid = event.eventId;
        if (eid == null || eid.isEmpty) return;
        final existing = calendars[eid];
        if (existing == null) return;
        final by = event.byId ?? m.sourceId;
        if (!_isTrustedSource(m.sourceId)) return;
        if (!_acceptCalendarDelete(existing, by)) return;
        calendars.remove(eid);
        chat.addSystem(
          'Calendar removed: ${existing.title}'
          ' (by ${_peerLabel(by)})',
        );
      case CalendarWire.syncRequestType:
        final scope = event.requestScope;
        final scopeId = event.requestScopeId;
        final from = event.requestFromId ?? m.sourceId;
        if (scope == null ||
            scopeId == null ||
            scopeId.isEmpty ||
            from == null) {
          return;
        }
        // Only sync calendars with QR/NFC-trusted peers.
        if (!_isTrustedSource(m.sourceId) || !isTrusted(from)) return;
        // Only answer group/org/family requests we are part of.
        if (!_mayShareScopeWith(scope: scope, scopeId: scopeId, peerId: from) &&
            scope != CalendarScope.organization) {
          return;
        }
        if (scope == CalendarScope.organization &&
            !trustStore.organizations.containsKey(scopeId)) {
          return;
        }
        if (scope == CalendarScope.group) {
          final g = groups[scopeId];
          final me = identity?.id;
          if (g == null || me == null || !g.isMember(me) || !g.isMember(from)) {
            return;
          }
        }
        unawaited(
          pushScopeCalendar(scope: scope, scopeId: scopeId, peerId: from),
        );
      default:
        return;
    }
    notifyListeners();
  }

  void _onFamilySafetyEvent(FamilySafetyEvent event, MeshMessage m) {
    switch (event.type) {
      case FamilySafetyWire.linkType:
        final guardianId = event.body['guardianId'] as String? ?? m.sourceId;
        if (guardianId == null || guardianId.isEmpty) return;
        // Only accept policy from a QR/NFC-trusted contact (never radio-only).
        final src = m.sourceId;
        if (!_isTrustedSource(src)) {
          chat.addSystem(
            'Ignored family safety link from untrusted peer '
            '${_peerLabel(src)} — exchange keys via QR/NFC first',
          );
          return;
        }
        if (src != guardianId && !isTrustedContact(guardianId)) {
          chat.addSystem(
            'Ignored family safety link: guardian is not QR/NFC-trusted',
          );
          return;
        }
        final mode = SafetyMode.parse(event.body['mode'] as String?);
        final grounded = event.body['grounded'] == true;
        final ids = <String>[];
        final raw = event.body['sharedWithIds'];
        if (raw is List) ids.addAll(raw.map((e) => '$e'));
        final parentIds = <String>[];
        final rawParents = event.body['parentIds'];
        if (rawParents is List) {
          parentIds.addAll(rawParents.map((e) => '$e'));
        }
        if (parentIds.isEmpty) parentIds.add(guardianId);
        final parentNames = <String, String>{};
        final rawNames = event.body['parentNames'];
        if (rawNames is Map) {
          rawNames.forEach((k, v) => parentNames['$k'] = '$v');
        }
        final gName = event.body['guardianName'] as String? ??
            _peerLabel(guardianId);
        parentNames.putIfAbsent(guardianId, () => gName);
        final wasGrounded = familySafety.myPolicy?.grounded == true;
        familySafety.setMyPolicy(
          MySafetyPolicy(
            guardianId: guardianId,
            guardianName: gName,
            parentIds: parentIds,
            parentNames: parentNames,
            mode: mode,
            grounded: grounded,
            sharedWithIds: ids,
            updatedAt: DateTime.now().toUtc(),
          ),
        );
        final pol = familySafety.myPolicy!;
        if (grounded && !wasGrounded) {
          chat.addSystem(
            'Grounded by ${pol.guardianName}'
            ' — chat and walkie are paused'
            ' (family: ${pol.parentsLabel})',
          );
          status = 'Grounded';
        } else if (!grounded && wasGrounded) {
          chat.addSystem(
            'Ungrounded — messaging restored (${mode.shortLabel})',
          );
          status = mode.label;
        } else {
          chat.addSystem(
            'Family safety on: ${pol.privilegeLabel}'
            ' · parents: ${pol.parentsLabel}',
          );
          status = grounded ? 'Grounded' : mode.label;
        }
      case FamilySafetyWire.statusType:
        // Co-parent privilege sync — Mom/Dad stay on the same page.
        if (!_isTrustedSource(m.sourceId)) return;
        final wardRaw = event.body['ward'];
        if (wardRaw is! Map) return;
        final remote = WardProfile.fromJson(Map<String, Object?>.from(wardRaw));
        // If we were removed as a parent, drop the ward.
        final me = identity?.id;
        if (me != null &&
            remote.parentIds.isNotEmpty &&
            !remote.parentIds.contains(me) &&
            familySafety.wards.containsKey(remote.wardId)) {
          familySafety.removeWard(remote.wardId);
          familySafety.clearPendingForWard(remote.wardId);
          chat.addSystem(
            'No longer co-parent for ${remote.displayName}',
          );
          break;
        }
        // Only accept if we are listed as a parent (or first intro with empty check).
        if (me != null &&
            remote.parentIds.isNotEmpty &&
            !remote.parentIds.contains(me) &&
            !familySafety.wards.containsKey(remote.wardId)) {
          return;
        }
        final changed = familySafety.applyRemoteWardStatus(remote);
        if (!changed) return;
        if (remote.grounded) {
          familySafety.clearPendingForWard(remote.wardId);
        }
        final by = event.body['updatedByName'] as String? ??
            remote.statusByName ??
            _peerLabel(event.body['updatedById'] as String? ?? m.sourceId);
        chat.addSystem(
          'Family status: ${remote.displayName} → ${remote.privilegeLabel}'
          ' (updated by $by)',
        );
        status = '${remote.displayName}: ${remote.privilegeLabel}';
      case FamilySafetyWire.settleType:
        if (!_isTrustedSource(m.sourceId)) return;
        final requestId = event.body['requestId'] as String?;
        if (requestId == null || requestId.isEmpty) return;
        final had = familySafety.pendingApprovals
            .any((p) => p.requestId == requestId);
        familySafety.removePending(requestId);
        if (!had) return;
        final approved = event.body['approved'] == true;
        final byName = event.body['byName'] as String? ??
            _peerLabel(event.body['byId'] as String?);
        final fromName = event.body['fromName'] as String? ?? 'child';
        final toLabel = event.body['toLabel'] as String? ?? '';
        chat.addSystem(
          approved
              ? '$byName approved $fromName'
                  '${toLabel.isEmpty ? '' : ' → $toLabel'}'
              : '$byName declined $fromName'
                  '${toLabel.isEmpty ? '' : ' → $toLabel'}',
        );
      case FamilySafetyWire.copyType:
        if (!_isTrustedSource(m.sourceId)) return;
        final fromId = event.body['fromId'] as String? ?? m.sourceId ?? '';
        // Prefer mesh source as author when payload is spoofable.
        if (m.sourceId != null &&
            fromId.isNotEmpty &&
            m.sourceId != fromId &&
            !isTrustedContact(fromId)) {
          return;
        }
        final fromName = event.body['fromName'] as String? ?? _peerLabel(fromId);
        final toLabel = event.body['toLabel'] as String? ?? '';
        final text = event.body['text'] as String? ?? '';
        final copyId =
            'copy-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
        familySafety.addCopy(
          SafetyCopy(
            id: copyId,
            fromId: fromId,
            fromName: fromName,
            toLabel: toLabel,
            text: text,
            at: DateTime.now().toUtc(),
          ),
        );
        chat.addSystem('Seen: $fromName → $toLabel: “$text”');
      case FamilySafetyWire.mediateReqType:
        if (!_isTrustedSource(m.sourceId)) return;
        final pending = PendingMediatedMessage.fromJson(event.body);
        // Only accept mediation for wards we supervise in kid mode (not grounded).
        // Kid must be QR/NFC-trusted (enrolled via setupWard).
        final ward = familySafety.wards[pending.fromId];
        if (ward == null ||
            ward.mode != SafetyMode.child ||
            ward.grounded ||
            !isTrustedContact(pending.fromId)) {
          return;
        }
        if (m.sourceId != null && m.sourceId != pending.fromId) return;
        familySafety.addPending(pending);
        chat.addSystem(
          'Needs OK: ${pending.fromName} → ${pending.toLabel}: “${pending.text}”'
          ' (either parent can approve)',
        );
        status = 'Approve message from ${pending.fromName}?';
      case FamilySafetyWire.discussNoteType:
        if (!_isTrustedSource(m.sourceId)) return;
        final raw = event.body['note'];
        if (raw is! Map) return;
        final note = DiscussNote.fromJson(Map<String, Object?>.from(raw));
        final me = identity?.id;
        if (me == null) return;
        // Author must match trusted mesh source and be a known ward (or self).
        if (m.sourceId != note.fromId) return;
        if (!isTrustedContact(note.fromId) && note.fromId != me) return;
        final isParentOf = familySafety.wards.containsKey(note.fromId);
        final isSelf = note.fromId == me;
        if (!isParentOf && !isSelf) return;
        if (note.discretion == NoteDiscretion.private && !isSelf) {
          final ward = familySafety.wards[note.fromId];
          if (ward == null) return;
        }
        familySafety.putDiscussNote(note);
        chat.addSystem(
          'Discuss first (${note.discretion.shortLabel}): '
          '${note.fromName} — “${note.text}”',
        );
        status = 'Discuss note from ${note.fromName}';
      case FamilySafetyWire.discussAckType:
        if (!_isTrustedSource(m.sourceId)) return;
        final noteId = event.body['noteId'] as String?;
        if (noteId == null) return;
        final existing = familySafety.discussNote(noteId);
        if (existing == null) return;
        final st = DiscussNoteStatus.parse(event.body['status'] as String?);
        final byId = event.body['byId'] as String? ?? m.sourceId;
        final byName = event.body['byName'] as String? ?? _peerLabel(byId);
        final at = event.body['at'] is String
            ? DateTime.parse(event.body['at']! as String)
            : DateTime.now().toUtc();
        familySafety.putDiscussNote(
          existing.copyWith(
            status: st,
            acknowledgedAt: at,
            acknowledgedById: byId,
            acknowledgedByName: byName,
          ),
        );
        chat.addSystem(
          st == DiscussNoteStatus.closed
              ? '$byName marked your discuss note as discussed'
              : '$byName saw your discuss note',
        );
      case FamilySafetyWire.mediateDecisionType:
        if (!_isTrustedSource(m.sourceId)) return;
        final approved = event.body['approved'] == true;
        final text = event.body['text'] as String? ?? '';
        final requestId = event.body['requestId'] as String? ?? '';
        final toPeerId = event.body['toPeerId'] as String?;
        final toGroupId = event.body['toGroupId'] as String?;
        final toLabel = toGroupId != null
            ? (groups[toGroupId]?.name ?? 'group')
            : (toPeerId == null || toPeerId.isEmpty
                ? 'Everyone'
                : _peerLabel(toPeerId));
        final pendingImg = requestId.isEmpty
            ? null
            : _pendingOutboundImages.remove(requestId);
        if (approved && (text.isNotEmpty || pendingImg != null)) {
          if (familySafety.iAmGrounded) {
            chat.addSystem(
              'Parent approved, but you are grounded — not sending',
            );
          } else if (pendingImg != null) {
            chat.addSystem('Parent approved photo — sending to $toLabel');
            unawaited(
              _deliverChatImage(
                bytes: pendingImg.bytes,
                fileName: pendingImg.name,
                mimeType: pendingImg.mime,
                caption: pendingImg.caption ?? '',
                toPeerId: toPeerId,
                toGroupId: toGroupId,
                useSelection: false,
              ).then((_) {
                final pol = familySafety.myPolicy;
                if (pol != null) {
                  return _sendFamilyCopies(
                    text: text.isEmpty ? '📷 ${pendingImg.name}' : text,
                    toPeerId: toPeerId,
                    toGroupId: toGroupId,
                    useSelection: false,
                  );
                }
              }),
            );
          } else {
            chat.addSystem('Parent approved — sending to $toLabel');
            unawaited(
              _deliverChat(
                text,
                toPeerId: toPeerId,
                toGroupId: toGroupId,
                useSelection: false,
              ).then((_) {
                // After release, also copy to parents + teachers.
                final pol = familySafety.myPolicy;
                if (pol != null) {
                  return _sendFamilyCopies(
                    text: text,
                    toPeerId: toPeerId,
                    toGroupId: toGroupId,
                    useSelection: false,
                  );
                }
              }),
            );
          }
        } else {
          chat.addSystem(
            text.isEmpty
                ? 'Parent declined your message'
                : 'Parent declined message to $toLabel: “$text”',
          );
        }
      default:
        return;
    }
    notifyListeners();
  }

  /// Toggle an RCS-style reaction on a chat line and gossip it on the mesh.
  Future<void> reactToMessage(String messageId, String emoji) async {
    final id = identity;
    final n = node;
    if (id == null) return;
    final line = chat.findById(messageId);
    if (line == null || line.isSystem) return;

    chat.toggleReaction(
      messageId: messageId,
      emoji: emoji,
      reactorId: id.id,
    );
    notifyListeners();

    if (n == null) return;
    final payload = ChatReactionWire.encode(
      messageId: messageId,
      emoji: emoji,
      reactorId: id.id,
      groupId: line.groupId,
      threadPeerId: line.isLocal ? line.peerId : line.peerId,
    );

    // Route reaction to the conversation participants.
    if (line.groupId != null) {
      final group = groups[line.groupId!];
      if (group == null) return;
      for (final mid in group.memberIds) {
        if (mid == id.id || blockList.isBlocked(mid)) continue;
        await n.send(
          MeshMessage(
            id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
            sourceId: id.id,
            destinationId: mid,
            kind: MessageKind.control,
            payload: payload,
            timestamp: DateTime.now().toUtc(),
          ),
        );
      }
      return;
    }

    if (line.isBroadcast) {
      await n.send(
        MeshMessage(
          id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
          sourceId: id.id,
          destinationId: null,
          kind: MessageKind.control,
          payload: payload,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      return;
    }

    // 1:1 — send to the other party.
    final other = line.isLocal ? line.peerId : line.peerId;
    // For remote lines in a DM thread, peerId is the sender; for local, peerId
    // is the destination. selectedPeerId is a good fallback.
    final dest = other ?? selectedPeerId;
    if (dest == null || blockList.isBlocked(dest)) return;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: dest,
        kind: MessageKind.control,
        payload: payload,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  void _onChatMessage(MeshMessage m) {
    // Group messages: only accept if we are still a member.
    try {
      final raw = utf8.decode(m.payload);
      final g = GroupChatWire.tryParse(raw);
      if (g != null) {
        final group = groups[g.groupId];
        if (group == null || !group.isMember(identity?.id ?? '')) {
          return;
        }
      }
    } catch (_) {}
    final name = m.sourceId == null
        ? null
        : (peers[m.sourceId!]?.displayName.isNotEmpty == true
            ? peers[m.sourceId!]!.displayName
            : null);
    chat.addRemoteChat(m, senderName: name);
    notifyListeners();
  }

  /// Refresh local QR / short-code credential (e.g. after rename).
  Future<PublicCredential?> refreshLocalCredential() async {
    final id = identity;
    if (id == null) return null;
    localCredential = await PublicCredential.fromIdentity(id);
    notifyListeners();
    return localCredential;
  }

  /// Import + trust a public credential **only** via QR or NFC key material.
  ///
  /// Mesh short codes and proximity advertisements do **not** establish trust.
  /// Pass the full `zvcomm:cred:…` payload (from QR) or the NFC-delivered payload
  /// with [channel] set accordingly.
  Future<PublicCredential?> importCredential(
    String raw, {
    TrustChannel channel = TrustChannel.qr,
  }) async {
    final text = raw.trim();
    if (text.isEmpty) return null;

    PublicCredential cred;
    try {
      // Full public key payload only (QR URI / JSON / base64url JSON).
      cred = PublicCredential.parse(text);
    } on FormatException {
      // Already trusted? short code is a convenience lookup only.
      for (final c in trustedCredentials.values) {
        if (ShortCode.matches(text, c.subjectId)) {
          return c;
        }
      }
      if (offerCache.byShortCode(text) != null) {
        throw const FormatException(
          'Mesh short codes do not grant trust. Scan their QR code or use NFC '
          'to exchange public keys (Credentials).',
        );
      }
      throw const FormatException(
        'Need a full public key via QR (zvcomm:cred:…) or NFC — '
        'not a short code or mesh advertisement alone',
      );
    }

    if (!await cred.verify()) {
      throw StateError('credential signature invalid');
    }
    if (identity != null && cred.subjectId == identity!.id) {
      throw StateError('cannot import own credential');
    }

    trustedCredentials[cred.subjectId] = cred;
    trustStore.trustDirect(cred);
    // Do not put mesh offer cache → that path is proximity; local trust only.
    chat.addSystem(
      'Trusted via ${channel.name.toUpperCase()}: '
      '${cred.displayName.isEmpty ? cred.subjectId : cred.displayName}'
      ' · ${cred.shortCode}',
    );
    status = 'Trusted ${cred.shortCode} (${channel.name})';
    notifyListeners();
    return cred;
  }

  /// Create a new hosted organization CA (generate certs + share as org root).
  Future<Organization> createOrganization({
    required String name,
    OrganizationCategory category = OrganizationCategory.other,
    String? description,
  }) async {
    final ca = await LocalCa.generate(displayName: name);
    final org = Organization.fromCaRoot(
      ca.root,
      category: category,
      description: description,
    );
    hostedOrgCas[org.id] = ca;
    trustStore.trustOrganization(org);
    orgOfferCache.put(org);
    sharingOrganization = org;
    // Seed mesh with any existing org calendar + pull from nearby peers.
    unawaited(resyncOrganizationCalendars(org.id));
    chat.addSystem(
      'Created organization ${org.name} (${org.category.label}) · ${org.shortCode}',
    );
    status = 'Org ${org.name} created';
    notifyListeners();
    return org;
  }

  /// Whether this device can issue member certs for [orgId] (root or delegated).
  bool canIssueForOrg(String orgId) => hostedOrgCas.containsKey(orgId);

  /// Whether [orgId] is a root CA we generated (vs delegated issuer).
  bool isRootHostForOrg(String orgId) {
    final ca = hostedOrgCas[orgId];
    if (ca == null) return false;
    return ca.root.id == orgId && !issuerAuthorities.containsKey(orgId);
  }

  /// Issue a member [MeshCertificate] for an external under a hosted org
  /// (root CA or delegated issuer).
  Future<MeshCertificate> issueOrganizationMemberCert({
    required String orgId,
    required PublicCredential member,
    Duration? ttl,
  }) async {
    final pack = await issueOrganizationMemberPackage(
      orgId: orgId,
      member: member,
      ttl: ttl,
    );
    return pack.certificate;
  }

  /// Issue member cert and return a shareable package (includes issuer chain
  /// when this device is a delegated issuer).
  Future<OrgMemberPackage> issueOrganizationMemberPackage({
    required String orgId,
    required PublicCredential member,
    Duration? ttl,
  }) async {
    final ca = hostedOrgCas[orgId];
    if (ca == null) {
      throw StateError(
        'not an issuer for org $orgId — become an issuer or generate a root CA',
      );
    }
    final org = trustStore.organizations[orgId];
    final subject = DeviceIdentity(
      id: member.subjectId,
      displayName: member.displayName,
      x25519PublicKey: member.x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: member.ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    final cert = await ca.issueFor(
      subject,
      ttl: ttl,
      capabilities: orgMemberCapabilities,
    );
    final pack = OrgMemberPackage(
      certificate: cert,
      issuerAuthority: issuerAuthorities[orgId],
      organization: org,
    );
    chat.addSystem(
      'Issued org cert for ${member.displayName.isEmpty ? member.subjectId : member.displayName}'
      ' (serial ${cert.serial})'
      '${issuerAuthorities.containsKey(orgId) ? " as delegated issuer" : ""}',
    );
    notifyListeners();
    return pack;
  }

  /// Root CA only: grant [member] the right to issue member certs for this org.
  Future<IssuerAuthority> issueIssuerAuthority({
    required String orgId,
    required PublicCredential member,
    Duration? ttl,
  }) async {
    if (!isRootHostForOrg(orgId)) {
      throw StateError(
        'only the org root CA host can grant issuer authority',
      );
    }
    final ca = hostedOrgCas[orgId]!;
    final org = trustStore.organizations[orgId];
    if (org == null) {
      throw StateError('org $orgId not in trust store');
    }
    final subject = DeviceIdentity(
      id: member.subjectId,
      displayName: member.displayName,
      x25519PublicKey: member.x25519PublicKey,
      x25519PrivateKey: Uint8List(32),
      ed25519PublicKey: member.ed25519PublicKey,
      ed25519PrivateKey: Uint8List(32),
    );
    final cert = await ca.issueIssuerFor(subject, ttl: ttl);
    // Peers need to know this issuer is authorized when they verify.
    trustStore.authorizedIssuers[cert.subjectId] = cert;
    trustStore.issuerOrgBySubject[cert.subjectId] = orgId;
    final grant = IssuerAuthority(organization: org, certificate: cert);
    chat.addSystem(
      'Granted issuer authority to '
      '${member.displayName.isEmpty ? member.subjectId : member.displayName}'
      ' for ${org.name}',
    );
    status = 'Issuer grant · ${grant.shortCode}';
    notifyListeners();
    return grant;
  }

  /// Accept an issuer authority grant and start issuing for that org.
  ///
  /// The grant's subject must match this device's identity. Private keys never
  /// leave the device — only the signed authority cert is imported.
  Future<Organization> becomeOrgIssuer(String raw) async {
    final id = identity;
    if (id == null) throw StateError('no local identity');
    final grant = IssuerAuthority.parse(raw);
    if (!await grant.verify()) {
      throw const FormatException(
        'issuer authority invalid (signature, expiry, or missing org_issue)',
      );
    }
    if (grant.certificate.subjectId != id.id) {
      throw FormatException(
        'issuer grant is for ${grant.certificate.subjectId}, not this device '
        '(${id.id}) — share your credential with the org admin first',
      );
    }
    // Keys must match our public identity.
    if (!_bytesEq(grant.certificate.publicKey, id.ed25519PublicKey)) {
      throw const FormatException(
        'issuer grant public key does not match this device',
      );
    }

    final org = grant.organization;
    trustStore.trustOrganization(org);
    final decision = await trustStore.trustIssuerAuthority(grant.certificate);
    if (!decision.isTrusted) {
      throw FormatException(decision.detail ?? 'issuer authority rejected');
    }

    // Issue with our device identity as the signing CA (delegated).
    hostedOrgCas[org.id] = LocalCa(root: id);
    issuerAuthorities[org.id] = grant.certificate;
    orgOfferCache.put(org);
    sharingOrganization = org;
    chat.addSystem(
      'Became issuer for ${org.name} · ${org.category.label} · ${org.shortCode}',
    );
    status = 'Issuer for ${org.name}';
    notifyListeners();
    return org;
  }

  static bool _bytesEq(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a[i] ^ b[i];
    }
    return d == 0;
  }

  /// Select an org for QR / short-code / NFC sharing.
  void selectSharingOrganization(Organization? org) {
    sharingOrganization = org;
    if (org != null) orgOfferCache.put(org);
    notifyListeners();
  }

  /// Trust an organization CA so its issued certificates are accepted as externals.
  ///
  /// Accepts full `zvcomm:org:v1:…` / JSON, CA `zvcomm:cred:…`, or a short code
  /// that matches a recent mesh/NFC org offer.
  /// Trust an organization CA from full QR/NFC public key material only.
  ///
  /// Mesh org advertisements / short codes alone do not establish trust.
  Future<Organization> trustOrganization(
    String raw, {
    OrganizationCategory? category,
    TrustChannel channel = TrustChannel.qr,
  }) async {
    final text = raw.trim();
    Organization org;
    try {
      org = Organization.parse(text);
    } on FormatException {
      for (final o in trustStore.organizationList) {
        if (ShortCode.matches(text, o.id)) {
          return o; // already trusted
        }
      }
      if (orgOfferCache.byShortCode(text) != null) {
        throw const FormatException(
          'Mesh org short codes do not grant trust. Scan the organization QR '
          'or receive the org public key via NFC.',
        );
      }
      throw const FormatException(
        'Need full organization public key via QR (zvcomm:org:…) or NFC',
      );
    }
    if (category != null && org.category != category) {
      org = org.copyWith(category: category);
    }
    trustStore.trustOrganization(org);
    unawaited(resyncOrganizationCalendars(org.id));
    chat.addSystem(
      'Trusted organization via ${channel.name.toUpperCase()}: '
      '${org.name} · ${org.category.label} · ${org.shortCode}'
      '${org.description != null ? " — ${org.description}" : ""}',
    );
    status = 'Org ${org.name} trusted (${channel.name})';
    notifyListeners();
    return org;
  }

  /// Broadcast organization trust anchor so peers can import via short code.
  Future<void> publishOrganizationOffer(Organization org, {String? to}) async {
    final n = node;
    final id = identity;
    if (n == null || id == null) return;
    orgOfferCache.put(org);
    sharingOrganization = org;
    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: to,
        kind: MessageKind.control,
        payload: OrganizationWire.encodeOffer(org),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    chat.addSystem(
      'Published org offer ${org.name} · ${org.shortCode}'
      '${to == null ? " (broadcast)" : " → $to"}',
    );
    status = 'Org offer ${org.shortCode} published';
    notifyListeners();
  }

  /// NFC write of organization trust payload on next tap.
  Future<void> shareOrganizationViaNfc(Organization org) async {
    final nfc = nfcTransport;
    if (nfc == null) {
      throw StateError(
        'NFC not available — enable the NFC plugin and use a phone with NFC',
      );
    }
    if (!await nfc.isAvailable()) {
      throw StateError('NFC is disabled or not present on this device');
    }
    final id = identity;
    if (id == null) throw StateError('no local identity');
    orgOfferCache.put(org);
    sharingOrganization = org;
    await nfc.shareUriOnNextTap(
      org.toQrPayload(),
      localId: id.id,
      displayName: id.displayName,
    );
    nfcCredentialArmed = true;
    status = 'NFC org share armed · ${org.shortCode}';
    chat.addSystem(
      'NFC org share ready — hold phones together for ${org.name}',
    );
    notifyListeners();
  }

  void setOrganizationCategory(String orgId, OrganizationCategory category) {
    final existing = trustStore.organizations[orgId];
    if (existing == null) return;
    trustStore.updateOrganization(existing.copyWith(category: category));
    chat.addSystem('${existing.name} → ${category.label}');
    notifyListeners();
  }

  void untrustOrganization(String orgId) {
    final org = trustStore.organizations[orgId];
    trustStore.untrustOrganization(orgId);
    hostedOrgCas.remove(orgId);
    issuerAuthorities.remove(orgId);
    if (sharingOrganization?.id == orgId) {
      sharingOrganization = null;
    }
    final cleared = calendars.removeScope(CalendarScope.organization, orgId);
    if (org != null) {
      chat.addSystem(
        'Removed organization trust: ${org.name}'
        '${cleared > 0 ? " · $cleared calendar event(s) cleared" : ""}',
      );
    }
    notifyListeners();
  }

  /// Import an org-issued member cert (bare JSON or [OrgMemberPackage]).
  Future<TrustDecision> trustExternalCertificateJson(String raw) async {
    final text = raw.trim();
    if (!text.startsWith('{')) {
      throw const FormatException('certificate JSON required');
    }
    final pack = OrgMemberPackage.parse(text);
    if (pack.organization != null) {
      trustStore.trustOrganization(pack.organization!);
    }
    final decision = await trustStore.trustExternalCertificate(
      pack.certificate,
      issuerAuthority: pack.issuerAuthority,
    );
    if (decision.isTrusted) {
      final orgId = decision.organizationId ??
          trustStore.externalOrgBySubject[pack.certificate.subjectId];
      if (orgId != null && trustStore.organizations.containsKey(orgId)) {
        // Share org calendar with the newly trusted org member.
        unawaited(
          pushScopeCalendar(
            scope: CalendarScope.organization,
            scopeId: orgId,
            peerId: pack.certificate.subjectId,
          ),
        );
        unawaited(
          requestScopeCalendar(
            scope: CalendarScope.organization,
            scopeId: orgId,
            peerId: pack.certificate.subjectId,
          ),
        );
      }
      chat.addSystem(
        'Trusted external ${pack.certificate.subjectId} via org '
        '${decision.organizationName ?? pack.certificate.issuerId}'
        ' · org calendar shared',
      );
      status =
          'External ${pack.certificate.subjectId.substring(0, 8)}… trusted';
    } else {
      status = decision.detail ?? 'External cert rejected';
    }
    notifyListeners();
    return decision;
  }

  /// Import issuer authority only (register a peer as delegated issuer).
  Future<TrustDecision> trustIssuerAuthorityJson(String raw) async {
    final grant = IssuerAuthority.parse(raw);
    trustStore.trustOrganization(grant.organization);
    final decision = await trustStore.trustIssuerAuthority(grant.certificate);
    if (decision.isTrusted) {
      chat.addSystem(
        'Registered delegated issuer ${grant.certificate.subjectId} for '
        '${grant.organization.name}',
      );
    }
    notifyListeners();
    return decision;
  }

  /// Whether [subjectId] is trusted via QR/NFC public-key exchange (or org cert).
  ///
  /// Radio presence alone never returns true.
  bool isTrusted(String subjectId) {
    if (subjectId.isEmpty) return false;
    if (trustedCredentials.containsKey(subjectId)) return true;
    if (trustStore.directPeers.containsKey(subjectId)) return true;
    if (trustStore.organizations.containsKey(subjectId)) return true;
    if (trustStore.externalCerts.containsKey(subjectId)) return true;
    if (trustStore.authorizedIssuers.containsKey(subjectId)) return true;
    return false;
  }

  /// True when [id] is a QR/NFC-trusted contact (direct credential).
  bool isTrustedContact(String? id) {
    if (id == null || id.isEmpty) return false;
    return trustedCredentials.containsKey(id) ||
        trustStore.directPeers.containsKey(id);
  }

  /// Peers that are both visible on the mesh **and** QR/NFC-trusted.
  List<Peer> get trustedVisiblePeers {
    return visiblePeers.where((p) => isTrustedContact(p.id)).toList();
  }

  /// Require [peerId] to be QR/NFC trusted; throws otherwise.
  void requireTrustedContact(String peerId, {String action = 'this action'}) {
    if (!isTrustedContact(peerId)) {
      throw StateError(
        'Trust required for $action. Exchange public keys via QR or NFC first '
        '(Credentials). Radio proximity alone is not enough.',
      );
    }
  }

  bool _isTrustedSource(String? sourceId) {
    if (sourceId == null || sourceId.isEmpty) return false;
    return isTrusted(sourceId);
  }

  Future<TrustDecision> evaluateTrust(String subjectId) =>
      trustStore.evaluate(subjectId: subjectId);

  /// Broadcast local public credential so peers can import via short code.
  Future<void> publishCredentialOffer({String? to}) async {
    final n = node;
    final id = identity;
    var cred = localCredential;
    if (n == null || id == null) return;
    cred ??= await PublicCredential.fromIdentity(id);
    localCredential = cred;

    await n.send(
      MeshMessage(
        id: DateTime.now().microsecondsSinceEpoch.toRadixString(16),
        sourceId: id.id,
        destinationId: to,
        kind: MessageKind.control,
        payload: CredentialWire.encodeOffer(cred),
        timestamp: DateTime.now().toUtc(),
      ),
    );
    chat.addSystem(
      'Published credential offer ${cred.shortCode}'
      '${to == null ? " (broadcast)" : " → $to"}',
    );
    status = 'Offer ${cred.shortCode} published';
    notifyListeners();
  }

  Future<void> _onControlMessage(MeshMessage m) async {
    // Typing indicators.
    final typingEv = ChatTypingWire.tryDecode(m.payload);
    if (typingEv != null) {
      if (blockList.isBlocked(typingEv.peerId)) return;
      if (identity != null && typingEv.peerId == identity!.id) return;
      final name = typingEv.displayName?.isNotEmpty == true
          ? typingEv.displayName
          : peers[typingEv.peerId]?.displayName;

      // Map to ChatLog thread keys: g:…, peer id, or *.
      final String threadKey;
      if (typingEv.groupId != null && typingEv.groupId!.isNotEmpty) {
        threadKey = TypingPresence.threadKey(groupId: typingEv.groupId);
      } else if (typingEv.threadPeerId == null ||
          typingEv.threadPeerId!.isEmpty) {
        threadKey = ChatLog.broadcastKey;
      } else if (typingEv.threadPeerId == identity?.id) {
        // DM: they address us → store under their id.
        threadKey = TypingPresence.threadKey(peerId: typingEv.peerId);
      } else {
        // DM: threadPeerId is the other party (from our perspective if echoed).
        threadKey = TypingPresence.threadKey(peerId: typingEv.threadPeerId);
      }

      typing.setTyping(
        threadKey: threadKey,
        peerId: typingEv.peerId,
        typing: typingEv.typing,
        displayName: name,
      );
      notifyListeners();
      return;
    }

    // Chat reactions (RCS-style).
    final reaction = ChatReactionWire.tryDecode(m.payload);
    if (reaction != null) {
      if (blockList.isBlocked(reaction.reactorId)) return;
      chat.toggleReaction(
        messageId: reaction.messageId,
        emoji: reaction.emoji,
        reactorId: reaction.reactorId,
      );
      notifyListeners();
      return;
    }

    // Group membership control.
    final groupEvent = GroupWire.tryDecode(m.payload);
    if (groupEvent != null) {
      _onGroupWire(groupEvent, m);
      return;
    }

    // Incoming moderation reports (we act as a local inbox).
    final report = ReportWire.tryDecode(m.payload);
    if (report != null) {
      reports.add(report.copyWith(status: ReportStatus.submitted));
      chat.addSystem(
        'Report received about ${_peerLabel(report.subjectId)}'
        ' · ${report.category.label} from ${_peerLabel(report.reporterId)}',
      );
      notifyListeners();
      return;
    }

    // Family safety (teen copies, kid mediation, parent link).
    final family = FamilySafetyWire.tryDecode(m.payload);
    if (family != null) {
      _onFamilySafetyEvent(family, m);
      return;
    }

    // Calendars (personal / family / group / org).
    final cal = CalendarWire.tryDecode(m.payload);
    if (cal != null) {
      _onCalendarWire(cal, m);
      return;
    }

    final org = OrganizationWire.tryDecodeOffer(m.payload);
    if (org != null) {
      // Cache for display only — mesh ads never establish trust.
      orgOfferCache.put(org);
      chat.addSystem(
        'Nearby org advertisement: ${org.name} (${org.category.label})'
        ' · not trusted until QR/NFC public key exchange',
      );
      notifyListeners();
      return;
    }

    final cred = CredentialWire.tryDecodeOffer(m.payload);
    if (cred == null) return;
    try {
      if (!await cred.verify()) return;
      if (identity != null && cred.subjectId == identity!.id) return;
      // Cache for display only — radio proximity is not trust.
      offerCache.put(cred);
      chat.addSystem(
        'Nearby key advertisement: '
        '${cred.displayName.isEmpty ? cred.subjectId : cred.displayName}'
        ' · not trusted until QR/NFC exchange',
      );
      notifyListeners();
    } catch (_) {
      // Ignore malformed control frames.
    }
  }

  void _onGroupWire(GroupWireEvent event, MeshMessage m) {
    final me = identity?.id;
    switch (event.type) {
      case GroupWire.inviteType:
      case GroupWire.updateType:
        final g = event.group;
        if (g == null) return;
        // Group control only from QR/NFC-trusted peers (not radio proximity).
        if (!_isTrustedSource(m.sourceId)) {
          chat.addSystem(
            'Ignored group update from untrusted ${_peerLabel(m.sourceId)} '
            '— exchange keys via QR/NFC first',
          );
          return;
        }
        // Only accept if we are listed as a member (or already know the group).
        if (me != null && !g.isMember(me) && !groups.contains(g.id)) {
          return;
        }
        final existing = groups[g.id];
        final wasMember =
            me != null && existing != null && existing.isMember(me);
        groups.put(g);
        final nowMember = me != null && g.isMember(me);
        if (existing == null && event.type == GroupWire.inviteType) {
          chat.addSystem(
            'Joined group “${g.name}”'
            '${event.note != null ? " — ${event.note}" : ""}'
            ' (from ${_peerLabel(m.sourceId)})',
            groupId: g.id,
          );
        } else {
          chat.addSystem('Group “${g.name}” updated', groupId: g.id);
        }
        // Pull group calendar when we join; push ours when membership grows.
        if (nowMember) {
          final from = m.sourceId;
          if (from != null && (!wasMember || event.type == GroupWire.inviteType)) {
            unawaited(
              requestScopeCalendar(
                scope: CalendarScope.group,
                scopeId: g.id,
                peerId: from,
              ),
            );
            unawaited(
              pushScopeCalendar(
                scope: CalendarScope.group,
                scopeId: g.id,
                peerId: from,
              ),
            );
          }
          // Share calendar with any newly listed members.
          if (existing != null) {
            for (final mid in g.memberIds) {
              if (mid == me || existing.isMember(mid)) continue;
              unawaited(
                pushScopeCalendar(
                  scope: CalendarScope.group,
                  scopeId: g.id,
                  peerId: mid,
                ),
              );
            }
          }
        }
      case GroupWire.leaveType:
        if (!_isTrustedSource(m.sourceId)) return;
        final gid = event.groupId;
        final mid = event.memberId;
        if (gid == null || mid == null) return;
        if (me != null && mid == me) {
          groups.remove(gid);
          if (selectedGroupId == gid) selectedGroupId = null;
          final n = calendars.removeScope(CalendarScope.group, gid);
          chat.addSystem(
            'You were removed from a group'
            '${n > 0 ? " · $n calendar event(s) cleared" : ""}',
          );
        } else {
          groups.removeMember(gid, mid);
          chat.addSystem(
            '${_peerLabel(mid)} left the group',
            groupId: gid,
          );
        }
      case GroupWire.kickType:
        if (!_isTrustedSource(m.sourceId)) return;
        final gid = event.groupId;
        final mid = event.memberId;
        if (gid == null || mid == null) return;
        if (me != null && mid == me) {
          final name = groups[gid]?.name ?? gid;
          groups.remove(gid);
          if (selectedGroupId == gid) selectedGroupId = null;
          final n = calendars.removeScope(CalendarScope.group, gid);
          chat.addSystem(
            'You were removed from “$name”'
            '${n > 0 ? " · $n calendar event(s) cleared" : ""}',
          );
        } else {
          groups.removeMember(gid, mid);
          chat.addSystem(
            '${_peerLabel(mid)} was removed by ${_peerLabel(event.byId)}',
            groupId: gid,
          );
        }
    }
    notifyListeners();
  }

  /// Active [NfcTransport] if the NFC plugin is enabled, else null.
  NfcTransport? get nfcTransport {
    final t = pluginTransports[nfcPluginId];
    return t is NfcTransport ? t : null;
  }

  bool get nfcAvailable => nfcTransport != null;

  void _listenNfcCredentials() {
    unawaited(_nfcCredSub?.cancel());
    final nfc = nfcTransport;
    if (nfc == null) return;
    _nfcCredSub = nfc.credentialReads.listen((cred) {
      unawaited(_onNfcCredential(cred));
    });
  }

  void _listenNfcUris() {
    unawaited(_nfcUriSub?.cancel());
    final nfc = nfcTransport;
    if (nfc == null) return;
    _nfcUriSub = nfc.uriPayloadReads.listen((uri) {
      unawaited(_onNfcUri(uri));
    });
  }

  Future<void> _onNfcUri(String uri) async {
    final lower = uri.toLowerCase();
    try {
      if (lower.startsWith('zvcomm:org:')) {
        await trustOrganization(uri, channel: TrustChannel.nfc);
        nfcCredentialArmed = nfcTransport?.isCredentialShareArmed ?? false;
        return;
      }
      if (lower.startsWith('zvcomm:issuer:')) {
        await becomeOrgIssuer(uri);
        nfcCredentialArmed = nfcTransport?.isCredentialShareArmed ?? false;
        return;
      }
      if (lower.startsWith('zvcomm:cred:')) {
        await importCredential(uri, channel: TrustChannel.nfc);
        nfcCredentialArmed = nfcTransport?.isCredentialShareArmed ?? false;
      }
    } catch (e) {
      chat.addSystem('NFC import error: $e');
      notifyListeners();
    }
  }

  Future<void> _onNfcCredential(PublicCredential cred) async {
    try {
      // Intentional NFC receive = trusted public-key exchange channel.
      await importCredential(cred.toQrPayload(), channel: TrustChannel.nfc);
      nfcCredentialArmed = nfcTransport?.isCredentialShareArmed ?? false;
      notifyListeners();
    } catch (e) {
      chat.addSystem('NFC credential error: $e');
      notifyListeners();
    }
  }

  /// Write local public credential on the next NFC tap (phone-to-phone / tag).
  Future<void> shareCredentialViaNfc() async {
    final nfc = nfcTransport;
    if (nfc == null) {
      throw StateError(
        'NFC not available — enable the NFC plugin and use a phone with NFC',
      );
    }
    final available = await nfc.isAvailable();
    if (!available) {
      throw StateError('NFC is disabled or not present on this device');
    }
    var cred = localCredential;
    final id = identity;
    if (id == null) throw StateError('no local identity');
    cred ??= await PublicCredential.fromIdentity(id);
    localCredential = cred;
    await nfc.shareCredentialOnNextTap(
      cred,
      localId: id.id,
      displayName: id.displayName,
    );
    nfcCredentialArmed = true;
    status = 'NFC share armed · ${cred.shortCode}';
    chat.addSystem(
      'NFC share ready — hold phones together to write ${cred.shortCode}',
    );
    notifyListeners();
  }

  /// Start NFC session to read a peer credential (import on tap).
  Future<void> receiveCredentialViaNfc() async {
    final nfc = nfcTransport;
    if (nfc == null) {
      throw StateError(
        'NFC not available — enable the NFC plugin and use a phone with NFC',
      );
    }
    final available = await nfc.isAvailable();
    if (!available) {
      throw StateError('NFC is disabled or not present on this device');
    }
    await nfc.receiveCredentialOnNextTap();
    nfcCredentialArmed = true;
    status = 'NFC receive armed';
    chat.addSystem('NFC receive ready — hold near peer phone or tag');
    notifyListeners();
  }

  void cancelNfcCredentialExchange() {
    nfcTransport?.cancelCredentialShare();
    nfcCredentialArmed = false;
    status = 'NFC credential exchange cancelled';
    notifyListeners();
  }

  Future<void> sendDemoFile() async {
    final t = transfers;
    if (t == null) return;
    final payload = Uint8List.fromList(
      utf8.encode(
        'ZVComm demo file\nGenerated ${DateTime.now().toIso8601String()}\n'
        '${List.generate(200, (i) => 'line $i\n').join()}',
      ),
    );
    final info = await t.sendFile(
      fileName: 'demo-${DateTime.now().millisecondsSinceEpoch}.txt',
      bytes: payload,
      to: selectedPeerId,
      mimeType: 'text/plain',
    );
    chat.addSystem(
      'Sent ${info.fileName} (${info.totalBytes} B)'
      '${selectedPeerId != null ? " → $selectedPeerId" : " (broadcast)"}',
    );
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final n = node;
    if (n == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        n.setBackgroundMode(true);
        unawaited(n.transports.setPowerMode(TransportPowerMode.powerSaver));
        if (kDebugMode) {
          status = 'Background power-saver';
          notifyListeners();
        }
      case AppLifecycleState.resumed:
        n.setBackgroundMode(false);
        unawaited(n.transports.setPowerMode(powerMode));
        status = 'Foreground · ${powerMode.name}';
        notifyListeners();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _typingPurgeTimer?.cancel();
    _statsSampleTimer?.cancel();
    _localTypingIdleTimer?.cancel();
    mockTransport?.cancelDiscoverySync();
    demoPeer?.cancelDiscoverySync();
    for (final t in transportManager?.transports ?? const <Transport>[]) {
      if (t is WifiTransport) t.cancelTimersSync();
    }
    unawaited(_peerSub?.cancel());
    unawaited(_msgSub?.cancel());
    unawaited(_presenceSub?.cancel());
    unawaited(_xferSub?.cancel());
    unawaited(_xferDoneSub?.cancel());
    unawaited(_nfcCredSub?.cancel());
    unawaited(_nfcUriSub?.cancel());
    unawaited(_voiceSub?.cancel());
    unawaited(voice?.dispose());
    unawaited(transfers?.dispose());
    unawaited(node?.dispose());
    unawaited(demoPeer?.dispose());
    super.dispose();
  }
}

/// A received walkie clip ready for local playback.
final class WalkieClip {
  final VoiceTransmission transmission;
  final Uint8List pcm;
  final DateTime receivedAt;

  const WalkieClip({
    required this.transmission,
    required this.pcm,
    required this.receivedAt,
  });
}

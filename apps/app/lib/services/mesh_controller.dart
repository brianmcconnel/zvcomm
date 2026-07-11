import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ble/ble.dart';
import 'package:core/core.dart';
import 'package:nfc/nfc.dart';
import 'package:wifi/wifi.dart';

/// App-wide mesh lifecycle, chat log, transfers, plugins, and battery policy.
final class MeshController extends ChangeNotifier with WidgetsBindingObserver {
  DeviceIdentity? identity;
  MeshNode? node;
  FileTransferService? transfers;
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

  /// Transient mesh offers keyed by short code.
  final CredentialOfferCache offerCache = CredentialOfferCache();

  /// Cached local share payload (QR + short code).
  PublicCredential? localCredential;

  StreamSubscription<Peer>? _peerSub;
  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<PresenceInfo>? _presenceSub;
  StreamSubscription<FileTransferProgress>? _xferSub;
  StreamSubscription<({FileTransferInfo info, Uint8List bytes})>? _xferDoneSub;
  StreamSubscription<PublicCredential>? _nfcCredSub;

  bool ready = false;
  bool running = false;

  /// In-process mock radio + demo peer. Off by default; enable in Settings → Developer.
  bool useMockDemo = false;
  TransportPowerMode powerMode = TransportPowerMode.balanced;
  String? status;
  String? selectedPeerId;
  String displayName = 'This device';

  /// True while an NFC credential share/receive session is armed.
  bool nfcCredentialArmed = false;

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

    _peerSub = node!.peerUpdates.listen((p) {
      peers[p.id] = p;
      notifyListeners();
    });
    _msgSub = node!.messages.listen((m) {
      if (m.kind == MessageKind.chat) {
        chat.addRemoteChat(m);
        notifyListeners();
      } else if (m.kind == MessageKind.control) {
        unawaited(_onControlMessage(m));
      }
    });

    // Pre-build shareable credential for QR / short code / NFC.
    localCredential = await PublicCredential.fromIdentity(id);
    _listenNfcCredentials();

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
      chat.addSystem(
        'Received file ${event.info.fileName} (${event.bytes.length} B)'
        '${event.info.sourceId != null ? " from ${event.info.sourceId}" : ""}',
      );
      notifyListeners();
    });

    WidgetsBinding.instance.addObserver(this);
    ready = true;
    await probeAvailability();
    await startDiscovery();
    notifyListeners();
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
        }
      } catch (e) {
        chat.addSystem('Failed to enable ${plugin.name}: $e');
      }
    } else if (existing != null) {
      await mgr.unregister(existing);
      pluginTransports.remove(pluginId);
      if (pluginId == nfcPluginId) {
        unawaited(_nfcCredSub?.cancel());
        _nfcCredSub = null;
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
    selectedPeerId = peerId;
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

  Future<void> sendChat(String text) async {
    final n = node;
    final id = identity;
    if (n == null || id == null || text.trim().isEmpty) return;
    final to = selectedPeerId;
    final msgId = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    chat.addLocalChat(text: text.trim(), to: to, messageId: msgId);
    await n.sendChat(text.trim(), to: to);
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

  /// Import credential from QR payload, JSON, or short code (mesh cache).
  Future<PublicCredential?> importCredential(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // Prefer full payload parse; fall back to short-code cache lookup.
    PublicCredential? cred;
    try {
      cred = PublicCredential.parse(text);
    } on FormatException {
      cred = offerCache.byShortCode(text);
      if (cred == null) {
        // Match short code against already-trusted contacts.
        for (final c in trustedCredentials.values) {
          if (ShortCode.matches(text, c.subjectId)) {
            cred = c;
            break;
          }
        }
      }
      if (cred == null) {
        throw const FormatException(
          'Unknown short code — ask peer to publish offer or share QR payload',
        );
      }
    }

    if (!await cred.verify()) {
      throw StateError('credential signature invalid');
    }
    if (identity != null && cred.subjectId == identity!.id) {
      throw StateError('cannot import own credential');
    }

    trustedCredentials[cred.subjectId] = cred;
    offerCache.put(cred);
    chat.addSystem(
      'Trusted credential: ${cred.displayName.isEmpty ? cred.subjectId : cred.displayName}'
      ' · ${cred.shortCode}',
    );
    status = 'Imported ${cred.shortCode}';
    notifyListeners();
    return cred;
  }

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
    final cred = CredentialWire.tryDecodeOffer(m.payload);
    if (cred == null) return;
    try {
      if (!await cred.verify()) return;
      if (identity != null && cred.subjectId == identity!.id) return;
      offerCache.put(cred);
      chat.addSystem(
        'Credential offer from '
        '${cred.displayName.isEmpty ? cred.subjectId : cred.displayName}'
        ' · short code ${cred.shortCode}',
      );
      notifyListeners();
    } catch (_) {
      // Ignore malformed control frames.
    }
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

  Future<void> _onNfcCredential(PublicCredential cred) async {
    try {
      if (!await cred.verify()) {
        chat.addSystem('NFC credential signature invalid');
        notifyListeners();
        return;
      }
      if (identity != null && cred.subjectId == identity!.id) return;

      // Auto-trust on intentional NFC receive/share flow.
      trustedCredentials[cred.subjectId] = cred;
      offerCache.put(cred);
      nfcCredentialArmed = nfcTransport?.isCredentialShareArmed ?? false;
      chat.addSystem(
        'NFC trusted: '
        '${cred.displayName.isEmpty ? cred.subjectId : cred.displayName}'
        ' · ${cred.shortCode}',
      );
      status = 'NFC import ${cred.shortCode}';
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
    unawaited(transfers?.dispose());
    unawaited(node?.dispose());
    unawaited(demoPeer?.dispose());
    super.dispose();
  }
}

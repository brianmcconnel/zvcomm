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

  StreamSubscription<Peer>? _peerSub;
  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<PresenceInfo>? _presenceSub;
  StreamSubscription<FileTransferProgress>? _xferSub;
  StreamSubscription<({FileTransferInfo info, Uint8List bytes})>? _xferDoneSub;

  bool ready = false;
  bool running = false;
  bool useMockDemo = true;
  TransportPowerMode powerMode = TransportPowerMode.balanced;
  String? status;
  String? selectedPeerId;
  String displayName = 'This device';

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
      }
    });
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
      } catch (e) {
        chat.addSystem('Failed to enable ${plugin.name}: $e');
      }
    } else if (existing != null) {
      await mgr.unregister(existing);
      pluginTransports.remove(pluginId);
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

  void setUseMockDemo(bool value) {
    useMockDemo = value;
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
    unawaited(transfers?.dispose());
    unawaited(node?.dispose());
    unawaited(demoPeer?.dispose());
    super.dispose();
  }
}

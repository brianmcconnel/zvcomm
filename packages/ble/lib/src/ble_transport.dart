import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart' as ble;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:core/core.dart';

import 'ble_connection.dart';

/// Bluetooth LE transport: peripheral GATT server + central scanner/client.
///
/// Discovery filters on [ZvcommProtocol.bleServiceUuid]. Identity is advertised
/// via local name and (where supported) service data / manufacturer payload.
final class BleTransport implements Transport {
  final ble.CentralManager? _central;
  final ble.PeripheralManager? _peripheral;
  final bool _platformReady;

  final StreamController<Peer> _discovery =
      StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();

  final Map<String, ble.Peripheral> _seenPeripherals = {};
  final Map<String, BleConnection> _connections = {};
  // Peripheral-role links keyed by remote central uuid string.
  final Map<String, BleConnection> _peripheralLinks = {};
  final Map<String, bool> _notifyEnabled = {};

  final List<StreamSubscription<dynamic>> _subs = [];

  String _localId = '';
  String _displayName = '';
  bool _advertising = false;
  bool _discovering = false;
  TransportPowerMode _powerMode = TransportPowerMode.balanced;
  Timer? _dutyTimer;
  bool _scanActive = false;

  ble.GATTCharacteristic? _rxChar;
  ble.GATTCharacteristic? _txChar;
  ble.GATTCharacteristic? _identityChar;

  /// Creates a live BLE transport when the platform plugin is available.
  ///
  /// On unsupported hosts (e.g. pure Dart tests), [isAvailable] returns false.
  factory BleTransport() {
    if (kIsWeb) {
      return BleTransport._unavailable();
    }
    try {
      return BleTransport._(
        central: ble.CentralManager(),
        peripheral: ble.PeripheralManager(),
        platformReady: true,
      );
    } catch (_) {
      return BleTransport._unavailable();
    }
  }

  /// Explicit unavailable transport for tests.
  factory BleTransport.unavailable() => BleTransport._unavailable();

  BleTransport._({
    required ble.CentralManager? central,
    required ble.PeripheralManager? peripheral,
    required bool platformReady,
  })  : _central = central,
        _peripheral = peripheral,
        _platformReady = platformReady {
    if (_platformReady) {
      _wireEvents();
    }
  }

  factory BleTransport._unavailable() => BleTransport._(
        central: null,
        peripheral: null,
        platformReady: false,
      );

  static final ble.UUID serviceUuid =
      ble.UUID.fromString(ZvcommProtocol.bleServiceUuid);
  static final ble.UUID rxUuid =
      ble.UUID.fromString(ZvcommProtocol.bleRxCharacteristicUuid);
  static final ble.UUID txUuid =
      ble.UUID.fromString(ZvcommProtocol.bleTxCharacteristicUuid);
  static final ble.UUID identityUuid =
      ble.UUID.fromString(ZvcommProtocol.bleIdentityCharacteristicUuid);

  @override
  TransportKind get kind => TransportKind.ble;

  @override
  String get name => 'Bluetooth LE';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: true,
        supportsBackground: true,
        maxMtu: 512,
        typicalRangeMeters: 30,
      );

  @override
  Stream<Connection> get incomingConnections => _inbound.stream;

  void _wireEvents() {
    final central = _central!;
    final peripheral = _peripheral!;

    _subs.add(central.stateChanged.listen((e) async {
      if (e.state == ble.BluetoothLowEnergyState.unauthorized &&
          !kIsWeb &&
          Platform.isAndroid) {
        try {
          await central.authorize();
        } catch (_) {}
      }
    }));

    _subs.add(central.discovered.listen(_onDiscovered));

    _subs.add(central.characteristicNotified.listen((e) {
      final key = e.peripheral.uuid.toString();
      final conn = _connections[key];
      if (conn != null) {
        conn.deliverChunk(e.value);
      }
    }));

    _subs.add(central.connectionStateChanged.listen((e) {
      final key = e.peripheral.uuid.toString();
      final conn = _connections[key];
      if (conn == null) return;
      if (e.state == ble.ConnectionState.disconnected) {
        unawaited(conn.close());
        _connections.remove(key);
      }
    }));

    _subs.add(peripheral.characteristicWriteRequested.listen((e) async {
      try {
        await peripheral.respondWriteRequest(e.request);
      } catch (_) {}
      if (e.characteristic.uuid != rxUuid) return;
      final centralKey = e.central.uuid.toString();
      final conn = _peripheralLinks.putIfAbsent(centralKey, () {
        final peer = Peer(
          id: centralKey,
          displayName: '',
          transports: {TransportKind.ble},
          addresses: {TransportKind.ble: centralKey},
          lastSeen: DateTime.now().toUtc(),
        );
        final link = BleConnection(
          peer: peer,
          writeChunk: (chunk) async {
            if (!(_notifyEnabled[centralKey] ?? false)) return;
            await peripheral.notifyCharacteristic(
              e.central,
              _txChar!,
              value: chunk,
            );
          },
          onClose: () async {
            _peripheralLinks.remove(centralKey);
            _notifyEnabled.remove(centralKey);
            try {
              if (!kIsWeb && Platform.isAndroid) {
                await peripheral.disconnect(e.central);
              }
            } catch (_) {}
          },
          maxChunk: () => 180,
        );
        link.markOpen();
        if (!_inbound.isClosed) {
          _inbound.add(link);
        }
        return link;
      });
      conn.deliverChunk(e.request.value);
    }));

    _subs.add(peripheral.characteristicReadRequested.listen((e) async {
      try {
        if (e.characteristic.uuid == identityUuid) {
          final value = Uint8List.fromList(
            utf8.encode('$_localId|$_displayName'),
          );
          final trimmed = e.request.offset < value.length
              ? value.sublist(e.request.offset)
              : Uint8List(0);
          await peripheral.respondReadRequestWithValue(
            e.request,
            value: trimmed,
          );
        } else {
          await peripheral.respondReadRequestWithValue(
            e.request,
            value: Uint8List(0),
          );
        }
      } catch (_) {}
    }));

    _subs.add(peripheral.characteristicNotifyStateChanged.listen((e) {
      final key = e.central.uuid.toString();
      _notifyEnabled[key] = e.state;
    }));
  }

  void _onDiscovered(ble.DiscoveredEventArgs event) {
    if (!_discovering) return;
    final adv = event.advertisement;
    final hasService = adv.serviceUUIDs.any((u) => u == serviceUuid);
    // Accept devices advertising our service, or any with ZV manufacturer data.
    final mfg = adv.manufacturerSpecificData
        .where((m) => m.id == ZvcommProtocol.bleManufacturerId)
        .toList();
    if (!hasService && mfg.isEmpty && (adv.name == null || adv.name!.isEmpty)) {
      // Still accept if filtered scan already applied service UUID.
      if (adv.serviceUUIDs.isEmpty && mfg.isEmpty) {
        // Keep if scan was service-filtered; peripheral uuid is enough.
      }
    }

    final address = event.peripheral.uuid.toString();
    _seenPeripherals[address] = event.peripheral;

    String id = address;
    String displayName = adv.name ?? '';
    final serviceData = adv.serviceData[serviceUuid];
    if (serviceData != null && serviceData.isNotEmpty) {
      try {
        final text = utf8.decode(serviceData, allowMalformed: true);
        final parts = text.split('|');
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          id = parts.first;
          if (parts.length > 1) displayName = parts[1];
        }
      } catch (_) {}
    } else if (mfg.isNotEmpty && mfg.first.data.isNotEmpty) {
      try {
        final text = utf8.decode(mfg.first.data, allowMalformed: true);
        final parts = text.split('|');
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          id = parts.first;
          if (parts.length > 1) displayName = parts[1];
        }
      } catch (_) {}
    }

    final peer = Peer(
      id: id,
      displayName: displayName,
      transports: {TransportKind.ble},
      rssi: event.rssi,
      addresses: {TransportKind.ble: address},
      lastSeen: DateTime.now().toUtc(),
      metadata: {
        'bleAddress': address,
        if (adv.name != null) 'advName': adv.name!,
      },
    );
    if (!_discovery.isClosed) {
      _discovery.add(peer);
    }
  }

  @override
  Future<bool> isAvailable() async {
    if (!_platformReady || _central == null) return false;
    if (kIsWeb) return false;
    try {
      // Do not request permissions here — that can hang in tests / headless CI.
      // Permission prompts happen when advertising or scanning starts.
      final s = _central.state;
      return s == ble.BluetoothLowEnergyState.poweredOn ||
          s == ble.BluetoothLowEnergyState.unknown ||
          s == ble.BluetoothLowEnergyState.unauthorized;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensurePermissions() async {
    if (kIsWeb) return;
    if (Platform.isAndroid || Platform.isIOS) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    if (!_platformReady || _peripheral == null) return;
    _localId = localId;
    _displayName = displayName ?? '';
    await _ensurePermissions();

    final peripheral = _peripheral;
    await peripheral.removeAllServices();

    final identityValue = Uint8List.fromList(
      utf8.encode('$localId|${displayName ?? ''}'),
    );

    _identityChar = ble.GATTCharacteristic.immutable(
      uuid: identityUuid,
      value: identityValue,
      descriptors: [],
    );
    _rxChar = ble.GATTCharacteristic.mutable(
      uuid: rxUuid,
      properties: [
        ble.GATTCharacteristicProperty.write,
        ble.GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: [ble.GATTCharacteristicPermission.write],
      descriptors: [],
    );
    _txChar = ble.GATTCharacteristic.mutable(
      uuid: txUuid,
      properties: [ble.GATTCharacteristicProperty.notify],
      permissions: [ble.GATTCharacteristicPermission.read],
      descriptors: [],
    );

    final service = ble.GATTService(
      uuid: serviceUuid,
      isPrimary: true,
      includedServices: [],
      characteristics: [_identityChar!, _rxChar!, _txChar!],
    );
    await peripheral.addService(service);

    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'ZV-$localId';
    final shortName = name.length > 11 ? name.substring(0, 11) : name;

    final idBytes = Uint8List.fromList(
      utf8.encode(
        '$localId|${displayName ?? ''}'.length > 20
            ? localId
            : '$localId|${displayName ?? ''}',
      ),
    );

    final advertisement = ble.Advertisement(
      name: (!kIsWeb && Platform.isWindows) ? null : shortName,
      serviceUUIDs: [serviceUuid],
      serviceData: (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
          ? const {}
          : {serviceUuid: idBytes},
      manufacturerSpecificData: (!kIsWeb && (Platform.isIOS || Platform.isMacOS))
          ? const []
          : [
              ble.ManufacturerSpecificData(
                id: ZvcommProtocol.bleManufacturerId,
                data: idBytes.length > 20
                    ? Uint8List.sublistView(idBytes, 0, 20)
                    : idBytes,
              ),
            ],
    );

    await peripheral.startAdvertising(advertisement);
    _advertising = true;
  }

  @override
  Future<void> stopAdvertising() async {
    if (!_advertising || _peripheral == null) return;
    try {
      await _peripheral.stopAdvertising();
    } catch (_) {}
    _advertising = false;
  }

  @override
  Stream<Peer> discover() {
    if (!_platformReady || _central == null) {
      return const Stream.empty();
    }
    unawaited(_startScanLoop());
    return _discovery.stream;
  }

  Future<void> _startScanLoop() async {
    _discovering = true;
    await _ensurePermissions();
    await _applyScanForPowerMode();
  }

  Future<void> _applyScanForPowerMode() async {
    _dutyTimer?.cancel();
    _dutyTimer = null;
    if (!_discovering || _central == null) return;

    switch (_powerMode) {
      case TransportPowerMode.performance:
      case TransportPowerMode.balanced:
        await _startScan();
      case TransportPowerMode.powerSaver:
        await _startScan();
        _dutyTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
          if (!_discovering) return;
          await _stopScan();
          await Future<void>.delayed(const Duration(seconds: 5));
          if (_discovering) await _startScan();
        });
      case TransportPowerMode.ultraLow:
        await _stopScan();
        // Discovery only when actively connecting / rare burst.
        _dutyTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
          if (!_discovering) return;
          await _startScan();
          await Future<void>.delayed(const Duration(seconds: 3));
          if (_discovering && _powerMode == TransportPowerMode.ultraLow) {
            await _stopScan();
          }
        });
    }
  }

  Future<void> _startScan() async {
    if (_central == null || _scanActive) return;
    try {
      await _central.startDiscovery(serviceUUIDs: [serviceUuid]);
      _scanActive = true;
    } catch (_) {
      try {
        await _central.startDiscovery();
        _scanActive = true;
      } catch (_) {}
    }
  }

  Future<void> _stopScan() async {
    if (_central == null || !_scanActive) return;
    try {
      await _central.stopDiscovery();
    } catch (_) {}
    _scanActive = false;
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    _dutyTimer?.cancel();
    _dutyTimer = null;
    await _stopScan();
  }

  @override
  Future<Connection> connect(Peer peer) async {
    if (!_platformReady || _central == null) {
      throw StateError('BLE platform not available');
    }
    final address = peer.addresses[TransportKind.ble] ?? peer.id;
    final peripheral = _seenPeripherals[address];
    if (peripheral == null) {
      throw StateError(
        'BLE peer $address not in scan cache; start discovery first',
      );
    }

    final existing = _connections[address];
    if (existing != null && existing.state == ConnectionState.open) {
      return existing;
    }

    await _central.connect(peripheral);
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _central.requestMTU(peripheral, mtu: 512);
      }
    } catch (_) {}

    final services = await _central.discoverGATT(peripheral);
    ble.GATTService? mesh;
    for (final s in services) {
      if (s.uuid == serviceUuid) {
        mesh = s;
        break;
      }
    }
    if (mesh == null) {
      await _central.disconnect(peripheral);
      throw StateError('ZVComm mesh service not found on $address');
    }

    ble.GATTCharacteristic? rx;
    ble.GATTCharacteristic? tx;
    ble.GATTCharacteristic? identity;
    for (final c in mesh.characteristics) {
      if (c.uuid == rxUuid) rx = c;
      if (c.uuid == txUuid) tx = c;
      if (c.uuid == identityUuid) identity = c;
    }
    if (rx == null || tx == null) {
      await _central.disconnect(peripheral);
      throw StateError('ZVComm RX/TX characteristics missing on $address');
    }

    String peerId = peer.id;
    String peerName = peer.displayName;
    if (identity != null) {
      try {
        final raw = await _central.readCharacteristic(peripheral, identity);
        final text = utf8.decode(raw, allowMalformed: true);
        final parts = text.split('|');
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          peerId = parts.first;
          if (parts.length > 1) peerName = parts[1];
        }
      } catch (_) {}
    }

    final resolvedPeer = peer.copyWith(
      id: peerId,
      displayName: peerName,
      transports: {...peer.transports, TransportKind.ble},
      addresses: {...peer.addresses, TransportKind.ble: address},
      lastSeen: DateTime.now().toUtc(),
    );

    var maxWrite = 180;
    try {
      maxWrite = await _central.getMaximumWriteLength(
        peripheral,
        type: ble.GATTCharacteristicWriteType.withoutResponse,
      );
    } catch (_) {}

    final conn = BleConnection(
      peer: resolvedPeer,
      writeChunk: (chunk) async {
        await _central.writeCharacteristic(
          peripheral,
          rx!,
          value: chunk,
          type: ble.GATTCharacteristicWriteType.withoutResponse,
        );
      },
      onClose: () async {
        _connections.remove(address);
        try {
          await _central.disconnect(peripheral);
        } catch (_) {}
      },
      maxChunk: () => maxWrite > 20 ? maxWrite - 3 : 20,
      metrics: LinkMetrics(mtu: maxWrite, rssi: peer.rssi),
    );

    await _central.setCharacteristicNotifyState(
      peripheral,
      tx,
      state: true,
    );

    conn.markOpen();
    _connections[address] = conn;
    return conn;
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    _powerMode = mode;
    if (_discovering) {
      await _applyScanForPowerMode();
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await stopAdvertising();
    for (final c in [..._connections.values, ..._peripheralLinks.values]) {
      await c.close();
    }
    _connections.clear();
    _peripheralLinks.clear();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _discovery.close();
    await _inbound.close();
  }
}

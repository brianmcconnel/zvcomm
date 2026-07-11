import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:core/core.dart';

import 'nfc_payload.dart';

/// NFC transport optimized for pairing / bootstrap and short messages.
///
/// Continuous discovery runs an NFC reader session; each NDEF tag with a
/// ZVComm record is reported as a [Peer]. Optional write carries local identity.
final class NfcTransport implements Transport, ConnectionlessSend {
  final StreamController<Peer> _discovery = StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();

  String _localId = '';
  String _displayName = '';
  Map<String, String> _metadata = const {};
  bool _sessionActive = false;
  bool _discovering = false;
  bool _writeOnTap = false;
  Uint8List? _pendingSend;

  @override
  TransportKind get kind => TransportKind.nfc;

  @override
  String get name => 'NFC';

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        canDiscover: true,
        canConnect: true,
        canAdvertise: false,
        supportsBackground: false,
        maxMtu: 256,
        typicalRangeMeters: 1,
      );

  @override
  Stream<Connection> get incomingConnections => _inbound.stream;

  /// When true, the next discovered writable tag receives our identity NDEF.
  set writeIdentityOnNextTap(bool value) => _writeOnTap = value;

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      final availability = await NfcManager.instance.checkAvailability();
      return availability == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startAdvertising({
    required String localId,
    String? displayName,
    Map<String, String> metadata = const {},
  }) async {
    // NFC has no continuous advertise; store local identity for write-on-tap.
    _localId = localId;
    _displayName = displayName ?? '';
    _metadata = metadata;
    _writeOnTap = true;
  }

  @override
  Future<void> stopAdvertising() async {
    _writeOnTap = false;
  }

  @override
  Stream<Peer> discover() {
    unawaited(_startSession());
    return _discovery.stream;
  }

  Future<void> _startSession() async {
    if (_sessionActive) return;
    final available = await isAvailable();
    if (!available) return;

    _discovering = true;
    _sessionActive = true;
    try {
      await NfcManager.instance.startSession(
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        alertMessageIos: 'Hold near a ZVComm peer or tag',
        invalidateAfterFirstReadIos: false,
        onDiscovered: _onTag,
      );
    } catch (_) {
      _sessionActive = false;
      _discovering = false;
    }
  }

  Future<void> _onTag(NfcTag tag) async {
    try {
      final ndef = Ndef.from(tag);
      if (ndef == null) return;

      NdefMessage? message = ndef.cachedMessage;
      message ??= await ndef.read();

      Peer? peer;
      Uint8List? extra;
      if (message != null) {
        for (final record in message.records) {
          final payload = _parseRecord(record);
          if (payload != null) {
            peer = payload.toPeer();
            extra = payload.data;
            break;
          }
        }
      }

      if (peer != null && !_discovery.isClosed) {
        _discovery.add(peer);
      }

      final shouldWrite = _writeOnTap || _pendingSend != null;
      if (shouldWrite && ndef.isWritable) {
        final bootstrap = NfcBootstrapPayload(
          peerId: _localId,
          displayName: _displayName,
          metadata: _metadata,
          data: _pendingSend,
        );
        final record = NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(utf8.encode(ZvcommProtocol.nfcMimeType)),
          identifier: Uint8List(0),
          payload: bootstrap.toBytes(),
        );
        await ndef.write(message: NdefMessage(records: [record]));
        _pendingSend = null;
        _writeOnTap = false;
      }

      if (peer != null && extra != null && extra.isNotEmpty) {
        final conn = _OneShotNfcConnection(peer: peer, initial: extra);
        conn.markOpen();
        if (!_inbound.isClosed) {
          _inbound.add(conn);
        }
        conn.deliverInitial();
      }
    } catch (_) {
      // Ignore tag errors; keep session alive for next tap.
    }
  }

  NfcBootstrapPayload? _parseRecord(NdefRecord record) {
    try {
      final type = utf8.decode(record.type, allowMalformed: true);
      if (type == ZvcommProtocol.nfcMimeType || type.contains('zvcomm')) {
        return NfcBootstrapPayload.fromBytes(record.payload);
      }
      final text = utf8.decode(record.payload, allowMalformed: true);
      if (text.contains('zvcomm://peer/')) {
        final idx = text.indexOf('zvcomm://peer/');
        final rest = text.substring(idx + 'zvcomm://peer/'.length);
        final id = rest.split(RegExp(r'[\s\?/]')).first;
        return NfcBootstrapPayload(peerId: id);
      }
    } catch (_) {}
    return null;
  }

  @override
  Future<void> stopDiscovery() async {
    _discovering = false;
    if (!_sessionActive) return;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    _sessionActive = false;
  }

  @override
  Future<Connection> connect(Peer peer) async {
    final conn = _OneShotNfcConnection(peer: peer);
    conn.markOpen();
    conn.onOutbound = (data) {
      _pendingSend = data;
      _writeOnTap = true;
      if (!_sessionActive) {
        unawaited(_startSession());
      }
    };
    return conn;
  }

  @override
  Future<void> sendTo(Peer peer, Uint8List data) async {
    _pendingSend = data;
    _writeOnTap = true;
    if (!_sessionActive && _discovering) {
      await _startSession();
    }
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    if (mode == TransportPowerMode.ultraLow && _sessionActive) {
      await stopDiscovery();
      _discovering = true; // remember intent for resume
    } else if (_discovering && !_sessionActive) {
      await _startSession();
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await _discovery.close();
    await _inbound.close();
  }
}

/// Single-tap NFC logical connection.
final class _OneShotNfcConnection implements Connection {
  @override
  final Peer peer;

  @override
  TransportKind get kind => TransportKind.nfc;

  final StreamController<Uint8List> _incoming =
      StreamController<Uint8List>.broadcast();
  final StreamController<ConnectionState> _states =
      StreamController<ConnectionState>.broadcast();
  ConnectionState _state = ConnectionState.connecting;
  void Function(Uint8List data)? onOutbound;
  final Uint8List? _initial;

  _OneShotNfcConnection({required this.peer, Uint8List? initial})
      : _initial = initial;

  @override
  ConnectionState get state => _state;

  @override
  Stream<Uint8List> get incoming => _incoming.stream;

  @override
  Stream<ConnectionState> get stateChanges => _states.stream;

  @override
  LinkMetrics get metrics => const LinkMetrics(mtu: 256, rttMs: 50);

  void markOpen() {
    _state = ConnectionState.open;
    if (!_states.isClosed) _states.add(_state);
  }

  void deliverInitial() {
    if (_initial != null && !_incoming.isClosed) {
      _incoming.add(_initial);
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    if (_state != ConnectionState.open) {
      throw StateError('NFC connection not open');
    }
    onOutbound?.call(data);
  }

  @override
  Future<void> close() async {
    _state = ConnectionState.closed;
    if (!_states.isClosed) _states.add(_state);
    await _incoming.close();
    await _states.close();
  }
}

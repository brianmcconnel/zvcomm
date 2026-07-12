import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import 'package:core/core.dart';

import 'nfc_payload.dart';

/// NFC transport optimized for pairing / bootstrap, short messages, and
/// public-credential exchange (share / receive on tap).
///
/// Continuous discovery runs an NFC reader session; each NDEF tag with a
/// ZVComm record is reported as a [Peer]. Optional write carries local identity
/// and/or a [PublicCredential] for QR-less trust bootstrap.
final class NfcTransport implements Transport, ConnectionlessSend {
  final StreamController<Peer> _discovery = StreamController<Peer>.broadcast();
  final StreamController<Connection> _inbound =
      StreamController<Connection>.broadcast();
  final StreamController<PublicCredential> _credentials =
      StreamController<PublicCredential>.broadcast();
  final StreamController<String> _uriPayloads =
      StreamController<String>.broadcast();

  String _localId = '';
  String _displayName = '';
  Map<String, String> _metadata = const {};
  bool _sessionActive = false;
  bool _discovering = false;
  bool _writeOnTap = false;
  Uint8List? _pendingSend;
  PublicCredential? _pendingCredential;
  String? _pendingUri;
  String _sessionAlert = 'Hold near a ZVComm peer or tag';

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

  /// Stream of public credentials read from NFC tags / peer phones.
  Stream<PublicCredential> get credentialReads => _credentials.stream;

  /// Stream of raw `zvcomm:…` URIs (cred **or** org) read from NFC.
  Stream<String> get uriPayloadReads => _uriPayloads.stream;

  /// Whether a share write is armed for the next tap.
  bool get isCredentialShareArmed =>
      _pendingCredential != null || _pendingUri != null;

  /// When true, the next discovered writable tag receives our identity NDEF.
  set writeIdentityOnNextTap(bool value) => _writeOnTap = value;

  /// Arm the next NFC tap to write [credential] as an NDEF MIME record.
  ///
  /// Starts a reader session if needed. Call [cancelCredentialShare] to abort.
  Future<void> shareCredentialOnNextTap(
    PublicCredential credential, {
    String? localId,
    String? displayName,
  }) async {
    _pendingCredential = credential;
    _pendingUri = null;
    _localId = localId ?? credential.subjectId;
    _displayName = displayName ?? credential.displayName;
    _writeOnTap = true;
    _sessionAlert = 'Hold phones together to share credentials';
    await _ensureSession(forceRestart: true);
  }

  /// Arm the next NFC tap to write any ZVComm URI (org or credential).
  Future<void> shareUriOnNextTap(
    String uri, {
    required String localId,
    String displayName = '',
  }) async {
    _pendingUri = uri;
    _pendingCredential = null;
    _localId = localId;
    _displayName = displayName;
    _writeOnTap = true;
    _sessionAlert = uri.toLowerCase().startsWith('zvcomm:org:')
        ? 'Hold phones together to share organization'
        : 'Hold phones together to share credentials';
    await _ensureSession(forceRestart: true);
  }

  /// Arm a receive-only session (read peer credential / org on tap).
  Future<void> receiveCredentialOnNextTap() async {
    _pendingCredential = null;
    _pendingUri = null;
    _writeOnTap = false;
    _sessionAlert = 'Hold near peer phone or tag to import';
    await _ensureSession(forceRestart: true);
  }

  /// Clear a pending credential/URI write without stopping discovery.
  void cancelCredentialShare() {
    _pendingCredential = null;
    _pendingUri = null;
    _writeOnTap = false;
    _sessionAlert = 'Hold near a ZVComm peer or tag';
  }

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
    _pendingCredential = null;
    _pendingUri = null;
  }

  @override
  Stream<Peer> discover() {
    unawaited(_ensureSession());
    return _discovery.stream;
  }

  Future<void> _ensureSession({bool forceRestart = false}) async {
    if (_sessionActive && !forceRestart) return;
    if (_sessionActive && forceRestart) {
      try {
        await NfcManager.instance.stopSession();
      } catch (_) {}
      _sessionActive = false;
    }
    await _startSession();
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
        alertMessageIos: _sessionAlert,
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
      PublicCredential? receivedCred;
      String? receivedUri;
      if (message != null) {
        for (final record in message.records) {
          final payload = _parseRecord(record);
          if (payload != null) {
            peer = payload.toPeer();
            extra = payload.data;
            receivedCred = payload.credential;
            receivedUri = payload.uriPayload;
            break;
          }
        }
      }

      if (peer != null && !_discovery.isClosed) {
        _discovery.add(peer);
      }

      if (receivedCred != null && !_credentials.isClosed) {
        _credentials.add(receivedCred);
      }
      if (receivedUri != null &&
          receivedUri.isNotEmpty &&
          !_uriPayloads.isClosed) {
        _uriPayloads.add(receivedUri);
      }

      final shouldWrite = _writeOnTap ||
          _pendingSend != null ||
          _pendingCredential != null ||
          _pendingUri != null;
      if (shouldWrite && ndef.isWritable) {
        final NfcBootstrapPayload bootstrap;
        if (_pendingCredential != null) {
          bootstrap = NfcBootstrapPayload.forCredential(_pendingCredential!);
        } else if (_pendingUri != null) {
          bootstrap = NfcBootstrapPayload.forUri(
            uri: _pendingUri!,
            peerId: _localId,
            displayName: _displayName,
          );
        } else {
          bootstrap = NfcBootstrapPayload(
            peerId: _localId,
            displayName: _displayName,
            metadata: _metadata,
            data: _pendingSend,
          );
        }
        final record = NdefRecord(
          typeNameFormat: TypeNameFormat.media,
          type: Uint8List.fromList(utf8.encode(ZvcommProtocol.nfcMimeType)),
          identifier: Uint8List(0),
          payload: bootstrap.toBytes(),
        );
        await ndef.write(message: NdefMessage(records: [record]));
        _pendingSend = null;
        _pendingCredential = null;
        _pendingUri = null;
        _writeOnTap = false;
        _sessionAlert = 'Hold near a ZVComm peer or tag';
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
      // QR-style org or credential URI on a plain text NDEF record.
      for (final prefix in ['zvcomm:org:', 'zvcomm:cred:']) {
        if (text.contains(prefix)) {
          final start = text.indexOf(prefix);
          final end = text.indexOf(RegExp(r'[\s]'), start);
          final uri =
              (end < 0 ? text.substring(start) : text.substring(start, end))
                  .trim();
          if (prefix.startsWith('zvcomm:cred:')) {
            try {
              return NfcBootstrapPayload.forCredential(
                PublicCredential.parse(uri),
              );
            } catch (_) {
              return NfcBootstrapPayload.forUri(
                uri: uri,
                peerId: 'nfc',
              );
            }
          }
          return NfcBootstrapPayload.forUri(uri: uri, peerId: 'nfc');
        }
      }
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
        unawaited(_ensureSession());
      }
    };
    return conn;
  }

  @override
  Future<void> sendTo(Peer peer, Uint8List data) async {
    _pendingSend = data;
    _writeOnTap = true;
    if (!_sessionActive && _discovering) {
      await _ensureSession();
    }
  }

  @override
  Future<void> setPowerMode(TransportPowerMode mode) async {
    if (mode == TransportPowerMode.ultraLow && _sessionActive) {
      await stopDiscovery();
      _discovering = true; // remember intent for resume
    } else if (_discovering && !_sessionActive) {
      await _ensureSession();
    }
  }

  @override
  Future<void> dispose() async {
    await stopDiscovery();
    await _discovery.close();
    await _inbound.close();
    await _credentials.close();
    await _uriPayloads.close();
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

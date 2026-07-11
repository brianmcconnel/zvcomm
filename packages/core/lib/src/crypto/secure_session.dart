import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'identity.dart';

/// Wire tags for the ZVComm Noise-inspired handshake / secure payloads.
abstract final class SecureWire {
  static const int handshakeInit = 0x01;
  static const int handshakeResp = 0x02;
  static const int appData = 0x10;
  static const int protocolVersion = 1;
}

/// Result of deriving session keys after a completed handshake.
final class SessionKeys {
  final SecretKey sendKey;
  final SecretKey recvKey;
  final String remoteId;
  final Uint8List remoteX25519Public;
  final Uint8List remoteEd25519Public;

  const SessionKeys({
    required this.sendKey,
    required this.recvKey,
    required this.remoteId,
    required this.remoteX25519Public,
    required this.remoteEd25519Public,
  });
}

/// Established bidirectional secure session (AEAD counters).
final class SecureSession {
  final SessionKeys keys;
  final bool isInitiator;
  int _sendCounter = 0;

  SecureSession({required this.keys, required this.isInitiator});

  String get remoteId => keys.remoteId;

  /// Encrypt application payload; returns wire frame for mesh transport.
  Future<Uint8List> seal(Uint8List plaintext) async {
    final nonce = _nonceFromCounter(_sendCounter++);
    final box = await Chacha20.poly1305Aead().encrypt(
      plaintext,
      secretKey: keys.sendKey,
      nonce: nonce,
    );
    final out = BytesBuilder(copy: false)
      ..addByte(SecureWire.appData)
      ..add(nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return out.toBytes();
  }

  /// Decrypt a wire frame produced by [seal].
  Future<Uint8List> open(Uint8List frame) async {
    if (frame.isEmpty || frame[0] != SecureWire.appData) {
      throw FormatException('not app data frame');
    }
    if (frame.length < 1 + 12 + 16) {
      throw FormatException('app data frame too short');
    }
    final nonce = frame.sublist(1, 13);
    final mac = Mac(frame.sublist(frame.length - 16));
    final cipherText = frame.sublist(13, frame.length - 16);
    final clear = await Chacha20.poly1305Aead().decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: keys.recvKey,
    );
    return Uint8List.fromList(clear);
  }

  static List<int> _nonceFromCounter(int counter) {
    // 12-byte nonce: 4 zero bytes + u64be counter
    final n = Uint8List(12);
    final bd = ByteData.sublistView(n);
    bd.setUint32(0, 0);
    bd.setUint64(4, counter, Endian.big);
    return n;
  }
}

/// Noise-inspired XX-style handshake (X25519 + Ed25519 + ChaCha20-Poly1305 + HKDF).
///
/// Not a byte-compatible Noise Protocol Framework implementation; documented as
/// **ZVComm Handshake v1** for short-range mesh E2E sessions.
final class Handshake {
  final DeviceIdentity local;
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();

  SimpleKeyPair? _ephemeral;
  Uint8List? _remoteStaticEd;
  String? _remoteId;

  Handshake(this.local);

  /// Initiator → message 1: version | e_pub | s_x_pub | s_ed_pub | id | sig
  Future<Uint8List> createInitiation() async {
    _ephemeral = await _x25519.newKeyPair();
    final ePub = await _ephemeral!.extractPublicKey();
    final body = BytesBuilder(copy: false)
      ..addByte(SecureWire.protocolVersion)
      ..addByte(SecureWire.handshakeInit)
      ..add(ePub.bytes)
      ..add(local.x25519PublicKey)
      ..add(local.ed25519PublicKey)
      ..addByte(local.id.length)
      ..add(utf8.encode(local.id));
    final toSign = body.toBytes();
    final sig = await local.sign(toSign);
    return Uint8List.fromList([...toSign, ...sig]);
  }

  /// Responder processes message 1 and returns message 2 + session.
  Future<({Uint8List response, SecureSession session})> acceptInitiation(
    Uint8List message1,
  ) async {
    final parsed = await _parseInit(message1);
    _remoteStaticEd = parsed.staticEd;
    _remoteId = parsed.id;

    _ephemeral = await _x25519.newKeyPair();
    final ePub = await _ephemeral!.extractPublicKey();

    final keys = await _deriveKeys(
      initiator: false,
      remoteEph: parsed.eph,
      remoteStaticX: parsed.staticX,
    );

    final body = BytesBuilder(copy: false)
      ..addByte(SecureWire.protocolVersion)
      ..addByte(SecureWire.handshakeResp)
      ..add(ePub.bytes)
      ..add(local.x25519PublicKey)
      ..add(local.ed25519PublicKey)
      ..addByte(local.id.length)
      ..add(utf8.encode(local.id));
    final toSign = body.toBytes();
    final sig = await local.sign(toSign);

    // Confirmation tag under responder→initiator key.
    final confirm = await Chacha20.poly1305Aead().encrypt(
      utf8.encode('zvcomm-hs-ok'),
      secretKey: keys.sendKey,
      nonce: List<int>.filled(12, 0),
    );
    final response = Uint8List.fromList([
      ...toSign,
      ...sig,
      ...confirm.cipherText,
      ...confirm.mac.bytes,
    ]);

    final session = SecureSession(keys: keys, isInitiator: false);
    return (response: response, session: session);
  }

  /// Initiator processes message 2 and completes the session.
  Future<SecureSession> finish(Uint8List message2) async {
    if (_ephemeral == null) {
      throw StateError('createInitiation must be called first');
    }
    final parsed = await _parseResp(message2);
    _remoteStaticEd = parsed.staticEd;
    _remoteId = parsed.id;

    final keys = await _deriveKeys(
      initiator: true,
      remoteEph: parsed.eph,
      remoteStaticX: parsed.staticX,
    );

    // Verify confirmation.
    final confirmCipher = parsed.confirmCipher;
    final confirmMac = parsed.confirmMac;
    await Chacha20.poly1305Aead().decrypt(
      SecretBox(
        confirmCipher,
        nonce: List<int>.filled(12, 0),
        mac: Mac(confirmMac),
      ),
      secretKey: keys.recvKey,
    );

    return SecureSession(keys: keys, isInitiator: true);
  }

  Future<SessionKeys> _deriveKeys({
    required bool initiator,
    required Uint8List remoteEph,
    required Uint8List remoteStaticX,
  }) async {
    final ephPair = _ephemeral!;
    final staticPair = await local.x25519KeyPair();

    Future<List<int>> dh(SimpleKeyPair localPair, Uint8List remotePub) async {
      final secret = await _x25519.sharedSecretKey(
        keyPair: localPair,
        remotePublicKey: SimplePublicKey(remotePub, type: KeyPairType.x25519),
      );
      return secret.extractBytes();
    }

    // Noise-style transcript order (both sides must match):
    //   ee = DH(e_i, e_r)
    //   es = DH(e_i, s_r)
    //   se = DH(s_i, e_r)
    final List<int> eeBytes;
    final List<int> esBytes;
    final List<int> seBytes;
    if (initiator) {
      eeBytes = await dh(ephPair, remoteEph);
      esBytes = await dh(ephPair, remoteStaticX); // e_i, s_r
      seBytes = await dh(staticPair, remoteEph); // s_i, e_r
    } else {
      // Responder: local eph is e_r, local static is s_r; remote eph is e_i.
      eeBytes = await dh(ephPair, remoteEph);
      esBytes = await dh(staticPair, remoteEph); // s_r, e_i == e_i, s_r
      seBytes = await dh(ephPair, remoteStaticX); // e_r, s_i == s_i, e_r
    }

    final ikm = Uint8List.fromList([...eeBytes, ...esBytes, ...seBytes]);

    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 64);
    final okm = await hkdf.deriveKey(
      secretKey: SecretKey(ikm),
      nonce: utf8.encode('zvcomm-handshake-v1'),
      info: utf8.encode('session-keys'),
    );
    final okmBytes = await okm.extractBytes();
    final k1 = SecretKey(okmBytes.sublist(0, 32));
    final k2 = SecretKey(okmBytes.sublist(32, 64));

    // Initiator sends with k1, receives with k2; responder opposite.
    return SessionKeys(
      sendKey: initiator ? k1 : k2,
      recvKey: initiator ? k2 : k1,
      remoteId: _remoteId ?? '',
      remoteX25519Public: remoteStaticX,
      remoteEd25519Public: _remoteStaticEd ?? Uint8List(0),
    );
  }

  Future<
      ({
        Uint8List eph,
        Uint8List staticX,
        Uint8List staticEd,
        String id,
      })> _parseInit(Uint8List msg) async {
    var o = 0;
    if (msg.length < 2 + 32 * 3 + 1 + 64) {
      throw FormatException('handshake init too short');
    }
    final ver = msg[o++];
    final type = msg[o++];
    if (ver != SecureWire.protocolVersion || type != SecureWire.handshakeInit) {
      throw FormatException('bad handshake init header');
    }
    final eph = msg.sublist(o, o + 32);
    o += 32;
    final staticX = msg.sublist(o, o + 32);
    o += 32;
    final staticEd = msg.sublist(o, o + 32);
    o += 32;
    final idLen = msg[o++];
    final id = utf8.decode(msg.sublist(o, o + idLen));
    o += idLen;
    final signed = msg.sublist(0, o);
    final sig = msg.sublist(o);
    final ok = await _ed25519.verify(
      signed,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(staticEd, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) throw FormatException('handshake init signature invalid');
    return (eph: eph, staticX: staticX, staticEd: staticEd, id: id);
  }

  Future<
      ({
        Uint8List eph,
        Uint8List staticX,
        Uint8List staticEd,
        String id,
        Uint8List confirmCipher,
        Uint8List confirmMac,
      })> _parseResp(Uint8List msg) async {
    var o = 0;
    if (msg.length < 2 + 32 * 3 + 1 + 64 + 16) {
      throw FormatException('handshake resp too short');
    }
    final ver = msg[o++];
    final type = msg[o++];
    if (ver != SecureWire.protocolVersion || type != SecureWire.handshakeResp) {
      throw FormatException('bad handshake resp header');
    }
    final eph = msg.sublist(o, o + 32);
    o += 32;
    final staticX = msg.sublist(o, o + 32);
    o += 32;
    final staticEd = msg.sublist(o, o + 32);
    o += 32;
    final idLen = msg[o++];
    final id = utf8.decode(msg.sublist(o, o + idLen));
    o += idLen;
    final signed = msg.sublist(0, o);
    // signature 64 bytes for Ed25519
    final sig = msg.sublist(o, o + 64);
    o += 64;
    final ok = await _ed25519.verify(
      signed,
      signature: Signature(
        sig,
        publicKey: SimplePublicKey(staticEd, type: KeyPairType.ed25519),
      ),
    );
    if (!ok) throw FormatException('handshake resp signature invalid');
    final rest = msg.sublist(o);
    if (rest.length < 16) throw FormatException('missing confirm');
    final confirmMac = rest.sublist(rest.length - 16);
    final confirmCipher = rest.sublist(0, rest.length - 16);
    return (
      eph: eph,
      staticX: staticX,
      staticEd: staticEd,
      id: id,
      confirmCipher: confirmCipher,
      confirmMac: confirmMac,
    );
  }
}

/// Manages handshakes and sessions keyed by remote peer id.
final class SessionManager {
  final DeviceIdentity local;
  final Map<String, SecureSession> _sessions = {};
  final Map<String, Handshake> _pendingInit = {};

  SessionManager(this.local);

  SecureSession? sessionFor(String peerId) => _sessions[peerId];

  bool hasSession(String peerId) => _sessions.containsKey(peerId);

  /// Start initiator handshake; returns wire payload for MessageKind.control.
  Future<Uint8List> beginHandshake(String remoteHintId) async {
    final hs = Handshake(local);
    _pendingInit[remoteHintId] = hs;
    return hs.createInitiation();
  }

  /// Handle inbound handshake / return optional reply + completed remote id.
  Future<({Uint8List? reply, String? establishedPeerId})>
      handleHandshakeMessage(
    Uint8List frame,
  ) async {
    if (frame.length < 2) {
      return (reply: null, establishedPeerId: null);
    }
    final type = frame[1];
    if (type == SecureWire.handshakeInit) {
      final hs = Handshake(local);
      final result = await hs.acceptInitiation(frame);
      final remoteId = result.session.remoteId;
      _sessions[remoteId] = result.session;
      return (reply: result.response, establishedPeerId: remoteId);
    }
    if (type == SecureWire.handshakeResp) {
      // Match pending initiator (single pending if unknown id).
      Handshake? hs;
      String? key;
      if (_pendingInit.length == 1) {
        key = _pendingInit.keys.first;
        hs = _pendingInit[key];
      } else {
        // Try all pending.
        for (final e in _pendingInit.entries) {
          hs = e.value;
          key = e.key;
          break;
        }
      }
      if (hs == null) {
        throw StateError('no pending handshake for response');
      }
      final session = await hs.finish(frame);
      _pendingInit.remove(key);
      _sessions[session.remoteId] = session;
      return (reply: null, establishedPeerId: session.remoteId);
    }
    return (reply: null, establishedPeerId: null);
  }

  Future<Uint8List> encryptTo(String peerId, Uint8List plaintext) async {
    final s = _sessions[peerId];
    if (s == null) throw StateError('no session with $peerId');
    return s.seal(plaintext);
  }

  Future<Uint8List> decryptFrom(String peerId, Uint8List frame) async {
    final s = _sessions[peerId];
    if (s == null) throw StateError('no session with $peerId');
    return s.open(frame);
  }

  void clear() {
    _sessions.clear();
    _pendingInit.clear();
  }
}

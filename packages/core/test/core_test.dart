import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:core/core.dart';

void main() {
  group('MeshPacket', () {
    test('round-trips encode/decode', () {
      final packet = MeshPacket(
        messageId: 'abc123',
        sourceId: 'node-a',
        destinationId: 'node-b',
        kind: MessageKind.chat,
        hopLimit: 5,
        sequence: 42,
        payload: Uint8List.fromList(utf8.encode('hello mesh')),
      );

      final decoded = MeshPacket.decode(packet.encode());
      expect(decoded.messageId, packet.messageId);
      expect(decoded.sourceId, packet.sourceId);
      expect(decoded.destinationId, packet.destinationId);
      expect(decoded.kind, MessageKind.chat);
      expect(decoded.hopLimit, 5);
      expect(decoded.sequence, 42);
      expect(utf8.decode(decoded.payload), 'hello mesh');
    });

    test('broadcast uses null destination', () {
      final packet = MeshPacket(
        messageId: 'x',
        sourceId: 'a',
        kind: MessageKind.presence,
        hopLimit: 3,
        sequence: 1,
        payload: Uint8List(0),
      );
      final decoded = MeshPacket.decode(packet.encode());
      expect(decoded.isBroadcast, isTrue);
      expect(decoded.destinationId, isNull);
    });
  });

  group('FloodRouter', () {
    test('dedups and forwards with hop decrement', () {
      final router = FloodRouter(localId: 'me');
      final packet = MeshPacket(
        messageId: 'm1',
        sourceId: 'alice',
        kind: MessageKind.chat,
        hopLimit: 3,
        sequence: 1,
        payload: Uint8List.fromList([1, 2, 3]),
      );

      final first = router.decide(packet);
      expect(first.duplicate, isFalse);
      expect(first.deliverLocally, isTrue); // broadcast
      expect(first.shouldForward, isTrue);
      expect(first.forwardPacket!.hopLimit, 2);

      final second = router.decide(packet);
      expect(second.duplicate, isTrue);
    });

    test('does not forward when hopLimit is 1', () {
      final router = FloodRouter(localId: 'me');
      final packet = MeshPacket(
        messageId: 'm2',
        sourceId: 'alice',
        destinationId: 'bob',
        kind: MessageKind.chat,
        hopLimit: 1,
        sequence: 1,
        payload: Uint8List(0),
      );
      final d = router.decide(packet);
      expect(d.deliverLocally, isFalse);
      expect(d.shouldForward, isFalse);
    });
  });

  group('HybridPacketDeduper + Bloom', () {
    test('exact window catches recent duplicates', () {
      final d = HybridPacketDeduper(exactCapacity: 4, bloomBits: 1024);
      expect(d.observe('a'), isTrue);
      expect(d.observe('a'), isFalse);
    });

    test('aged keys are remembered via bloom', () {
      final d = HybridPacketDeduper(exactCapacity: 2, bloomBits: 4096);
      expect(d.observe('k0'), isTrue);
      expect(d.observe('k1'), isTrue);
      expect(d.observe('k2'), isTrue); // evicts k0 into bloom
      expect(d.observe('k0'), isFalse); // bloom hit
    });
  });

  group('RouteTable', () {
    test('prefers shorter paths', () {
      final t = RouteTable();
      t.learn(destinationId: 'z', nextHopId: 'a', hopCount: 3);
      t.learn(destinationId: 'z', nextHopId: 'b', hopCount: 2);
      expect(t.lookup('z')!.nextHopId, 'b');
      expect(t.lookup('z')!.hopCount, 2);
    });
  });

  group('Presence', () {
    test('codec round-trip and table seq', () {
      final bytes = PresenceCodec.encode(
        peerId: 'p1',
        displayName: 'Pat',
        sequence: 3,
      );
      final info = PresenceCodec.decode(bytes)!;
      expect(info.peerId, 'p1');
      expect(info.sequence, 3);
      final table = PresenceTable();
      expect(table.observe(info), isTrue);
      expect(
        table.observe(info.copyWith(sequence: 2)),
        isFalse,
      );
    });
  });

  group('MockTransport + MeshNode', () {
    late MockMedium medium;
    late MockTransport tA;
    late MockTransport tB;
    late MockTransport tC;
    late MeshNode nodeA;
    late MeshNode nodeB;
    late MeshNode nodeC;

    setUp(() {
      medium = MockMedium();
      tA = MockTransport(
        medium: medium,
        localId: 'a',
        displayName: 'Alice',
        position: const SimPoint(0, 0),
      );
      tB = MockTransport(
        medium: medium,
        localId: 'b',
        displayName: 'Bob',
        position: const SimPoint(10, 0),
      );
      tC = MockTransport(
        medium: medium,
        localId: 'c',
        displayName: 'Carol',
        position: const SimPoint(20, 0),
      );
      nodeA = MeshNode(
        localId: 'a',
        displayName: 'Alice',
        transports: TransportManager([tA]),
      );
      nodeB = MeshNode(
        localId: 'b',
        displayName: 'Bob',
        transports: TransportManager([tB]),
      );
      nodeC = MeshNode(
        localId: 'c',
        displayName: 'Carol',
        transports: TransportManager([tC]),
      );
    });

    tearDown(() async {
      await nodeA.dispose();
      await nodeB.dispose();
      await nodeC.dispose();
    });

    test('discovers peers on the mock medium', () async {
      await nodeA.start();
      await nodeB.start();

      final peer = await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      expect(peer.displayName, 'Bob');
      expect(peer.transports, contains(TransportKind.mock));
    });

    test('delivers direct chat over mock connection', () async {
      await nodeA.start();
      await nodeB.start();

      // Wait until A sees B.
      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      final received = nodeB.messages.first.timeout(const Duration(seconds: 3));
      await nodeA.sendChat('hello bob', to: 'b');

      final msg = await received;
      expect(msg.kind, MessageKind.chat);
      expect(utf8.decode(msg.payload), 'hello bob');
      expect(msg.sourceId, 'a');
    });

    test('floods multi-hop when all nodes are linked via discovery', () async {
      // Place all in range of each other for full mesh flood.
      tA.position = const SimPoint(0, 0);
      tB.position = const SimPoint(5, 0);
      tC.position = const SimPoint(10, 0);

      await nodeA.start();
      await nodeB.start();
      await nodeC.start();

      await Future.wait([
        nodeA.peerUpdates
            .firstWhere((p) => p.id == 'c')
            .timeout(const Duration(seconds: 3)),
        nodeC.peerUpdates
            .firstWhere((p) => p.id == 'a')
            .timeout(const Duration(seconds: 3)),
      ]);

      final received = nodeC.messages
          .firstWhere((m) => utf8.decode(m.payload) == 'multi-hop hi')
          .timeout(const Duration(seconds: 3));

      await nodeA.sendChat('multi-hop hi'); // broadcast
      final msg = await received;
      expect(msg.sourceId, 'a');
    });

    test('line multi-hop reaches non-adjacent node', () async {
      // A -- B -- C  (range only covers neighbors)
      tA.position = const SimPoint(0, 0);
      tB.position = const SimPoint(20, 0);
      tC.position = const SimPoint(40, 0);
      tA.rangeMeters = 25;
      tB.rangeMeters = 25;
      tC.rangeMeters = 25;

      await nodeA.start();
      await nodeB.start();
      await nodeC.start();

      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));
      await nodeC.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      final received = nodeC.messages
          .firstWhere((m) => utf8.decode(m.payload) == 'relay please')
          .timeout(const Duration(seconds: 4));

      await nodeA.sendChat('relay please');
      final msg = await received;
      expect(msg.sourceId, 'a');
      expect(nodeB.stats.forwarded, greaterThan(0));
    });

    test('unicast uses route toward destination', () async {
      tA.position = const SimPoint(0, 0);
      tB.position = const SimPoint(10, 0);
      tC.position = const SimPoint(20, 0);
      tA.rangeMeters = 50;
      tB.rangeMeters = 50;
      tC.rangeMeters = 50;

      await nodeA.start();
      await nodeB.start();
      await nodeC.start();

      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'c')
          .timeout(const Duration(seconds: 3));

      // Seed route A→C via B so adaptive path prefers B (optional).
      nodeA.routes.learn(destinationId: 'c', nextHopId: 'b', hopCount: 2);

      final received = nodeC.messages
          .firstWhere((m) => utf8.decode(m.payload) == 'direct-ish')
          .timeout(const Duration(seconds: 3));

      await nodeA.sendChat('direct-ish', to: 'c');
      expect(utf8.decode((await received).payload), 'direct-ish');
    });
  });

  group('DeviceIdentity', () {
    test('fromSeed is deterministic', () async {
      final a = await DeviceIdentity.fromSeed('test', displayName: 'T');
      final b = await DeviceIdentity.fromSeed('test', displayName: 'T');
      expect(a.id, b.id);
      expect(a.ed25519PublicKey, b.ed25519PublicKey);
      expect(a.x25519PublicKey, b.x25519PublicKey);
    });

    test('sign and verify', () async {
      final id = await DeviceIdentity.fromSeed('signer');
      final msg = Uint8List.fromList(utf8.encode('hello'));
      final sig = await id.sign(msg);
      expect(await id.verify(msg, sig), isTrue);
    });
  });

  group('SecureSession handshake', () {
    test('initiator and responder establish AEAD channel', () async {
      final alice = await DeviceIdentity.fromSeed('alice', displayName: 'A');
      final bob = await DeviceIdentity.fromSeed('bob', displayName: 'B');

      final hsA = Handshake(alice);
      final init = await hsA.createInitiation();
      final hsB = Handshake(bob);
      final accepted = await hsB.acceptInitiation(init);
      final sessionA = await hsA.finish(accepted.response);
      final sessionB = accepted.session;

      final cipher =
          await sessionA.seal(Uint8List.fromList(utf8.encode('ping')));
      final clear = await sessionB.open(cipher);
      expect(utf8.decode(clear), 'ping');

      final cipher2 =
          await sessionB.seal(Uint8List.fromList(utf8.encode('pong')));
      final clear2 = await sessionA.open(cipher2);
      expect(utf8.decode(clear2), 'pong');
    });
  });

  group('IdentityStore', () {
    test('memory store round-trip', () async {
      final store = MemoryIdentityStore();
      final id = await DeviceIdentity.fromSeed('stored');
      await store.save(StoredIdentity(identity: id));
      final loaded = await store.load();
      expect(loaded!.identity.id, id.id);
      expect(loaded.identity.ed25519PublicKey, id.ed25519PublicKey);
    });
  });

  group('TransportRegistry + plugins', () {
    late TransportRegistry registry;

    setUp(() {
      registry = TransportRegistry.instance;
      registry.clear();
      BuiltinCorePlugins.registerAll(registry);
    });

    tearDown(() {
      registry.clear();
    });

    test('registers stub plugins sorted by priority', () {
      final ids = registry.plugins.map((p) => p.id).toList();
      expect(ids, contains('builtin.uwb.stub'));
      expect(ids, contains('builtin.lora.stub'));
      // UWB priority 80 > hardware 30
      final uwb =
          registry.plugins.indexWhere((p) => p.id == 'builtin.uwb.stub');
      final hw = registry.plugins.indexWhere(
        (p) => p.id == BuiltinCorePlugins.hardwareAdapterId,
      );
      expect(uwb, lessThan(hw));
    });

    test('hot-plug transport on TransportManager', () async {
      final mgr = TransportManager([]);
      final medium = MockMedium();
      final t = MockTransport(medium: medium, localId: 'x', displayName: 'X');
      await mgr.register(t);
      expect(mgr.transports, hasLength(1));
      await mgr.unregister(t);
      expect(mgr.transports, isEmpty);
    });

    test('hardware adapter loopback carries framed mesh payload', () async {
      final pair = LoopbackHardwarePair();
      await pair.a.open();
      await pair.b.open();

      final tA = AdapterTransport(
        adapter: pair.a,
        remotePeerId: 'b',
        remoteDisplayName: 'B',
      );
      final tB = AdapterTransport(
        adapter: pair.b,
        remotePeerId: 'a',
        remoteDisplayName: 'A',
      );

      final nodeA = MeshNode(
        localId: 'a',
        transports: TransportManager([tA]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );
      final nodeB = MeshNode(
        localId: 'b',
        transports: TransportManager([tB]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );

      await nodeA.start();
      await nodeB.start();

      // Synthetic discovery peers for adapter transports.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Manually ensure peer addresses for connect.
      // Adapter discover emits hw peer ids 'b' and 'a'.
      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      final got = nodeB.messages.first.timeout(const Duration(seconds: 3));
      await nodeA.sendChat('via-hardware', to: 'b');
      final msg = await got;
      expect(utf8.decode(msg.payload), 'via-hardware');

      tA.cancelDiscoverySync();
      tB.cancelDiscoverySync();
      await nodeA.dispose();
      await nodeB.dispose();
    });
  });

  group('FileTransferService', () {
    test('sends and reassembles file over mock mesh', () async {
      final medium = MockMedium();
      final tA = MockTransport(
        medium: medium,
        localId: 'a',
        displayName: 'A',
        position: const SimPoint(0, 0),
      );
      final tB = MockTransport(
        medium: medium,
        localId: 'b',
        displayName: 'B',
        position: const SimPoint(5, 0),
      );
      final nodeA = MeshNode(
        localId: 'a',
        transports: TransportManager([tA]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );
      final nodeB = MeshNode(
        localId: 'b',
        transports: TransportManager([tB]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );
      final xferA = FileTransferService(node: nodeA, chunkSize: 50);
      final xferB = FileTransferService(node: nodeB, chunkSize: 50);
      xferA.start();
      xferB.start();

      await nodeA.start();
      await nodeB.start();
      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      final done = xferB.completed.first.timeout(const Duration(seconds: 5));
      final payload = Uint8List.fromList(
        List.generate(120, (i) => i & 0xff),
      );
      await xferA.sendFile(fileName: 'demo.bin', bytes: payload, to: 'b');
      final received = await done;
      expect(received.info.fileName, 'demo.bin');
      expect(received.bytes, payload);

      await xferA.dispose();
      await xferB.dispose();
      await nodeA.dispose();
      await nodeB.dispose();
    });
  });

  group('StreamFrameCodec', () {
    test('round-trips a payload', () {
      final payload = Uint8List.fromList(List.generate(50, (i) => i));
      final encoded = StreamFrameCodec.encode(payload);
      final codec = StreamFrameCodec();
      final frames = codec.add(encoded);
      expect(frames, hasLength(1));
      expect(frames.first, payload);
    });

    test('reassembles across chunks', () {
      final payload = Uint8List.fromList(utf8.encode('chunked mesh frame'));
      final encoded = StreamFrameCodec.encode(payload);
      final codec = StreamFrameCodec();
      expect(codec.add(Uint8List.sublistView(encoded, 0, 3)), isEmpty);
      expect(codec.add(Uint8List.sublistView(encoded, 3, 10)), isEmpty);
      final frames = codec.add(Uint8List.sublistView(encoded, 10));
      expect(frames, hasLength(1));
      expect(utf8.decode(frames.first), 'chunked mesh frame');
    });

    test('chunk splits large frames', () {
      final big = Uint8List(100);
      final frame = StreamFrameCodec.encode(big);
      final parts = StreamFrameCodec.chunk(frame, 20);
      expect(parts.length, greaterThan(1));
      final codec = StreamFrameCodec();
      final out = <Uint8List>[];
      for (final p in parts) {
        out.addAll(codec.add(p));
      }
      expect(out, hasLength(1));
      expect(out.first.length, 100);
    });
  });

  group('TransportManager', () {
    test('merges peer sightings', () async {
      final medium = MockMedium();
      final t = MockTransport(medium: medium, localId: 'x', displayName: 'X');
      final other =
          MockTransport(medium: medium, localId: 'y', displayName: 'Y');
      await other.startAdvertising(localId: 'y', displayName: 'Y');

      final mgr = TransportManager([t]);
      await mgr.startDiscovery();

      final peer = await mgr.peerUpdates
          .firstWhere((p) => p.id == 'y')
          .timeout(const Duration(seconds: 3));
      expect(peer.displayName, 'Y');

      await mgr.dispose();
      await other.dispose();
    });
  });

  group('MessageCensor', () {
    tearDown(MessageCensor.resetDefaults);

    test('masks known English profanity', () {
      MessageCensor.pattern = LanguagePattern.english;
      final out = MessageCensor.censor('what the shit is this');
      expect(out, isNot(contains('shit')));
      expect(out, contains('*'));
      expect(MessageCensor.hasProfanity('what the shit is this'), isTrue);
      expect(MessageCensor.hasProfanity('hello world'), isFalse);
    });

    test('can be disabled', () {
      MessageCensor.enabled = false;
      expect(MessageCensor.censor('shit'), 'shit');
    });

    test('sendChat censors before mesh delivery', () async {
      MessageCensor.pattern = LanguagePattern.english;
      final medium = MockMedium();
      final tA = MockTransport(
        medium: medium,
        localId: 'a',
        displayName: 'A',
        position: const SimPoint(0, 0),
      );
      final tB = MockTransport(
        medium: medium,
        localId: 'b',
        displayName: 'B',
        position: const SimPoint(5, 0),
      );
      final nodeA = MeshNode(
        localId: 'a',
        transports: TransportManager([tA]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );
      final nodeB = MeshNode(
        localId: 'b',
        transports: TransportManager([tB]),
        config: const MeshConfig(presenceInterval: Duration.zero),
      );
      await nodeA.start();
      await nodeB.start();
      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'b')
          .timeout(const Duration(seconds: 3));

      final got = nodeB.messages.first.timeout(const Duration(seconds: 3));
      await nodeA.sendChat('hello shit friend', to: 'b');
      final msg = await got;
      final text = utf8.decode(msg.payload);
      expect(text, isNot(contains('shit')));
      expect(text, contains('hello'));
      expect(text, contains('friend'));

      await nodeA.dispose();
      await nodeB.dispose();
    });

    test('censors after secure session decrypt', () async {
      MessageCensor.pattern = LanguagePattern.english;
      final alice = await DeviceIdentity.fromSeed(
        'alice-censor-seed',
        displayName: 'Alice',
      );
      final bob = await DeviceIdentity.fromSeed(
        'bob-censor-seed',
        displayName: 'Bob',
      );

      final hs = Handshake(alice);
      final msg1 = await hs.createInitiation();
      final bobHs = Handshake(bob);
      final msg2 = await bobHs.acceptInitiation(msg1);
      final aliceSession = await hs.finish(msg2.response);
      final bobSession = msg2.session;

      // Seal raw profanity (simulates peer without outbound filter), then
      // post-decrypt censor as SecureMesh does.
      final dirty = 'oh shit';
      final sealed = await aliceSession.seal(
        Uint8List.fromList(utf8.encode(dirty)),
      );
      final clear = await bobSession.open(sealed);
      final after = MessageCensor.censor(utf8.decode(clear));
      expect(after, isNot(contains('shit')));
      expect(after.length, dirty.length);
    });

    test('ChatLog censors local and remote lines', () {
      MessageCensor.pattern = LanguagePattern.english;
      final log = ChatLog();
      log.addLocalChat(text: 'damn shit', to: 'p', messageId: '1');
      expect(log.thread('p').single.text, isNot(contains('shit')));

      log.addRemoteChat(
        MeshMessage(
          id: '2',
          sourceId: 'p',
          kind: MessageKind.chat,
          payload: Uint8List.fromList(utf8.encode('more shit here')),
          timestamp: DateTime.now().toUtc(),
        ),
      );
      expect(log.thread('p').last.text, isNot(contains('shit')));
    });
  });

  group('PublicCredential', () {
    test('QR payload round-trips and verifies', () async {
      final id =
          await DeviceIdentity.fromSeed('qr-alice', displayName: 'Alice');
      final cred = await PublicCredential.fromIdentity(id);
      expect(cred.shortCode, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}$')));
      final payload = cred.toQrPayload();
      expect(payload, startsWith('zvcomm:cred:v1:'));
      final parsed = PublicCredential.parse(payload);
      expect(parsed.subjectId, id.id);
      expect(parsed.displayName, 'Alice');
      expect(await parsed.verify(), isTrue);
      expect(ShortCode.matches(cred.shortCode, id.id), isTrue);
    });

    test('offer cache resolves short code', () async {
      final id = await DeviceIdentity.fromSeed('qr-bob', displayName: 'Bob');
      final cred = await PublicCredential.fromIdentity(id);
      final cache = CredentialOfferCache();
      cache.put(cred);
      final found = cache.byShortCode(cred.shortCode.toLowerCase());
      expect(found?.subjectId, id.id);
    });
  });
}

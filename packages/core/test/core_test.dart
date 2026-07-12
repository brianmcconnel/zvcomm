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

    test('ChatLog reactions toggle and wire round-trip', () {
      final log = ChatLog();
      log.addLocalChat(text: 'hello', to: 'bob', messageId: 'm1');
      final updated = log.toggleReaction(
        messageId: 'm1',
        emoji: '👍',
        reactorId: 'alice',
      );
      expect(updated, isNotNull);
      expect(updated!.reactions['👍'], contains('alice'));
      log.toggleReaction(messageId: 'm1', emoji: '👍', reactorId: 'alice');
      expect(log.findById('m1')!.reactions.containsKey('👍'), isFalse);

      final bytes = ChatReactionWire.encode(
        messageId: 'm1',
        emoji: '❤️',
        reactorId: 'bob',
      );
      final event = ChatReactionWire.tryDecode(bytes);
      expect(event?.emoji, '❤️');
      expect(event?.messageId, 'm1');
    });

    test('TypingPresence status text and wire', () {
      final tp = TypingPresence();
      final gKey = TypingPresence.threadKey(groupId: 'g1');
      tp.setTyping(
        threadKey: gKey,
        peerId: 'a',
        typing: true,
        displayName: 'Alice',
      );
      expect(tp.statusText(gKey), 'Alice is typing…');
      tp.setTyping(
        threadKey: gKey,
        peerId: 'b',
        typing: true,
        displayName: 'Bob',
      );
      expect(tp.statusText(gKey), 'Alice and Bob are typing…');
      tp.setTyping(threadKey: gKey, peerId: 'a', typing: false);
      expect(tp.statusText(gKey), 'Bob is typing…');

      final bytes = ChatTypingWire.encode(
        peerId: 'a',
        typing: true,
        groupId: 'g1',
        displayName: 'Alice',
      );
      final ev = ChatTypingWire.tryDecode(bytes);
      expect(ev?.typing, isTrue);
      expect(ev?.groupId, 'g1');
      expect(ev?.displayName, 'Alice');
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

  group('Social: groups, block, report', () {
    test('BlockList blocks and unblocks', () {
      final list = BlockList();
      expect(list.isBlocked('a'), isFalse);
      list.block('a', displayName: 'Alice', reason: 'spam');
      expect(list.isBlocked('a'), isTrue);
      expect(list.entries.single.displayName, 'Alice');
      final json = list.toJson();
      final restored = BlockList.fromJson(json);
      expect(restored.isBlocked('a'), isTrue);
      restored.unblock('a');
      expect(restored.isBlocked('a'), isFalse);
    });

    test('GroupStore create invite membership', () {
      final store = GroupStore();
      final g = store.create(
        name: 'Ops',
        ownerId: 'owner',
        members: ['bob', 'carol'],
      );
      expect(g.isMember('owner'), isTrue);
      expect(g.isAdmin('owner'), isTrue);
      expect(g.memberCount, 3);
      store.addMember(g.id, 'dave');
      expect(store[g.id]!.isMember('dave'), isTrue);
      store.removeMember(g.id, 'bob');
      expect(store[g.id]!.isMember('bob'), isFalse);
      // Cannot remove owner.
      store.removeMember(g.id, 'owner');
      expect(store[g.id]!.isMember('owner'), isTrue);

      final wire = GroupWire.encodeInvite(store[g.id]!);
      final event = GroupWire.tryDecode(wire);
      expect(event, isNotNull);
      expect(event!.type, GroupWire.inviteType);
      expect(event.group!.name, 'Ops');
    });

    test('GroupChatWire round-trip and ChatLog group thread', () {
      final payload = GroupChatWire.encode(groupId: 'g-1', text: 'hello group');
      final parsed = GroupChatWire.tryParse(payload);
      expect(parsed?.groupId, 'g-1');
      expect(parsed?.text, 'hello group');

      final log = ChatLog();
      log.addLocalChat(
        text: 'hi',
        messageId: '1',
        groupId: 'g-1',
      );
      expect(log.groupThread('g-1').single.text, 'hi');
      expect(log.thread(null), isEmpty);

      final msg = MeshMessage(
        id: '2',
        sourceId: 'bob',
        kind: MessageKind.chat,
        payload: Uint8List.fromList(utf8.encode(payload)),
        timestamp: DateTime.now().toUtc(),
      );
      log.addRemoteChat(msg);
      expect(log.groupThread('g-1').length, 2);
      expect(log.groupThread('g-1').last.peerId, 'bob');
    });

    test('UserReport wire and store', () {
      final report = UserReport(
        id: 'r1',
        subjectId: 'bad',
        reporterId: 'me',
        category: ReportCategory.harassment,
        details: 'unwanted messages',
        createdAt: DateTime.now().toUtc(),
      );
      final bytes = ReportWire.encode(report);
      final decoded = ReportWire.tryDecode(bytes);
      expect(decoded, isNotNull);
      expect(decoded!.category, ReportCategory.harassment);
      expect(decoded.details, 'unwanted messages');

      final store = ReportStore()..add(report);
      expect(store.all, hasLength(1));
      final round = ReportStore.fromJson(store.toJson());
      expect(round.all.single.subjectId, 'bad');
    });
  });

  group('VoiceChannel', () {
    test('PCM WAV round-trip helpers', () {
      final pcm = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7]);
      final wav = pcm16ToWav(pcm, sampleRate: 8000, channels: 1);
      expect(wav.length, 44 + pcm.length);
      final restored = wavToPcm16(wav);
      expect(restored, pcm);
    });

    test('group fan-out tags gid and delivers to members', () async {
      final medium = MockMedium();
      final a = MockTransport(
        medium: medium,
        localId: 'va',
        displayName: 'A',
        position: const SimPoint(0, 0),
      );
      final b = MockTransport(
        medium: medium,
        localId: 'vb',
        displayName: 'B',
        position: const SimPoint(1, 0),
      );
      final c = MockTransport(
        medium: medium,
        localId: 'vc',
        displayName: 'C',
        position: const SimPoint(2, 0),
      );
      final nodeA = MeshNode(
        localId: 'va',
        displayName: 'A',
        transports: TransportManager([a]),
      );
      final nodeB = MeshNode(
        localId: 'vb',
        displayName: 'B',
        transports: TransportManager([b]),
      );
      final nodeC = MeshNode(
        localId: 'vc',
        displayName: 'C',
        transports: TransportManager([c]),
      );
      await nodeA.start();
      await nodeB.start();
      await nodeC.start();
      await Future.wait([
        nodeA.peerUpdates
            .firstWhere((p) => p.id == 'vb')
            .timeout(const Duration(seconds: 3)),
        nodeA.peerUpdates
            .firstWhere((p) => p.id == 'vc')
            .timeout(const Duration(seconds: 3)),
      ]);

      final voiceA = VoiceChannelService(node: nodeA)..start();
      final voiceB = VoiceChannelService(node: nodeB)..start();
      final voiceC = VoiceChannelService(node: nodeC)..start();
      // C pretends not to be in the group.
      voiceC.acceptIncoming = (info) => info.groupId != 'g-ops';

      final doneB = Completer<VoiceEvent>();
      final doneC = Completer<VoiceEvent>();
      final subB = voiceB.events.listen((e) {
        if (e.kind == VoiceEventKind.rxComplete && !doneB.isCompleted) {
          doneB.complete(e);
        }
      });
      final subC = voiceC.events.listen((e) {
        if (e.kind == VoiceEventKind.rxComplete && !doneC.isCompleted) {
          doneC.complete(e);
        }
      });

      final pcm = Uint8List(400);
      await voiceA.sendPcmBurst(
        pcm,
        recipients: ['vb', 'vc'],
        groupId: 'g-ops',
      );

      final eventB = await doneB.future.timeout(const Duration(seconds: 5));
      expect(eventB.transmission?.groupId, 'g-ops');
      expect(eventB.pcm!.length, pcm.length);

      // C filtered out — should not complete.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(doneC.isCompleted, isFalse);

      await subB.cancel();
      await subC.cancel();
      await voiceA.dispose();
      await voiceB.dispose();
      await voiceC.dispose();
      await nodeA.dispose();
      await nodeB.dispose();
      await nodeC.dispose();
      await a.dispose();
      await b.dispose();
      await c.dispose();
    });

    test('PTT burst delivers PCM over mock mesh', () async {
      final medium = MockMedium();
      final a = MockTransport(
        medium: medium,
        localId: 'voice-a',
        displayName: 'A',
        position: const SimPoint(0, 0),
      );
      final b = MockTransport(
        medium: medium,
        localId: 'voice-b',
        displayName: 'B',
        position: const SimPoint(1, 0),
      );
      final nodeA = MeshNode(
        localId: 'voice-a',
        displayName: 'A',
        transports: TransportManager([a]),
      );
      final nodeB = MeshNode(
        localId: 'voice-b',
        displayName: 'B',
        transports: TransportManager([b]),
      );
      await nodeA.start();
      await nodeB.start();
      await nodeA.peerUpdates
          .firstWhere((p) => p.id == 'voice-b')
          .timeout(const Duration(seconds: 3));

      final voiceA = VoiceChannelService(node: nodeA)..start();
      final voiceB = VoiceChannelService(node: nodeB)..start();

      final done = Completer<VoiceEvent>();
      final sub = voiceB.events.listen((e) {
        if (e.kind == VoiceEventKind.rxComplete && !done.isCompleted) {
          done.complete(e);
        }
      });

      // ~50 ms of 8 kHz mono s16 + a simple ramp.
      final pcm = Uint8List(800);
      for (var i = 0; i < pcm.length; i += 2) {
        final sample = (i * 17) & 0x7fff;
        pcm[i] = sample & 0xff;
        pcm[i + 1] = (sample >> 8) & 0xff;
      }

      await voiceA.sendPcmBurst(pcm, to: 'voice-b');
      final event = await done.future.timeout(const Duration(seconds: 5));
      expect(event.pcm, isNotNull);
      expect(event.pcm!.length, pcm.length);
      expect(event.transmission?.sourceId, 'voice-a');
      expect(event.pcm!.sublist(0, 8), pcm.sublist(0, 8));

      await sub.cancel();
      await voiceA.dispose();
      await voiceB.dispose();
      await nodeA.dispose();
      await nodeB.dispose();
      await a.dispose();
      await b.dispose();
    });
  });

  group('StatsHistory', () {
    test('records rates over time', () {
      final h = StatsHistory(capacity: 10);
      final s = MeshStats();
      final t0 = DateTime.utc(2020, 1, 1, 0, 0, 0);
      h.record(stats: s, peerCount: 1, presenceCount: 0, at: t0);
      s.originated = 10;
      s.delivered = 5;
      h.record(
        stats: s,
        peerCount: 2,
        presenceCount: 1,
        at: t0.add(const Duration(seconds: 2)),
      );
      final last = h.latest!;
      expect(last.originatedPerSec, closeTo(5, 0.01));
      expect(last.deliveredPerSec, closeTo(2.5, 0.01));
      expect(last.peerCount, 2);
      expect(h.length, 2);
    });
  });

  group('FamilySafety', () {
    test('SafetyMode parse accepts kid/teen aliases', () {
      expect(SafetyMode.parse('teen'), SafetyMode.teen);
      expect(SafetyMode.parse('child'), SafetyMode.child);
      expect(SafetyMode.parse('kid'), SafetyMode.child);
      expect(SafetyMode.parse('mediated'), SafetyMode.child);
      expect(SafetyMode.parse(null), SafetyMode.teen);
    });

    test('wire link/copy/mediate/status/settle round-trip', () {
      final link = FamilySafetyWire.encodeLink(
        guardianId: 'parent-1',
        guardianName: 'Mom',
        mode: SafetyMode.child,
        sharedWithIds: const ['teacher-1'],
        grounded: true,
        parentIds: const ['parent-1', 'parent-2'],
        parentNames: const {'parent-1': 'Mom', 'parent-2': 'Dad'},
      );
      final linkEv = FamilySafetyWire.tryDecode(link)!;
      expect(linkEv.type, FamilySafetyWire.linkType);
      expect(linkEv.body['guardianId'], 'parent-1');
      expect(SafetyMode.parse(linkEv.body['mode'] as String?), SafetyMode.child);
      expect(linkEv.body['grounded'], isTrue);
      expect(linkEv.body['parentIds'], containsAll(['parent-1', 'parent-2']));

      final ward = WardProfile(
        wardId: 'kid-1',
        displayName: 'Kid',
        mode: SafetyMode.teen,
        grounded: false,
        parentIds: const ['parent-1', 'parent-2'],
        parentNames: const {'parent-1': 'Mom', 'parent-2': 'Dad'},
        createdAt: DateTime.utc(2026, 1, 1),
        statusUpdatedAt: DateTime.utc(2026, 1, 5),
        statusById: 'parent-2',
        statusByName: 'Dad',
      );
      expect(ward.privilegeLabel, 'Teen');
      expect(ward.parentsLabel(selfId: 'parent-1'), 'You · Dad');

      final status = FamilySafetyWire.encodeStatus(
        ward: ward,
        updatedById: 'parent-2',
        updatedByName: 'Dad',
      );
      final statusEv = FamilySafetyWire.tryDecode(status)!;
      expect(statusEv.type, FamilySafetyWire.statusType);
      final remoteWard = WardProfile.fromJson(
        Map<String, Object?>.from(statusEv.body['ward']! as Map),
      );
      expect(remoteWard.privilegeLabel, 'Teen');
      expect(remoteWard.parentIds, hasLength(2));

      final settle = FamilySafetyWire.encodeSettle(
        requestId: 'req-1',
        approved: true,
        byId: 'parent-1',
        byName: 'Mom',
        fromId: 'kid-1',
        fromName: 'Kid',
        toLabel: 'Friend',
      );
      final settleEv = FamilySafetyWire.tryDecode(settle)!;
      expect(settleEv.type, FamilySafetyWire.settleType);
      expect(settleEv.body['approved'], isTrue);

      final copy = FamilySafetyWire.encodeCopy(
        fromId: 'teen-1',
        fromName: 'Alex',
        toLabel: 'Sam',
        text: 'hello',
        toPeerId: 'peer-2',
      );
      final copyEv = FamilySafetyWire.tryDecode(copy)!;
      expect(copyEv.type, FamilySafetyWire.copyType);
      expect(copyEv.body['text'], 'hello');

      final pending = PendingMediatedMessage(
        requestId: 'req-1',
        fromId: 'kid-1',
        fromName: 'Kid',
        toPeerId: 'friend',
        toLabel: 'Friend',
        text: 'can I go?',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final req = FamilySafetyWire.encodeMediateRequest(pending);
      final reqEv = FamilySafetyWire.tryDecode(req)!;
      expect(reqEv.type, FamilySafetyWire.mediateReqType);
      final decoded = PendingMediatedMessage.fromJson(reqEv.body);
      expect(decoded.requestId, 'req-1');
      expect(decoded.text, 'can I go?');

      final dec = FamilySafetyWire.encodeMediateDecision(
        requestId: 'req-1',
        approved: true,
        guardianId: 'parent-1',
        text: 'can I go?',
        toPeerId: 'friend',
      );
      final decEv = FamilySafetyWire.tryDecode(dec)!;
      expect(decEv.type, FamilySafetyWire.mediateDecisionType);
      expect(decEv.body['approved'], isTrue);
    });

    test('store wards, pending, feed, co-parent status', () {
      final s = FamilySafetyStore();
      s.putWard(
        WardProfile(
          wardId: 'kid-1',
          displayName: 'Kid',
          mode: SafetyMode.child,
          grounded: true,
          parentIds: const ['mom', 'dad'],
          parentNames: const {'mom': 'Mom', 'dad': 'Dad'},
          createdAt: DateTime.utc(2026, 1, 1),
          statusUpdatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(s.isGuardian, isTrue);
      expect(s.wards['kid-1']!.grounded, isTrue);
      expect(s.wards['kid-1']!.privilegeLabel, 'Kid · Grounded');

      // Newer co-parent status wins.
      final newer = WardProfile(
        wardId: 'kid-1',
        displayName: 'Kid',
        mode: SafetyMode.teen,
        grounded: false,
        parentIds: const ['mom', 'dad'],
        parentNames: const {'mom': 'Mom', 'dad': 'Dad'},
        createdAt: DateTime.utc(2026, 1, 1),
        statusUpdatedAt: DateTime.utc(2026, 1, 10),
        statusById: 'dad',
        statusByName: 'Dad',
      );
      expect(s.applyRemoteWardStatus(newer), isTrue);
      expect(s.wards['kid-1']!.mode, SafetyMode.teen);
      expect(s.wards['kid-1']!.grounded, isFalse);

      // Stale status ignored.
      final stale = newer.copyWith(
        grounded: true,
        statusUpdatedAt: DateTime.utc(2026, 1, 2),
      );
      expect(s.applyRemoteWardStatus(stale), isFalse);
      expect(s.wards['kid-1']!.grounded, isFalse);

      s.setMyPolicy(
        MySafetyPolicy(
          guardianId: 'mom',
          guardianName: 'Mom',
          parentIds: const ['mom', 'dad'],
          parentNames: const {'mom': 'Mom', 'dad': 'Dad'},
          mode: SafetyMode.teen,
          grounded: true,
          updatedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(s.isWard, isTrue);
      expect(s.iAmGrounded, isTrue);
      expect(s.myPolicy!.allParentIds, containsAll(['mom', 'dad']));
      expect(s.myPolicy!.parentsLabel, 'Mom · Dad');

      s.addPending(
        PendingMediatedMessage(
          requestId: 'r1',
          fromId: 'kid-1',
          fromName: 'Kid',
          toLabel: 'Everyone',
          text: 'hi',
          createdAt: DateTime.utc(2026, 1, 3),
        ),
      );
      s.addPending(
        PendingMediatedMessage(
          requestId: 'r2',
          fromId: 'other',
          fromName: 'Other',
          toLabel: 'Everyone',
          text: 'nope',
          createdAt: DateTime.utc(2026, 1, 3),
        ),
      );
      expect(s.hasPending, isTrue);
      s.clearPendingForWard('kid-1');
      expect(s.pendingApprovals, hasLength(1));
      expect(s.pendingApprovals.first.fromId, 'other');
      s.removePending('r2');
      expect(s.hasPending, isFalse);

      s.addCopy(
        SafetyCopy(
          id: 'c1',
          fromId: 'teen-1',
          fromName: 'Alex',
          toLabel: 'Sam',
          text: 'yo',
          at: DateTime.utc(2026, 1, 4),
        ),
      );
      expect(s.activityFeed, hasLength(1));

      final round = FamilySafetyStore.fromJson(s.toJson());
      expect(round.wards.containsKey('kid-1'), isTrue);
      expect(round.wards['kid-1']!.parentIds, containsAll(['mom', 'dad']));
      expect(round.myPolicy?.mode, SafetyMode.teen);
      expect(round.myPolicy?.grounded, isTrue);
    });
  });




  group('DiscussNotes', () {
    test('discretion parse and note json', () {
      expect(NoteDiscretion.parse('private'), NoteDiscretion.private);
      expect(NoteDiscretion.parse('parents'), NoteDiscretion.parents);
      final n = DiscussNote(
        id: 'dn1',
        fromId: 'teen',
        fromName: 'Alex',
        text: 'want to talk first',
        discretion: NoteDiscretion.private,
        createdAt: DateTime.utc(2026, 3, 1),
      );
      final round = DiscussNote.fromJson(n.toJson());
      expect(round.text, 'want to talk first');
      expect(round.discretion, NoteDiscretion.private);
      expect(round.isOpen, isTrue);

      final s = FamilySafetyStore();
      s.putDiscussNote(n);
      expect(s.hasOpenDiscussNotes, isTrue);
      s.putDiscussNote(
        n.copyWith(
          status: DiscussNoteStatus.closed,
          acknowledgedByName: 'Mom',
        ),
      );
      expect(s.openDiscussNotes, isEmpty);
      expect(s.discussNote('dn1')!.status, DiscussNoteStatus.closed);

      final wire = FamilySafetyWire.encodeDiscussNote(n);
      final ev = FamilySafetyWire.tryDecode(wire)!;
      expect(ev.type, FamilySafetyWire.discussNoteType);
    });
  });

  group('TimeLog', () {
    test('slots, empty hours, prompt', () {
      final s = TimeLogStore();
      final day = DateTime(2026, 7, 12, 14, 30);
      expect(s.shouldPromptNow(now: day), isTrue);
      s.setSlot(localDay: day, hour: 14, activity: 'Work');
      expect(s.shouldPromptNow(now: day), isFalse);
      expect(s.filledCount(day), 1);
      expect(s.emptyHours(day), hasLength(23));
      expect(s.slot(day, 14)!.activity, 'Work');
      final round = TimeLogStore.fromJson(s.toJson());
      expect(round.slot(day, 14)!.activity, 'Work');
      expect(TimeLogEntry.formatHour(0), '12:00 AM');
      expect(TimeLogEntry.formatHour(13), '1:00 PM');
    });
  });

  group('ChatImage', () {
    test('wire encode/decode and ChatLog remote image', () {
      final bytes = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final raw = ChatImageWire.encode(
        fileName: 'shot.png',
        mimeType: 'image/png',
        bytes: bytes,
        groupId: 'g-1',
        caption: 'hi',
      );
      final parsed = ChatImageWire.tryParse(raw)!;
      expect(parsed.fileName, 'shot.png');
      expect(parsed.mimeType, 'image/png');
      expect(parsed.groupId, 'g-1');
      expect(parsed.caption, 'hi');
      expect(parsed.bytes, bytes);

      final log = ChatLog();
      log.addRemoteChat(
        MeshMessage(
          id: 'm1',
          sourceId: 'alice',
          kind: MessageKind.chat,
          payload: Uint8List.fromList(utf8.encode(raw)),
          timestamp: DateTime.utc(2026, 1, 1),
        ),
        senderName: 'Alice',
      );
      final line = log.groupThread('g-1').single;
      expect(line.isImage, isTrue);
      expect(line.imageName, 'shot.png');
      expect(line.imageBytes, bytes);
      expect(line.senderName, 'Alice');
    });

    test('rejects oversized image', () {
      final big = Uint8List(ChatImageWire.maxBytes + 1);
      expect(
        () => ChatImageWire.encode(
          fileName: 'big.jpg',
          mimeType: 'image/jpeg',
          bytes: big,
        ),
        throwsStateError,
      );
    });
  });

  group('Calendar', () {
    test('event day overlap and json round-trip', () {
      final start = DateTime.utc(2026, 7, 15, 14, 0);
      final end = DateTime.utc(2026, 7, 15, 15, 30);
      final e = CalendarEvent(
        id: 'cal-1',
        title: 'Dinner',
        start: start,
        end: end,
        scope: CalendarScope.family,
        scopeId: 'family',
        creatorId: 'mom',
        creatorName: 'Mom',
        audienceIds: const ['mom', 'dad', 'kid'],
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      expect(e.overlapsDay(DateTime.utc(2026, 7, 15)), isTrue);
      expect(e.overlapsDay(DateTime.utc(2026, 7, 16)), isFalse);
      expect(e.scope.label, 'Family');

      final decoded = CalendarEvent.fromJson(e.toJson());
      expect(decoded.title, 'Dinner');
      expect(decoded.scope, CalendarScope.family);
      expect(decoded.audienceIds, containsAll(['mom', 'dad', 'kid']));
    });

    test('store scopes and wire upsert/delete', () {
      final s = CalendarStore();
      final personal = CalendarEvent(
        id: 'p1',
        title: 'Dentist',
        start: DateTime.utc(2026, 8, 1, 9),
        end: DateTime.utc(2026, 8, 1, 10),
        scope: CalendarScope.individual,
        scopeId: '',
        creatorId: 'me',
        creatorName: 'Me',
        updatedAt: DateTime.utc(2026, 7, 1),
      );
      final group = CalendarEvent(
        id: 'g1',
        title: 'Practice',
        start: DateTime.utc(2026, 8, 2, 18),
        end: DateTime.utc(2026, 8, 2, 19),
        scope: CalendarScope.group,
        scopeId: 'g-abc',
        creatorId: 'me',
        creatorName: 'Me',
        updatedAt: DateTime.utc(2026, 7, 2),
      );
      final org = CalendarEvent(
        id: 'o1',
        title: 'Town hall',
        start: DateTime.utc(2026, 8, 3, 12),
        end: DateTime.utc(2026, 8, 3, 13),
        scope: CalendarScope.organization,
        scopeId: 'org-1',
        creatorId: 'me',
        creatorName: 'Me',
        updatedAt: DateTime.utc(2026, 7, 3),
      );
      s.put(personal);
      s.put(group);
      s.put(org);
      expect(s.length, 3);
      expect(s.forScope(CalendarScope.group).single.title, 'Practice');
      expect(s.forDay(DateTime.utc(2026, 8, 1)).single.title, 'Dentist');
      expect(s.upcoming(from: DateTime.utc(2026, 8, 1, 8)), hasLength(3));

      final older = personal.copyWith(
        title: 'stale',
        updatedAt: DateTime.utc(2026, 6, 1),
      );
      s.put(older);
      expect(s['p1']!.title, 'Dentist'); // newer kept

      final upsert = CalendarWire.encodeUpsert(group);
      final upEv = CalendarWire.tryDecode(upsert)!;
      expect(upEv.type, CalendarWire.upsertType);
      expect(upEv.event!.title, 'Practice');

      final del = CalendarWire.encodeDelete(
        eventId: 'g1',
        byId: 'me',
        scope: 'group',
        scopeId: 'g-abc',
      );
      final delEv = CalendarWire.tryDecode(del)!;
      expect(delEv.type, CalendarWire.deleteType);
      expect(delEv.eventId, 'g1');

      final round = CalendarStore.fromJson(s.toJson());
      expect(round.length, 3);
      expect(round.forScope(CalendarScope.organization).single.scopeId, 'org-1');
    });

    test('scope parse aliases', () {
      expect(CalendarScope.parse('org'), CalendarScope.organization);
      expect(CalendarScope.parse('family'), CalendarScope.family);
      expect(CalendarScope.parse(null), CalendarScope.individual);
    });

    test('sync request wire and removeScope', () {
      final req = CalendarWire.encodeSyncRequest(
        scope: CalendarScope.group,
        scopeId: 'g-1',
        fromId: 'peer-a',
      );
      final ev = CalendarWire.tryDecode(req)!;
      expect(ev.type, CalendarWire.syncRequestType);
      expect(ev.requestScope, CalendarScope.group);
      expect(ev.requestScopeId, 'g-1');
      expect(ev.requestFromId, 'peer-a');

      final s = CalendarStore();
      s.put(
        CalendarEvent(
          id: 'a',
          title: 'A',
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 1, 1, 1),
          scope: CalendarScope.group,
          scopeId: 'g-1',
          creatorId: 'me',
          creatorName: 'Me',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      s.put(
        CalendarEvent(
          id: 'b',
          title: 'B',
          start: DateTime.utc(2026, 1, 2),
          end: DateTime.utc(2026, 1, 2, 1),
          scope: CalendarScope.group,
          scopeId: 'g-2',
          creatorId: 'me',
          creatorName: 'Me',
          updatedAt: DateTime.utc(2026, 1, 1),
        ),
      );
      expect(s.removeScope(CalendarScope.group, 'g-1'), 1);
      expect(s.length, 1);
      expect(s['b']!.title, 'B');
    });
  });


}

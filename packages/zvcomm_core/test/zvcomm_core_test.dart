import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

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
      // Place all in range of each other for Phase 0 full mesh flood.
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
  });

  group('DeviceIdentity', () {
    test('fromSeed is deterministic', () {
      final a = DeviceIdentity.fromSeed('test', displayName: 'T');
      final b = DeviceIdentity.fromSeed('test', displayName: 'T');
      expect(a.id, b.id);
      expect(a.publicKeyBytes, b.publicKeyBytes);
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
}

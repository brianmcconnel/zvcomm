import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:sim/sim.dart';
import 'package:test/test.dart';

void main() {
  group('SimCodec', () {
    test('round-trips frames', () {
      final codec = SimCodec();
      final frame = SimCodec.encode({'type': 'ping', 'n': 1});
      final msgs = codec.add(frame);
      expect(msgs, hasLength(1));
      expect(msgs.first['type'], 'ping');
      expect(msgs.first['n'], 1);
    });

    test('handles split frames', () {
      final codec = SimCodec();
      final frame = SimCodec.encode({'type': 'pong'});
      expect(codec.add(frame.sublist(0, 2)), isEmpty);
      final msgs = codec.add(frame.sublist(2));
      expect(msgs.single['type'], 'pong');
    });
  });

  group('SimHub + TcpSimTransport', () {
    late SimHub hub;
    late int port;

    setUp(() async {
      // Bind ephemeral port.
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = probe.port;
      await probe.close();
      hub = SimHub(
        address: InternetAddress.loopbackIPv4,
        port: port,
        log: (_) {},
      );
      await hub.start();
    });

    tearDown(() async {
      await hub.stop();
    });

    test('four nodes line topology delivers multi-hop chat', () async {
      // Positions: 0 -- 25 -- 50 -- 75, range 40 → line multi-hop.
      Future<({TcpSimTransport t, MeshNode n})> make(
        String id,
        double x,
      ) async {
        final t = TcpSimTransport(
          hubHost: '127.0.0.1',
          hubPort: port,
          localId: id,
          displayName: id,
          x: x,
          y: 0,
          rangeMeters: 40,
          log: (_) {},
        );
        await t.connectToHub();
        final n = MeshNode(
          localId: id,
          displayName: id,
          transports: TransportManager([t]),
          config: const MeshConfig(presenceInterval: Duration.zero),
        );
        await n.start();
        return (t: t, n: n);
      }

      final a = await make('alice', 0);
      final b = await make('bob', 25);
      final c = await make('carol', 50);
      final d = await make('dave', 75);

      // Wait for discovery graph to settle.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final got = d.n.messages
          .where((m) => m.kind == MessageKind.chat)
          .first
          .timeout(const Duration(seconds: 8));

      await a.n.sendChat('hello from alice across the line');

      final msg = await got;
      expect(utf8.decode(msg.payload), contains('hello from alice'));
      expect(msg.sourceId, 'alice');

      await a.n.dispose();
      await b.n.dispose();
      await c.n.dispose();
      await d.n.dispose();
      await a.t.dispose();
      await b.t.dispose();
      await c.t.dispose();
      await d.t.dispose();
    });
  });
}

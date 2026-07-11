import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:wifi/wifi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('WifiTransport is available via LAN fallback', () async {
    final t = WifiTransport();
    expect(t.kind, TransportKind.wifi);
    expect(await t.isAvailable(), isTrue);
    await t.dispose();
  });

  test('LanSoftApTransport discovers and delivers over loopback', () async {
    final a = LanSoftApTransport();
    final b = LanSoftApTransport();

    // Use unique ports if default collides — for CI we rely on SO_REUSEPORT.
    await a.startAdvertising(localId: 'lan-a', displayName: 'A');
    await b.startAdvertising(localId: 'lan-b', displayName: 'B');

    final peers = <Peer>[];
    final sub = a.discover().listen(peers.add);
    // B announces; A should see B.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    expect(peers.any((p) => p.id == 'lan-b'), isTrue);

    final bPeer = peers.firstWhere((p) => p.id == 'lan-b');
    final inbound = b.incomingConnections.first
        .timeout(const Duration(seconds: 3));

    final conn = await a.connect(bPeer);
    final remote = await inbound;

    final received = remote.incoming.first.timeout(const Duration(seconds: 2));
    await conn.send(Uint8List.fromList(utf8.encode('wifi-hi')));
    final msg = await received;
    expect(utf8.decode(msg), 'wifi-hi');

    await sub.cancel();
    await a.dispose();
    await b.dispose();
  });
}

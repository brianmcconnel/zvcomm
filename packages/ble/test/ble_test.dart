import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ble/ble.dart';
import 'package:core/core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BleTransport.unavailable reports not available', () async {
    final t = BleTransport.unavailable();
    expect(t.kind, TransportKind.ble);
    expect(await t.isAvailable(), isFalse);
    expect(t.capabilities.canDiscover, isTrue);
  });

  test('BleConnection frames through codec', () async {
    final sent = <Uint8List>[];
    final peer = Peer(
      id: 'p1',
      lastSeen: DateTime.now().toUtc(),
      transports: {TransportKind.ble},
    );
    final conn = BleConnection(
      peer: peer,
      writeChunk: (c) async => sent.add(c),
      onClose: () async {},
      maxChunk: () => 40,
    );
    conn.markOpen();

    final payload = Uint8List.fromList(List.generate(100, (i) => i & 0xff));
    await conn.send(payload);
    expect(sent, isNotEmpty);

    // Reassemble on peer side.
    final rx = BleConnection(
      peer: peer,
      writeChunk: (_) async {},
      onClose: () async {},
      maxChunk: () => 40,
    );
    rx.markOpen();
    final done = rx.incoming.first.timeout(const Duration(seconds: 1));
    for (final chunk in sent) {
      rx.deliverChunk(chunk);
    }
    final got = await done;
    expect(got, payload);
    await conn.close();
    await rx.close();
  });
}

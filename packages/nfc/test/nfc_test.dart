import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:nfc/nfc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NfcBootstrapPayload round-trips', () {
    final p = NfcBootstrapPayload(
      peerId: 'abc123',
      displayName: 'Phone',
      metadata: {'mesh': 'v1'},
      data: Uint8List.fromList(utf8.encode('hello')),
    );
    final restored = NfcBootstrapPayload.fromBytes(p.toBytes());
    expect(restored.peerId, 'abc123');
    expect(restored.displayName, 'Phone');
    expect(utf8.decode(restored.data!), 'hello');
    expect(restored.toPeer().transports, contains(TransportKind.nfc));
  });

  test('NfcBootstrapPayload carries PublicCredential', () async {
    final id = await DeviceIdentity.fromSeed('nfc-alice', displayName: 'Alice');
    final cred = await PublicCredential.fromIdentity(id);
    final p = NfcBootstrapPayload.forCredential(cred);
    final restored = NfcBootstrapPayload.fromBytes(p.toBytes());
    expect(restored.credential, isNotNull);
    expect(restored.credential!.subjectId, id.id);
    expect(restored.credential!.shortCode, cred.shortCode);
    expect(await restored.credential!.verify(), isTrue);
    expect(restored.toPeer().id, id.id);
    expect(restored.toPeer().metadata['shortCode'], cred.shortCode);
  });

  test('NfcTransport kind and capabilities', () async {
    final t = NfcTransport();
    expect(t.kind, TransportKind.nfc);
    expect(t.capabilities.typicalRangeMeters, 1);
    // On CI/desktop without NFC hardware this is typically false.
    final available = await t.isAvailable();
    expect(available, isA<bool>());
    await t.dispose();
  });
}

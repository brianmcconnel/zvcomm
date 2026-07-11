import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_nfc/zvcomm_nfc.dart';

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

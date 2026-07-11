import 'package:test/test.dart';
import 'package:zvcomm_nfc/zvcomm_nfc.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

void main() {
  test('NfcTransport is a stub that is unavailable', () async {
    final t = NfcTransport();
    expect(t.kind, TransportKind.nfc);
    expect(await t.isAvailable(), isFalse);
  });
}

import 'package:test/test.dart';
import 'package:zvcomm_ble/zvcomm_ble.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

void main() {
  test('BleTransport is a stub that is unavailable', () async {
    final t = BleTransport();
    expect(t.kind, TransportKind.ble);
    expect(await t.isAvailable(), isFalse);
  });
}

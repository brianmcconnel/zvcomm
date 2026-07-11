import 'package:test/test.dart';
import 'package:zvcomm_wifi/zvcomm_wifi.dart';
import 'package:zvcomm_core/zvcomm_core.dart';

void main() {
  test('WifiTransport is a stub that is unavailable', () async {
    final t = WifiTransport();
    expect(t.kind, TransportKind.wifi);
    expect(await t.isAvailable(), isFalse);
  });
}

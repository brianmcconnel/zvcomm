import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

void main() {
  test('layoutPeerMap places RSSI peers with stable angles', () {
    final peers = [
      Peer(
        id: 'alice',
        displayName: 'Alice',
        lastSeen: DateTime.now().toUtc(),
        rssi: -40,
        transports: {TransportKind.ble},
      ),
      Peer(
        id: 'bob',
        displayName: 'Bob',
        lastSeen: DateTime.now().toUtc(),
        rssi: -80,
        transports: {TransportKind.wifi},
      ),
    ];
    final a = layoutPeerMap(peers);
    expect(a, hasLength(2));
    expect(a[0].label, 'Alice');
    // Stronger RSSI → closer to origin.
    expect(a[0].position.distance, lessThan(a[1].position.distance));
    // Stable across calls.
    final b = layoutPeerMap(peers);
    expect(a[0].position, b[0].position);
  });

  test('layoutPeerMap uses metadata x/y when present', () {
    final peers = [
      Peer(
        id: 'a',
        displayName: 'A',
        lastSeen: DateTime.now().toUtc(),
        metadata: const {'x': '0', 'y': '0'},
      ),
      Peer(
        id: 'b',
        displayName: 'B',
        lastSeen: DateTime.now().toUtc(),
        metadata: const {'x': '10', 'y': '0'},
      ),
    ];
    final m = layoutPeerMap(peers);
    expect(m.every((e) => e.hasKnownPosition), isTrue);
    // Relative layout: not both on origin after normalize.
    expect((m[0].position - m[1].position).distance, greaterThan(0.1));
  });
}

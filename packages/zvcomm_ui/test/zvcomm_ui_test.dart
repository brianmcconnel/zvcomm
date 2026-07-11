import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvcomm_core/zvcomm_core.dart';
import 'package:zvcomm_ui/zvcomm_ui.dart';

void main() {
  testWidgets('PeerListView shows empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PeerListView(peers: []),
        ),
      ),
    );
    expect(find.textContaining('No peers'), findsOneWidget);
  });

  testWidgets('PeerListView lists peers', (tester) async {
    final peers = [
      Peer(
        id: 'abc',
        displayName: 'Alice',
        transports: {TransportKind.mock},
        lastSeen: DateTime.utc(2026, 1, 1),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PeerListView(peers: peers),
        ),
      ),
    );
    expect(find.text('Alice'), findsOneWidget);
  });
}

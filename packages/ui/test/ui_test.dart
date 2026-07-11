import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:ui/ui.dart';

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

  test('all ZVBible-aligned themes build', () {
    expect(ZvcommTheme.all, hasLength(13));
    expect(ZvcommTheme.byId('dark').id, 'dark');
    expect(ZvcommTheme.byId('ocean').accent, const Color(0xFF2DD4BF));
    for (final p in ZvcommTheme.all) {
      final theme = p.toThemeData();
      expect(theme.colorScheme.primary, p.accent);
      expect(theme.scaffoldBackgroundColor, p.bgApp);
    }
  });

  testWidgets('ZvcommTitle paints gradient wordmark', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ZvcommTheme.dark(),
        home: const Scaffold(
          body: Center(child: ZvcommTitle.appBar()),
        ),
      ),
    );
    expect(find.text('ZVComm'), findsOneWidget);
    expect(find.byType(ShaderMask), findsOneWidget);
  });
}

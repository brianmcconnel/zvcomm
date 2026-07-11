import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('app boots to peers shell with navigation', (tester) async {
    await tester.pumpWidget(const ZvcommApp());
    await tester.pump();

    // Wait for async identity generation + mesh bootstrap.
    var found = false;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
      if (find.text('ZVComm').evaluate().isNotEmpty) {
        found = true;
        break;
      }
    }
    expect(found, isTrue, reason: 'app did not leave loading state');

    expect(find.text('Local identity'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);

    await tester.tap(find.text('Chat'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Broadcast'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

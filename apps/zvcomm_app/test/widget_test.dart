import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zvcomm_app/main.dart';

void main() {
  testWidgets('app shows ZVComm title and local identity', (tester) async {
    await tester.pumpWidget(const ZvcommApp());
    await tester.pump(); // schedule bootstrap
    // Allow async key generation + discovery start.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('ZVComm'), findsOneWidget);
    expect(find.text('Local identity'), findsOneWidget);
    expect(find.textContaining('Discovered peers'), findsOneWidget);

    // Tear down widget tree so MockTransport discovery timers are cancelled.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

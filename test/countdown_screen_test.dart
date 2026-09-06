import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anno/ui/countdown_screen.dart';
import 'package:anno/ui/theme.dart';

void main() {
  testWidgets('counts down and reports that it ran through', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const CountdownScreen(),
                  ),
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.text('3'), findsOneWidget);
    // One second per pump: settling in between would run the clock past the
    // next tick and skip a number.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.text('start'), findsOneWidget);
    // Nothing is given away while the group waits for the song.
    expect(find.text('2005'), findsNothing);
  });

  testWidgets('cancelling reports that the round was dropped', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute<bool>(
                    builder: (_) => const CountdownScreen(),
                  ),
                );
              },
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(find.text('start'), findsOneWidget);
  });
}

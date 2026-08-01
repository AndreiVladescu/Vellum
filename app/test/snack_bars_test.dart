// Snack bars have to go away by themselves.
//
// `SnackBar.persist` defaults to `action != null`, and the dismiss timer
// returns early when it is set, so every snack bar with a button used to sit at
// the bottom of the window until it was swiped away. The wrapper fixes it; this
// checks both that it works and that nothing has gone back to building a
// SnackBar with an action directly.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/snack_bars.dart';

void main() {
  testWidgets('one with an action dismisses itself', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      })),
    ));

    ScaffoldMessenger.of(ctx).showSnackBar(appSnackBar(
      content: const Text('Moved to the trash'),
      action: SnackBarAction(label: 'Undo', onPressed: () {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Moved to the trash'), findsOneWidget);

    // Long enough to reach the button, and then gone.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Moved to the trash'), findsOneWidget,
        reason: 'four seconds is not long enough to notice and press a button');
    await tester.pump(actionSnackDuration);
    await tester.pumpAndSettle();
    expect(find.text('Moved to the trash'), findsNothing);
  });

  testWidgets('a plain one keeps the usual four seconds', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      })),
    ));

    ScaffoldMessenger.of(ctx)
        .showSnackBar(appSnackBar(content: const Text('Saved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('tapping the message dismisses it', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      })),
    ));

    ScaffoldMessenger.of(ctx)
        .showSnackBar(appSnackBar(content: const Text('Moved to the trash')));
    await tester.pumpAndSettle();
    expect(find.text('Moved to the trash'), findsOneWidget);

    await tester.tap(find.text('Moved to the trash'));
    await tester.pumpAndSettle();
    expect(find.text('Moved to the trash'), findsNothing,
        reason: 'a tap on the message should get rid of it');
  });

  testWidgets('tapping the action does the action, and does not just dismiss',
      (tester) async {
    // The one thing this must not break: the dismiss gesture wraps the
    // *message*, not the bar, so "Undo" still undoes.
    late BuildContext ctx;
    var undone = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) {
        ctx = context;
        return const SizedBox();
      })),
    ));

    ScaffoldMessenger.of(ctx).showSnackBar(appSnackBar(
      content: const Text('Moved to the trash'),
      action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(undone, isTrue, reason: 'the tap swallowed the action');
    expect(find.text('Moved to the trash'), findsNothing);
  });

  test('nothing builds a SnackBar with an action directly', () {
    // The trap is silent — a bare `SnackBar(action: ...)` looks perfectly
    // ordinary and simply never goes away — so it is worth catching in the
    // source rather than waiting to notice it on screen.
    // `appSnackBar(` ends in `SnackBar(`, so a plain search finds the wrapper's
    // own name and reports every converted call site. The boundary is the whole
    // point of the check.
    final bareCall = RegExp(r'(?<![A-Za-z])SnackBar\(');
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      // The wrapper is where the one legitimate `SnackBar(action:)` lives.
      if (file.path.endsWith('snack_bars.dart')) continue;
      final source = file.readAsStringSync();
      for (final match in 'SnackBarAction'.allMatches(source)) {
        // Walk back to whichever constructor this action belongs to.
        final before = source.substring(0, match.start);
        final bare = bareCall.allMatches(before).lastOrNull?.start ?? -1;
        final wrapped = before.lastIndexOf('appSnackBar(');
        if (bare > wrapped) {
          final line = '\n'.allMatches(before).length + 1;
          offenders.add('${file.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use appSnackBar() so these dismiss themselves: $offenders');
  });
}

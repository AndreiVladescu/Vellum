// First-run onboarding (plan 5 #41). The behaviour that matters is restraint:
// shown once, dismissible in every direction, and never shown again afterwards —
// including when the user swiped it away without choosing anything.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/onboarding/first_run_sheet.dart';
import 'package:vellum/settings/app_settings.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Pumps a host that opens the sheet on first frame and records the result.
  Future<({List<FirstRunAction?> results, AppSettingsStore settings})> open(
    WidgetTester tester,
  ) async {
    late AppSettingsStore settings;
    await tester.runAsync(() async {
      settings = await AppSettingsStore.load();
    });
    final results = <FirstRunAction?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async =>
                  results.add(await FirstRunSheet.maybeShow(context, settings)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return (results: results, settings: settings);
  }

  testWidgets('the first card offers the three ways to add books',
      (tester) async {
    await open(tester);

    expect(find.text('Welcome to Vellum'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Import a folder'), findsOneWidget);
    expect(find.text('Scan a barcode'), findsOneWidget);
    expect(find.text('Add one book'), findsOneWidget);
  });

  testWidgets('Next walks the three cards and Done closes', (tester) async {
    final t = await open(tester);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a server?'), findsOneWidget);
    expect(find.textContaining('skip this forever'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Set up a room?'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Vellum'), findsNothing);
    expect(t.results.single, isNull, reason: 'walked through without choosing');
  });

  testWidgets('a choice is reported back to the caller', (tester) async {
    final t = await open(tester);

    await tester.tap(find.text('Scan a barcode'));
    await tester.pumpAndSettle();

    expect(t.results.single, FirstRunAction.scan);
  });

  testWidgets('Skip closes it without a choice', (tester) async {
    final t = await open(tester);

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Vellum'), findsNothing);
    expect(t.results.single, isNull);
  });

  testWidgets('it is never shown a second time', (tester) async {
    final t = await open(tester);
    expect(t.settings.hasSeenFirstRun, true,
        reason: 'marked seen as soon as it opens, not when it completes');

    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();

    // Ask again, as the next launch would.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Vellum'), findsNothing);
    expect(t.results, [null, null]);
  });

  testWidgets('a returning user never sees it at all', (tester) async {
    SharedPreferences.setMockInitialValues({'settings.hasSeenFirstRun': true});
    final t = await open(tester);

    expect(find.text('Welcome to Vellum'), findsNothing);
    expect(t.results.single, isNull);
  });
}

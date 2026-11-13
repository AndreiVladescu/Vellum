import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/stats/goals_dialog.dart';
import 'package:vellum/stats/reading_goals.dart';

/// Opens the goals dialog from a button and returns the store it saves into.
Future<AppSettingsStore> _openDialog(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final settings = (await tester.runAsync(AppSettingsStore.load))!;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showGoalsDialog(context, settings),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // The first "Other" chip is the books picker's: it opens the custom field.
  await tester.tap(find.text('Other').first);
  await tester.pumpAndSettle();
  return settings;
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField).first).controller!.text;

void main() {
  testWidgets('a custom goal over the maximum shows the clamped value once '
      'the field is left, and is saved clamped', (tester) async {
    final settings = await _openDialog(tester);
    final max = ReadingGoals.maxBooks;

    await tester.enterText(find.byType(TextField).first, '${max + 500}');
    await tester.pump();
    // While typing, the text is left alone.
    expect(_fieldText(tester), '${max + 500}');

    // Leaving the field applies the clamp to what is shown.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(_fieldText(tester), '$max');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.readingGoalBooks, max);
  });

  testWidgets('submitting the field also shows the clamped value', (
    tester,
  ) async {
    await _openDialog(tester);
    final max = ReadingGoals.maxBooks;

    await tester.enterText(find.byType(TextField).first, '${max + 1}');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(_fieldText(tester), '$max');
  });
}

// Localization scaffolding (plan 5 #38).
//
// English is the only locale shipped, so these can't test a *translation*.
// What they can test — and what actually breaks in a half-done i18n retrofit —
// is that lookups resolve through the delegates at all, that plurals are ICU
// rather than a hand-built `'$n thing${n == 1 ? '' : 's'}'`, and that the
// generated code is in step with the ARB.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

/// Pumps a minimal app with the real delegates, and hands the lookup back.
Future<L10n> _l10n(WidgetTester tester, {Locale locale = const Locale('en')}) async {
  late L10n found;
  await tester.pumpWidget(MaterialApp(
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Builder(builder: (context) {
      found = L10n.of(context);
      return const SizedBox.shrink();
    }),
  ));
  return found;
}

void main() {
  testWidgets('a looked-up string resolves through the delegates', (tester) async {
    final l10n = await _l10n(tester);
    expect(l10n.addBook, 'Add book');
    expect(l10n.searchHint, 'Search your library…');
  });

  testWidgets('placeholders are substituted, not printed', (tester) async {
    final l10n = await _l10n(tester);
    expect(l10n.noBooksMatch('dune'), 'No books match “dune”.');
    expect(l10n.bookAdded('Dune'), '“Dune” added to your shelf');
    expect(l10n.syncResult(3, 4), 'Synced — pulled 3, pushed 4.');
    expect(
      l10n.noBooksInGenreMatch('Sci-fi', 'dune'),
      'No “Sci-fi” books match “dune”.',
    );
  });

  testWidgets('plurals are ICU, so one is not "1 issues"', (tester) async {
    // The exact bug this item exists to remove: the app used to build these by
    // hand as `'$n issue${n == 1 ? '' : 's'}'`, which no other language
    // survives. The assertion is about English only because English is all we
    // ship — the *mechanism* is what has to be right.
    final l10n = await _l10n(tester);
    expect(l10n.syncIssues(1), '1 issue');
    expect(l10n.syncIssues(2), '2 issues');
    expect(l10n.syncIssues(0), '0 issues');
    expect(l10n.newFilesInWatchedFolder(1), '1 new file in your watched folder.');
    expect(
      l10n.newFilesInWatchedFolder(7),
      '7 new files in your watched folder.',
    );
  });

  testWidgets('an unsupported locale falls back to English rather than failing',
      (tester) async {
    // A phone set to Romanian must not show a blank app while Vellum ships one
    // locale; `supportedLocales` resolution is what guarantees that.
    final l10n = await _l10n(tester, locale: const Locale('ro'));
    expect(l10n.addBook, 'Add book');
  });

  test('every ARB message has an entry in the generated English class', () {
    // Catches the drift that makes a retrofit rot: adding a message to the ARB
    // and forgetting to re-run `flutter gen-l10n`, so the getter never appears
    // and the string quietly stays hardcoded at its call site.
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final generated = File('lib/l10n/gen/app_localizations.dart').readAsStringSync();

    final missing = <String>[];
    for (final key in arb.keys) {
      if (key.startsWith('@')) continue; // metadata, not a message
      // Getters appear as `String get key`, messages as `String key(`.
      if (!generated.contains('get $key') && !generated.contains('String $key(')) {
        missing.add(key);
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'run `flutter gen-l10n` — these ARB messages have no generated '
          'accessor: ${missing.join(', ')}',
    );
  });

  test('no message is left untranslated in the template locale', () {
    // `untranslated.json` is written by gen_l10n. For the template locale it
    // must stay empty; a non-empty file here means a message was added to a
    // *translation* the template doesn't have.
    final file = File('lib/l10n/untranslated.json');
    if (!file.existsSync()) return;
    final raw = file.readAsStringSync().trim();
    if (raw.isEmpty) return;
    expect(jsonDecode(raw), isEmpty, reason: raw);
  });
}

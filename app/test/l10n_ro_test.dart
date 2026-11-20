// The Romanian translation: complete, structurally faithful, and pluralised by
// Romanian's own rules rather than English's.
//
// The parity checks read the ARB files rather than the generated classes, so a
// message that is missing from app_ro.arb fails here instead of silently
// falling back to English at runtime. They run over every translation in
// lib/l10n/, so a new language gets the same guard for free.
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/l10n/delegates.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

Map<String, dynamic> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Names used as arguments in an ICU message: `{name}` or `{name, plural, …}`.
Set<String> _arguments(String message) => RegExp(r'\{\s*(\w+)\s*[},]')
    .allMatches(message)
    .map((m) => m.group(1)!)
    .toSet();

/// The case keys of every `select` in [message], by argument name.
Map<String, Set<String>> _selectCases(String message) {
  final out = <String, Set<String>>{};
  for (final m in RegExp(r'\{\s*(\w+)\s*,\s*select\s*,').allMatches(message)) {
    final cases = <String>{};
    var depth = 1;
    final key = StringBuffer();
    for (var i = m.end; i < message.length && depth > 0; i++) {
      final c = message[i];
      if (c == '{') {
        if (depth == 1) {
          cases.add(key.toString().trim());
          key.clear();
        }
        depth++;
      } else if (c == '}') {
        depth--;
      } else if (depth == 1) {
        key.write(c);
      }
    }
    out[m.group(1)!] = cases;
  }
  return out;
}

Future<L10n> _ro(WidgetTester tester) async {
  late L10n found;
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ro'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Builder(builder: (context) {
      found = L10n.of(context);
      return const SizedBox.shrink();
    }),
  ));
  return found;
}

void main() {
  final template = _arb('lib/l10n/app_en.arb');
  final messages = template.keys.where((k) => !k.startsWith('@')).toList();
  final translations = Directory('lib/l10n')
      .listSync()
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.arb') && !p.endsWith('app_en.arb'))
      .toList()
    ..sort();

  test('Romanian is one of the translations checked', () {
    expect(translations.any((p) => p.endsWith('app_ro.arb')), isTrue);
  });

  for (final path in translations) {
    final arb = _arb(path);

    test('$path has every message of the template', () {
      final missing = messages.where((k) => !arb.containsKey(k)).toList();
      final extra = arb.keys
          .where((k) => !k.startsWith('@') && !template.containsKey(k))
          .toList();
      expect(missing, isEmpty, reason: 'missing from $path');
      expect(extra, isEmpty, reason: 'not in app_en.arb, so never shown');
    });

    test('$path keeps every placeholder and select case', () {
      final problems = <String>[];
      for (final key in messages) {
        final translated = arb[key];
        if (translated is! String) continue; // reported by the test above
        final english = template[key] as String;
        final meta = template['@$key'] as Map<String, dynamic>? ?? const {};
        final declared =
            (meta['placeholders'] as Map<String, dynamic>? ?? const {}).keys
                .toSet();
        // Words inside select cases look like `{word}` too; only the declared
        // placeholders are arguments.
        final names = declared.isEmpty ? _arguments(english) : declared;
        final want = _arguments(english).intersection(names);
        final got = _arguments(translated).intersection(names);
        if (want.length != got.length || !want.containsAll(got)) {
          problems.add('$key: placeholders $want, translation has $got');
        }
        final wantCases = _selectCases(english);
        final gotCases = _selectCases(translated);
        for (final entry in wantCases.entries) {
          final cases = gotCases[entry.key];
          if (cases == null ||
              cases.length != entry.value.length ||
              !cases.containsAll(entry.value)) {
            problems.add('$key: select ${entry.key} needs ${entry.value}, '
                'translation has $cases');
          }
        }
        if (RegExp(r'plural\s*,').hasMatch(translated) &&
            !translated.contains('other{')) {
          problems.add('$key: a plural needs an `other` case');
        }
      }
      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  }

  test('every Android string has a Romanian values-ro entry', () {
    // Launcher shortcuts and the home-screen widget are Android resources,
    // read before Flutter starts, so the ARB checks above cannot see them.
    Set<String> names(String path) => RegExp(r'<string name="(\w+)"')
        .allMatches(File(path).readAsStringSync())
        .map((m) => m.group(1)!)
        .toSet();
    const res = 'android/app/src/main/res';
    final english = names('$res/values/strings.xml');
    final romanian = names('$res/values-ro/strings.xml');
    expect(english.difference(romanian), isEmpty);
    expect(romanian.difference(english), isEmpty);
  });

  test('Romanian uses comma-below ș ț, never the cedilla forms', () {
    final raw = File('lib/l10n/app_ro.arb').readAsStringSync();
    final bad = RegExp('[şţŞŢ]').allMatches(raw).length;
    expect(bad, 0, reason: 'ş/ţ are Turkish letters; use ș/ț (U+0219/U+021B)');
  });

  test('Romanian quotes are „…”, not English “…”', () {
    final arb = _arb('lib/l10n/app_ro.arb');
    final english = [
      for (final k in messages)
        if ((arb[k] as String? ?? '').contains('“')) k,
    ];
    expect(english, isEmpty);
  });

  testWidgets('plurals follow the CLDR rule for Romanian', (tester) async {
    // one: 1 · few: 0, 2–19 and n % 100 in 1–19 · other: the rest, which is
    // where Romanian puts "de" ("20 de cărți").
    final l10n = await _ro(tester);
    expect(l10n.libraryStatsTotal(0), '0 cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(1), '1 carte în bibliotecă');
    expect(l10n.libraryStatsTotal(2), '2 cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(19), '19 cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(20), '20 de cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(101), '101 cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(119), '119 cărți în bibliotecă');
    expect(l10n.libraryStatsTotal(120), '120 de cărți în bibliotecă');

    expect(l10n.syncIssues(0), '0 probleme');
    expect(l10n.syncIssues(1), '1 problemă');
    expect(l10n.syncIssues(2), '2 probleme');
    expect(l10n.syncIssues(19), '19 probleme');
    expect(l10n.syncIssues(20), '20 de probleme');
    expect(l10n.syncIssues(101), '101 probleme');

    expect(l10n.detailPages(1), '1 pagină');
    expect(l10n.detailPages(20), '20 de pagini');
    expect(l10n.detailRatingStars(5), '5 stele');
    expect(l10n.copiesCount(2), '2 exemplare fizice');
    expect(l10n.copiesCount(25), '25 de exemplare fizice');

    // An explicit =0 case wins over `few`.
    expect(l10n.insightsDayPages(0), 'Nicio pagină înregistrată');
    expect(l10n.insightsDayPages(3), '3 pagini');
  });

  testWidgets('selects and placeholders survive translation', (tester) async {
    final l10n = await _ro(tester);
    expect(l10n.readGoTo('page', 12), 'Mergi la pagina 12');
    expect(l10n.readGoTo('chapter', 3), 'Mergi la capitolul 3');
    expect(l10n.bookAdded('Dune'), 'Ai adăugat „Dune” pe raft');
    expect(
      l10n.readFilePosition('PDF', 'page', 214, 38),
      'PDF · pagina 214 (38 %)',
    );
  });

  testWidgets('dates in messages are formatted for Romanian', (tester) async {
    final l10n = await _ro(tester);
    expect(l10n.insightsBestDayDate(DateTime(2026, 3, 4)), '4 mar. 2026');
    expect(l10n.monthHeading(DateTime(2026, 11)), 'noiembrie 2026');
    expect(
      l10n.monthCompareTitle(DateTime(2026, 10)),
      'Comparativ cu octombrie',
    );
  });
}

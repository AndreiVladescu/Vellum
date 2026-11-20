// Dates and numbers follow the system's region when it speaks the app's
// language: plain "en" alone is American, which is wrong in London or Dublin.
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vellum/l10n/formats.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  final day = DateTime(2026, 11, 20, 14, 5);

  setUpAll(() => initializeDateFormatting());
  tearDown(() => debugSystemLocale = null);

  test('English on a British system writes the date the British way', () {
    debugSystemLocale = const Locale('en', 'GB');
    final l10n = lookupL10n(const Locale('en'));
    expect(l10n.formatDate(day), '20/11/2026');
    expect(l10n.formatDateTime(day), contains('14:05'));
  });

  test('English on an American system keeps the American date', () {
    debugSystemLocale = const Locale('en', 'US');
    expect(lookupL10n(const Locale('en')).formatDate(day), '11/20/2026');
  });

  test('Romanian on a Romanian system', () {
    debugSystemLocale = const Locale('ro', 'RO');
    final l10n = lookupL10n(const Locale('ro'));
    expect(l10n.formatDate(day), '20.11.2026');
    expect(l10n.formatDecimal(1.5), '1,5');
  });

  test('a language chosen in Preferences ignores another language region', () {
    // Romanian system, English chosen in the app: the English default, not a
    // Romanian date with English words around it.
    debugSystemLocale = const Locale('ro', 'RO');
    expect(lookupL10n(const Locale('en')).formatDate(day), '11/20/2026');
  });

  test('a system locale with no region uses the language alone', () {
    debugSystemLocale = const Locale('en');
    expect(lookupL10n(const Locale('en')).formatDate(day), '11/20/2026');
  });
}

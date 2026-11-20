// The language choice on Preferences → Appearance: stored per device, followed
// by MaterialApp, and by the code that posts notifications with no widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/l10n/platform_l10n.dart';
import 'package:vellum/settings/app_settings.dart';

void main() {
  Future<AppSettingsStore> store([Map<String, Object> initial = const {}]) {
    SharedPreferences.setMockInitialValues(initial);
    return AppSettingsStore.load();
  }

  tearDown(() => chosenLocale = null);

  test('defaults to following the system', () async {
    final s = await store();
    expect(s.appLocale, isNull);
    expect(chosenLocale, isNull);
  });

  test('a chosen language round-trips and reaches platformL10n', () async {
    final s = await store();
    await s.setAppLocale(const Locale('ro'));
    expect(s.appLocale, const Locale('ro'));
    expect(platformL10n().localeName, 'ro');
    expect(platformL10n().addBook, 'Adaugă carte');

    final reloaded = await store({'settings.language': 'ro'});
    expect(reloaded.appLocale, const Locale('ro'));
    expect(chosenLocale, const Locale('ro'), reason: 'load() restores it');

    await reloaded.setAppLocale(null);
    expect(reloaded.appLocale, isNull);
    expect(chosenLocale, isNull);
  });

  test('a stored language the app no longer ships means system', () async {
    final s = await store({'settings.language': 'xx'});
    expect(s.appLocale, isNull);
  });

  test('every shipped language names itself', () {
    final names = {
      for (final locale in L10n.supportedLocales)
        locale.languageCode: lookupL10n(locale).languageName,
    };
    expect(names['en'], 'English');
    expect(names['ro'], 'Română');
    expect(names.values.toSet().length, names.length,
        reason: 'two languages with the same endonym cannot be told apart');
  });
}

// The app's language for code that has no widget tree to ask.
//
// A screen gets its language from `L10n.of(context)`. The status-bar
// notifications are posted from places that have no context at all — the
// Android background-sync isolate (`server/background_sync.dart`) never builds
// a widget — so they resolve it the way the framework does at startup: the
// language chosen in Preferences if there is one, else the platform's preferred
// locales against the languages in `lib/l10n/`.
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

Locale? _chosen;

/// The language picked in Preferences, or null to follow the system.
/// [AppSettingsStore] keeps this in step with what it stores, in every isolate
/// that loads it, so [platformL10n] answers what the screens show.
Locale? get chosenLocale => _chosen;
set chosenLocale(Locale? value) => _chosen = supportedLocaleFor(value?.languageCode);

/// The supported locale for a language code, or null when Vellum has no file
/// for it (or [code] is null), which means "follow the system".
Locale? supportedLocaleFor(String? code) {
  if (code == null || code.isEmpty) return null;
  for (final locale in L10n.supportedLocales) {
    if (locale.languageCode == code) return locale;
  }
  return null;
}

/// The localizations for the app's language, English when nothing matches.
L10n platformL10n() {
  try {
    final locale = _chosen ??
        basicLocaleListResolution(
          PlatformDispatcher.instance.locales,
          L10n.supportedLocales,
        );
    return lookupL10n(locale);
  } catch (_) {
    return lookupL10n(const Locale('en'));
  }
}

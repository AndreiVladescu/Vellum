// The app's language for code that has no widget tree to ask.
//
// A screen gets its language from `L10n.of(context)`. The status-bar
// notifications are posted from places that have no context at all — the
// Android background-sync isolate (`server/background_sync.dart`) never builds
// a widget — so they resolve it the way the framework does at startup: the
// platform's preferred locales against the languages in `lib/l10n/`. Vellum has
// no in-app language setting, so this is the same answer a screen would get.
import 'dart:ui';

import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

/// The localizations for the platform's language, English when none matches.
L10n platformL10n() {
  try {
    final locale = basicLocaleListResolution(
      PlatformDispatcher.instance.locales,
      L10n.supportedLocales,
    );
    return lookupL10n(locale);
  } catch (_) {
    return lookupL10n(const Locale('en'));
  }
}

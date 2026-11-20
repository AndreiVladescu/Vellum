// The localizations every MaterialApp in Vellum is given.
//
// gen-l10n's own `L10n.localizationsDelegates` pairs the app's strings with
// flutter_localizations' Material and Cupertino delegates. Since Flutter 3.50
// the widgets come from package:material_ui, which looks its localizations up
// by its own types, so those delegates would load and never be read, and the
// framework's own strings and date formats (pickers, tooltips, menus) would
// fall back to material_ui's built-in US-English defaults. This is the same
// list with material_ui's delegates instead (its `delegates` covers Material,
// Cupertino and Widgets).
import 'package:material_ui/material_ui.dart';

import 'gen/app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates = [
  L10n.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

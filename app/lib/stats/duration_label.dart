import '../l10n/gen/app_localizations.dart';

/// "45m", "3h" or "3h 20m" — minutes alone stop being readable well before a
/// lifetime total does. Shared by the insights page and the book page so a
/// duration reads the same everywhere; the three shapes are translatable
/// messages rather than string pieces, so a language can order them its way.
String formatMinutes(L10n l10n, int minutes) {
  if (minutes < 60) return l10n.insightsMinutesShort(minutes);
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? l10n.insightsHoursShort(hours)
      : l10n.insightsHoursMinutesShort(hours, rest);
}

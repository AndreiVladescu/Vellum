// Dates, numbers and sizes in the reader's language.
//
// A message in the ARB can format its own DateTime or number placeholder, but a
// lot of what the app shows is a value on its own (a stat tile's "12 345", a
// file's "3,2 MB") or a String placeholder filled with a value formatted first.
// Those all come through here, so "20.11.2026" and "1,5" in Romanian and
// "11/20/2026" and "1.5" in English are intl's answer for the active locale
// rather than something written out by hand.
//
// These are extension methods on [L10n] (Dart lets you add methods to a class
// you do not own): `l10n.formatDate(d)` reads like the message lookups next to
// it, and `l10n.localeName` is the locale the lookup itself resolved to.
import 'package:intl/intl.dart';

import 'gen/app_localizations.dart';

extension L10nFormats on L10n {
  /// A calendar date, short and numeric: 20.11.2026, 11/20/2026.
  String formatDate(DateTime moment) {
    final local = moment.toLocal();
    try {
      return DateFormat.yMd(localeName).format(local);
    } catch (_) {
      // Date symbols are loaded by the Material localizations delegate. Code
      // that runs with no widget tree (a background isolate) may not have
      // them; ISO is better than a crash there.
      return DateFormat('yyyy-MM-dd').format(local);
    }
  }

  /// A date with its time of day: 20.11.2026, 14:05 / 11/20/2026, 2:05 PM.
  String formatDateTime(DateTime moment) {
    final local = moment.toLocal();
    try {
      return DateFormat.yMd(localeName).add_jm().format(local);
    } catch (_) {
      return DateFormat('yyyy-MM-dd HH:mm').format(local);
    }
  }

  /// A whole number with the locale's grouping: 12 345 → "12.345", "12,345".
  String formatInt(num value) =>
      NumberFormat.decimalPattern(localeName).format(value.round());

  /// A number with exactly [digits] decimals: 1.5 → "1,5" in Romanian.
  String formatDecimal(num value, {int digits = 1}) =>
      NumberFormat.decimalPatternDigits(locale: localeName, decimalDigits: digits)
          .format(value);

  /// A number with up to [maxDigits] decimals and no trailing zeros, for
  /// readouts such as a speed: 1 → "1", 1.25 → "1,25".
  String formatCompactDecimal(num value, {int maxDigits = 2}) {
    final f = NumberFormat.decimalPattern(localeName)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = maxDigits;
    return f.format(value);
  }

  /// A fraction as a percentage: 0.42 → "42 %" (Romanian), "42%" (English).
  String formatPercent(num fraction) =>
      NumberFormat.percentPattern(localeName).format(fraction);

  /// A byte count as KB, MB or GB (binary multiples, one decimal above KB).
  String formatFileSize(int bytes) {
    const kb = 1024;
    if (bytes < kb) return '${formatInt(bytes)} B';
    if (bytes < kb * kb) return '${formatInt(bytes / kb)} KB';
    if (bytes < kb * kb * kb) return '${formatDecimal(bytes / (kb * kb))} MB';
    return '${formatDecimal(bytes / (kb * kb * kb))} GB';
  }
}

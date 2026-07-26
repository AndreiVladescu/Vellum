/// ISBN and EAN-13 handling for barcode scanning (plan 5 #16).
///
/// A scanner reads whatever barcode is in front of it — a cereal box, a
/// bookshop's own price sticker, a magazine's ISSN. Validating here is what
/// keeps a continuous scan from firing off a metadata lookup (and a "not found"
/// dead end) for every non-book barcode that drifts through the frame.
library;

/// Strips separators and upper-cases the check digit. Returns the bare digits
/// (possibly with a trailing `X`), or an empty string if nothing usable is left.
String normalizeIsbnInput(String raw) =>
    raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();

/// Whether [digits] is a structurally valid ISBN-13: 13 digits, a `978`/`979`
/// Bookland prefix, and a correct EAN-13 check digit.
///
/// The prefix test is what separates a book from every other EAN-13 product
/// code, and `979-0` (sheet music, "ISMN") is excluded with it.
bool isValidIsbn13(String digits) {
  if (digits.length != 13 || !RegExp(r'^\d{13}$').hasMatch(digits)) return false;
  if (!digits.startsWith('978') && !digits.startsWith('979')) return false;
  if (digits.startsWith('9790')) return false; // ISMN — sheet music, not a book
  return _ean13CheckDigit(digits.substring(0, 12)) ==
      int.parse(digits[12]);
}

/// Whether [value] is a valid ISBN-10 (9 digits plus a 0–9/X check digit).
bool isValidIsbn10(String value) {
  final digits = normalizeIsbnInput(value);
  if (digits.length != 10) return false;
  if (!RegExp(r'^\d{9}[0-9X]$').hasMatch(digits)) return false;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += (10 - i) * int.parse(digits[i]);
  }
  sum += digits[9] == 'X' ? 10 : int.parse(digits[9]);
  return sum % 11 == 0;
}

/// The EAN-13 check digit for a 12-digit body: weights alternate 1 and 3.
int _ean13CheckDigit(String body) {
  var sum = 0;
  for (var i = 0; i < body.length; i++) {
    sum += int.parse(body[i]) * (i.isEven ? 1 : 3);
  }
  return (10 - sum % 10) % 10;
}

/// Converts a valid ISBN-10 to its ISBN-13 form, or returns null if [value]
/// isn't one. Metadata sources index both, but normalising to 13 means one
/// comparison key for duplicate detection.
String? isbn10To13(String value) {
  if (!isValidIsbn10(value)) return null;
  final body = '978${normalizeIsbnInput(value).substring(0, 9)}';
  return '$body${_ean13CheckDigit(body)}';
}

/// The ISBN-13 form of any accepted input (a scanned EAN-13 or a typed
/// ISBN-10), or null when the input is not a book identifier at all.
///
/// The single entry point callers should use: it accepts what a human would
/// type (hyphens, spaces, a trailing `x`) and rejects what a scanner picks up
/// off a non-book.
String? toIsbn13(String raw) {
  final digits = normalizeIsbnInput(raw);
  if (isValidIsbn13(digits)) return digits;
  return isbn10To13(digits);
}

/// Formats an ISBN-13 for display in the conventional 978-x-xxx-xxxxx-x shape.
/// Group boundaries vary by registrant, so this is a *readable* split, not a
/// claim about the registration groups.
String formatIsbn13(String isbn13) {
  if (isbn13.length != 13) return isbn13;
  return '${isbn13.substring(0, 3)}-${isbn13.substring(3, 4)}-'
      '${isbn13.substring(4, 8)}-${isbn13.substring(8, 12)}-'
      '${isbn13.substring(12)}';
}

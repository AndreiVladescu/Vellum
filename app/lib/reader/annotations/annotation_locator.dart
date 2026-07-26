import 'dart:convert';

/// Where in a book an annotation sits (plan 5 #22).
///
/// Stored as **versioned** JSON in `annotations.locator`, which is the whole
/// reason this type exists. A PDF locator is objective — a page and a character
/// range in the page's extracted text, both of which come from the PDF itself.
/// An EPUB locator is not: its offsets are indices into *this app's* plain-text
/// extraction of a chapter, so they are only as stable as that extraction. When
/// the parser changes, `v` is what lets the old offsets be migrated rather than
/// silently pointing at the wrong sentence.
///
/// Every text locator therefore also stores the quoted text, and resolution
/// prefers the quote (see [resolveOffsets]): text that still reads the same is
/// better evidence than an integer that may have shifted.
sealed class AnnotationLocator {
  const AnnotationLocator();

  /// Current locator format. Bump when the *meaning* of a field changes, not
  /// when adding an optional one.
  static const version = 1;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());

  /// Parses [raw], or returns null when it is absent, malformed, or written by
  /// a newer app than this one. A null locator degrades to the coarse `page` /
  /// `chapter` columns rather than losing the annotation.
  static AnnotationLocator? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final v = json['v'] as int? ?? 0;
      if (v > version) return null; // written by a newer build
      return switch (json['kind'] as String?) {
        'pdfPage' => PdfPageLocator(page: json['page'] as int),
        'pdfText' => PdfTextLocator(
            page: json['page'] as int,
            start: json['start'] as int,
            end: json['end'] as int,
          ),
        'epubScroll' => EpubScrollLocator(
            chapter: json['chapter'] as int,
            fraction: (json['fraction'] as num?)?.toDouble() ?? 0,
          ),
        'epubText' => EpubTextLocator(
            chapter: json['chapter'] as int,
            start: json['start'] as int,
            end: json['end'] as int,
          ),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

/// A whole PDF page — what a bookmark records.
class PdfPageLocator extends AnnotationLocator {
  const PdfPageLocator({required this.page});

  final int page;

  @override
  Map<String, dynamic> toJson() => {
        'v': AnnotationLocator.version,
        'kind': 'pdfPage',
        'page': page,
      };
}

/// A character range within one PDF page's extracted text.
class PdfTextLocator extends AnnotationLocator {
  const PdfTextLocator({
    required this.page,
    required this.start,
    required this.end,
  });

  final int page;
  final int start;
  final int end;

  @override
  Map<String, dynamic> toJson() => {
        'v': AnnotationLocator.version,
        'kind': 'pdfText',
        'page': page,
        'start': start,
        'end': end,
      };
}

/// A chapter plus how far down it — what an EPUB bookmark records.
class EpubScrollLocator extends AnnotationLocator {
  const EpubScrollLocator({required this.chapter, required this.fraction});

  final int chapter;
  final double fraction;

  @override
  Map<String, dynamic> toJson() => {
        'v': AnnotationLocator.version,
        'kind': 'epubScroll',
        'chapter': chapter,
        'fraction': fraction,
      };
}

/// A character range within one EPUB chapter's extracted plain text.
class EpubTextLocator extends AnnotationLocator {
  const EpubTextLocator({
    required this.chapter,
    required this.start,
    required this.end,
  });

  final int chapter;
  final int start;
  final int end;

  @override
  Map<String, dynamic> toJson() => {
        'v': AnnotationLocator.version,
        'kind': 'epubText',
        'chapter': chapter,
        'start': start,
        'end': end,
      };
}

/// Re-finds a quoted passage in [text], given where it used to be.
///
/// Returns the character range, or null if the quote can't be found at all.
/// Three attempts, in order of confidence:
///
/// 1. The stored offsets, if the text there still equals the quote — the fast,
///    exact path for a document that hasn't changed.
/// 2. The occurrence of the quote *nearest* the stored offset. A re-flowed
///    chapter moves text without changing it, and "nearest to where it was" is
///    the right disambiguator when a phrase appears several times.
/// 3. The first occurrence anywhere, when there is no usable hint.
///
/// Deliberately quote-first rather than offset-first: an offset that has drifted
/// points confidently at the wrong sentence, which is worse than a highlight
/// that moves a little.
({int start, int end})? resolveOffsets({
  required String text,
  required String quote,
  int? hintStart,
}) {
  if (quote.isEmpty) return null;
  if (hintStart != null &&
      hintStart >= 0 &&
      hintStart + quote.length <= text.length &&
      text.startsWith(quote, hintStart)) {
    return (start: hintStart, end: hintStart + quote.length);
  }

  final occurrences = <int>[];
  var from = 0;
  while (true) {
    final at = text.indexOf(quote, from);
    if (at < 0) break;
    occurrences.add(at);
    from = at + 1;
  }
  if (occurrences.isEmpty) return null;
  if (hintStart == null) {
    return (start: occurrences.first, end: occurrences.first + quote.length);
  }
  var best = occurrences.first;
  for (final at in occurrences) {
    if ((at - hintStart).abs() < (best - hintStart).abs()) best = at;
  }
  return (start: best, end: best + quote.length);
}

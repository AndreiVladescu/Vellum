import 'epub_book.dart';

/// Searching the text of an EPUB.
///
/// **Why this is here and not in the reader.** pdfrx brings its own searcher for
/// PDFs; an EPUB has none, so Ctrl+F in the EPUB reader had nothing to open. The
/// text is already available — [EpubChapter.plainText] is the same extraction
/// the highlight machinery anchors to — so the search is a few lines over it,
/// kept apart from the widget so the matching rules can be tested directly.
class EpubSearchHit {
  const EpubSearchHit({
    required this.chapter,
    required this.chapterTitle,
    required this.start,
    required this.end,
    required this.snippet,
    required this.fraction,
  });

  /// Index of the chapter this hit is in.
  final int chapter;
  final String chapterTitle;

  /// Where the match sits in that chapter's plain text.
  final int start;
  final int end;

  /// A line of context with the match in the middle, for the results list.
  final String snippet;

  /// How far down the chapter the match is, as the reader's scroll fraction —
  /// the same approximation the annotations panel jumps by.
  final double fraction;
}

/// Every occurrence of [query] across [chapters], in reading order.
///
/// Case-insensitive, and whitespace in the query is collapsed to match the way
/// [EpubChapter.plainText] collapses it — otherwise a phrase copied from a page
/// where it happened to break across two lines would never be found.
///
/// [limit] caps the result list. A one-letter query in a novel matches tens of
/// thousands of times; the honest response is the first few hundred and a note
/// that there were more, not several seconds of scrolling to build a list
/// nobody will reach the end of.
({List<EpubSearchHit> hits, bool truncated}) searchEpub(
  List<EpubChapter> chapters,
  String query, {
  int limit = 200,
}) {
  final needle = query.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  if (needle.isEmpty) return (hits: const <EpubSearchHit>[], truncated: false);

  final hits = <EpubSearchHit>[];
  for (var index = 0; index < chapters.length; index++) {
    final text = chapters[index].plainText;
    final haystack = text.toLowerCase();
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at < 0) break;
      if (hits.length >= limit) return (hits: hits, truncated: true);
      final end = at + needle.length;
      hits.add(EpubSearchHit(
        chapter: index,
        chapterTitle: chapters[index].title,
        start: at,
        end: end,
        snippet: snippetAround(text, at, end),
        fraction: text.isEmpty ? 0 : at / text.length,
      ));
      // Overlapping matches ("aa" in "aaa") would be two hits pointing at
      // nearly the same place; step past this one instead.
      from = end;
    }
  }
  return (hits: hits, truncated: false);
}

/// A line of context around `text[start..end)`, with ellipses where it was cut.
///
/// Cut on a word boundary where there is one nearby: a snippet starting
/// mid-word reads as a typo, and the whole job of the snippet is to let someone
/// recognise the passage at a glance.
String snippetAround(String text, int start, int end, {int around = 44}) {
  var from = (start - around).clamp(0, text.length);
  var to = (end + around).clamp(0, text.length);
  if (from > 0) {
    final space = text.lastIndexOf(' ', start);
    if (space > from - 12 && space >= 0 && space < start) from = space + 1;
  }
  if (to < text.length) {
    final space = text.indexOf(' ', end);
    if (space > 0 && space < to + 12) to = space;
  }
  final core = text.substring(from, to).trim();
  return '${from > 0 ? '…' : ''}$core${to < text.length ? '…' : ''}';
}

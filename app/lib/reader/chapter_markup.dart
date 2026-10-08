import 'dart:ui' show Color;

import '../data/database.dart';
import 'annotations/epub_highlight_html.dart';
import 'epub_book.dart';
import 'night_mode.dart';

/// The chapter markup the EPUB reader hands its `HtmlWidget`, remade only when
/// what it is made from changes (performance round #9).
///
/// Night mode's colour stripping and the highlights both rewrite the whole
/// chapter, and they ran on every rebuild of the reader page — a selection, the
/// chrome toggling, a bookmark. A chapter can be megabytes (its images arrive
/// inlined): on an 8 MB one that was ~150 ms of a debug build per rebuild, plus
/// the `HtmlWidget` comparing the new string with the old one character by
/// character to learn nothing had changed. Kept here, a rebuild hands back the
/// very same string, and comparing a string with itself is instant.
class ChapterMarkup {
  ({Object key, String html})? _last;

  /// [chapter] (number [index]) as the reader shows it: book colours removed
  /// on a [darkPage], and [annotations]' highlights painted in [ink].
  ///
  /// [annotations] is compared by identity — the reader replaces its list
  /// whenever annotations change, and must never edit it in place.
  String of(
    EpubChapter chapter, {
    required int index,
    required bool darkPage,
    required Color ink,
    required List<Annotation> annotations,
  }) {
    final key = (chapter, index, darkPage, ink, annotations);
    final last = _last;
    if (last != null && last.key == key) return last.html;
    // Stored highlights painted into the markup, so the text is coloured like
    // a marker rather than only listed in the panel. Night mode: the book's own
    // colours come out first, or a heading that asked for near-black stays
    // near-black on a near-black page.
    final html = withHighlights(
      darkPage ? withoutBookColours(chapter.html) : chapter.html,
      annotations,
      index,
      ink: ink,
    );
    _last = (key: key, html: html);
    return html;
  }
}

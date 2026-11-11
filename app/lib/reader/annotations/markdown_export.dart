import '../../data/database.dart';
import '../../l10n/gen/app_localizations.dart';
import '../../l10n/labels.dart';
import 'annotation_store.dart';

/// Exports annotations as Markdown (plan 5 #22).
///
/// The reason this exists at all: a highlight nobody can get out of the app is a
/// highlight held hostage. Markdown rather than a private format because it
/// pastes into anything — notes apps, a wiki, an email — without a converter.
///
/// Pure string building, deliberately: no file I/O, no widgets, so the output is
/// pinned by a test rather than eyeballed.
class MarkdownExport {
  /// One book's annotations, in reading order.
  ///
  /// [authors] appears under the title when known. Locations are rendered from
  /// the coarse `page`/`chapter` columns, which is what a human wants to see
  /// (the JSON locator is for jumping back inside the app, not for reading).
  static String forBook({
    required L10n l10n,
    required Book book,
    required List<Annotation> annotations,
    List<String> authors = const [],
  }) {
    final out = StringBuffer()
      ..writeln('# ${book.title}')
      ..writeln();
    if (authors.isNotEmpty) {
      out
        ..writeln('*${authors.join(', ')}*')
        ..writeln();
    }
    if (annotations.isEmpty) {
      out.writeln(l10n.markdownNothingYet);
      return out.toString();
    }

    for (final a in annotations) {
      final kind = AnnotationKind.parse(a.kind);
      // Writing on a page is strokes and coordinates; there is no text to
      // export and an empty heading would be a lie about what is there. Said
      // in words instead, so the export doesn't imply the page is unmarked.
      if (kind == AnnotationKind.ink) {
        final where = _location(l10n, a);
        final heading = AnnotationKind.ink.labelOf(l10n);
        out
          ..writeln(
              '## ${where == null ? heading : l10n.markdownHeadingWithLocation(heading, where)}')
          ..writeln()
          ..writeln(l10n.markdownWritingBody)
          ..writeln();
        continue;
      }
      final location = _location(l10n, a);
      final heading = kind?.labelOf(l10n) ?? a.kind;
      out.writeln(
          '## ${location == null ? heading : l10n.markdownHeadingWithLocation(heading, location)}');
      out.writeln();
      final quote = a.quotedText;
      if (quote != null && quote.isNotEmpty) {
        // Blockquote every line, so a multi-paragraph highlight stays quoted
        // rather than the second paragraph escaping into body text.
        for (final line in quote.trim().split('\n')) {
          out.writeln('> ${line.trim()}');
        }
        out.writeln();
      }
      final note = a.note;
      if (note != null && note.isNotEmpty) {
        out
          ..writeln(note.trim())
          ..writeln();
      }
    }
    return out.toString();
  }

  /// The whole library, one section per book, books with nothing omitted.
  ///
  /// [byBook] is keyed by book id. Books are emitted in the order given, so the
  /// caller decides (title, recently read, …) rather than this imposing one.
  static String forLibrary({
    required L10n l10n,
    required List<Book> books,
    required Map<String, List<Annotation>> byBook,
    Map<String, List<String>> authorsByBook = const {},
  }) {
    final sections = <String>[];
    for (final book in books) {
      final annotations = byBook[book.id] ?? const [];
      if (annotations.isEmpty) continue;
      sections.add(forBook(
        l10n: l10n,
        book: book,
        annotations: annotations,
        authors: authorsByBook[book.id] ?? const [],
      ).trim());
    }
    final out = StringBuffer()
      ..writeln('# ${l10n.markdownLibraryTitle}')
      ..writeln();
    if (sections.isEmpty) {
      out.writeln(l10n.markdownLibraryNothing);
      return out.toString();
    }
    // A count up front, because the first useful question about an export of
    // this kind is "did it get everything?".
    final total = sections.length;
    out
      ..writeln(l10n.markdownLibraryCount(total))
      ..writeln();
    // Demote the per-book `#` to `##` so the document has one root heading.
    for (final section in sections) {
      out
        ..writeln(section.replaceAll(RegExp(r'^#', multiLine: true), '##'))
        ..writeln();
    }
    return out.toString();
  }

  /// A human-readable location, or null when the annotation has none (an
  /// import from a source that didn't record one).
  static String? _location(L10n l10n, Annotation a) {
    if (a.page != null) return l10n.markdownLocationPage(a.page!);
    if (a.chapter != null) return l10n.markdownLocationChapter(a.chapter! + 1);
    return null;
  }

  /// A filesystem-safe name for a per-book export, e.g. `Dune-highlights.md`.
  static String fileNameFor(Book book) {
    final safe = book.title
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
    return '${safe.isEmpty ? 'book' : safe}-highlights.md';
  }
}

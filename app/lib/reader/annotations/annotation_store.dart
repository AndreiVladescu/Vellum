import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../data/database.dart';
import 'annotation_locator.dart';

/// The three things a reader can leave behind. Values match the `kind` column.
enum AnnotationKind {
  bookmark,
  highlight,
  note;

  static AnnotationKind? parse(String raw) =>
      AnnotationKind.values.where((k) => k.name == raw).firstOrNull;

  String get label => switch (this) {
        AnnotationKind.bookmark => 'Bookmark',
        AnnotationKind.highlight => 'Highlight',
        AnnotationKind.note => 'Note',
      };
}

/// Bookmarks, highlights and notes (plan 5 #22).
///
/// App-local by design, like `readerNotes`: marginalia are personal, and the
/// server has no business holding them. The store keeps no state of its own, so
/// the readers, the panel, and the exporter all see the same rows.
class AnnotationStore {
  AnnotationStore(this.db);

  final VellumDatabase db;

  static const _uuid = Uuid();

  /// Everything for one book, newest last within a location so the panel reads
  /// like the book: page/chapter ascending, then creation order.
  Stream<List<Annotation>> watchForBook(String bookId) =>
      (db.select(db.annotations)
            ..where((a) => a.bookId.equals(bookId))
            ..orderBy([
              (a) => OrderingTerm.asc(a.page),
              (a) => OrderingTerm.asc(a.chapter),
              (a) => OrderingTerm.asc(a.createdAt),
            ]))
          .watch();

  Future<List<Annotation>> forBook(String bookId) =>
      watchForBook(bookId).first;

  /// Every annotation in the library, newest first — the "everything I
  /// highlighted" view.
  Stream<List<Annotation>> watchAll() => (db.select(db.annotations)
        ..orderBy([(a) => OrderingTerm.desc(a.createdAt)]))
      .watch();

  /// Adds an annotation and returns its id.
  ///
  /// [locator] carries the fine position; [page]/[chapter] are stored alongside
  /// it so the panel can sort without parsing JSON. Nothing here bumps the
  /// book's sync clock: an annotation is not catalogue data.
  Future<String> add({
    required String bookId,
    required AnnotationKind kind,
    AnnotationLocator? locator,
    int? page,
    int? chapter,
    String? quotedText,
    String? note,
    int? color,
  }) async {
    final id = _uuid.v4();
    await db.into(db.annotations).insert(AnnotationsCompanion.insert(
          id: id,
          bookId: bookId,
          kind: kind.name,
          page: Value(page),
          chapter: Value(chapter),
          locator: Value(locator?.encode()),
          quotedText: Value(_blankToNull(quotedText)),
          note: Value(_blankToNull(note)),
          color: Value(color),
        ));
    return id;
  }

  /// Edits the user's own words on an existing annotation. Blank clears it.
  ///
  /// A highlight whose note is cleared stays a highlight — the quoted text is
  /// the point of it. Only the note text is editable: the location and the quote
  /// are what the reader captured, and letting them be typed over would make the
  /// annotation a lie about the book.
  Future<void> setNote(String id, String? note) =>
      (db.update(db.annotations)..where((a) => a.id.equals(id)))
          .write(AnnotationsCompanion(note: Value(_blankToNull(note))));

  Future<void> setColor(String id, int? color) =>
      (db.update(db.annotations)..where((a) => a.id.equals(id)))
          .write(AnnotationsCompanion(color: Value(color)));

  Future<void> delete(String id) =>
      (db.delete(db.annotations)..where((a) => a.id.equals(id))).go();

  /// Drops every annotation for a book — used when the book itself goes.
  Future<void> deleteForBook(String bookId) =>
      (db.delete(db.annotations)..where((a) => a.bookId.equals(bookId))).go();

  /// Whether this book has a bookmark at [page] already, so the reader's
  /// bookmark button can toggle instead of stacking duplicates.
  Future<Annotation?> bookmarkAtPage(String bookId, int page) async {
    final rows = await (db.select(db.annotations)
          ..where((a) =>
              a.bookId.equals(bookId) &
              a.kind.equals(AnnotationKind.bookmark.name) &
              a.page.equals(page)))
        .get();
    return rows.firstOrNull;
  }

  /// The EPUB equivalent: one bookmark per chapter is the useful granularity —
  /// a bookmark every few paragraphs would be noise, and the scroll fraction
  /// inside the locator still takes you back to the right place.
  Future<Annotation?> bookmarkAtChapter(String bookId, int chapter) async {
    final rows = await (db.select(db.annotations)
          ..where((a) =>
              a.bookId.equals(bookId) &
              a.kind.equals(AnnotationKind.bookmark.name) &
              a.chapter.equals(chapter)))
        .get();
    return rows.firstOrNull;
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

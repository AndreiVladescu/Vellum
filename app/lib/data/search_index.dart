/// FTS5-backed search index for the shelf's search box (plan 5 §A2).
///
/// - **App-local only.** The index is entirely derived from `books`,
///   `book_authors`/`authors`, and `book_genres`/`genres` — no server
///   migration, no `schema_parity.rs` entry, and nothing here ever touches
///   `books.updated_at` / `books.needs_push` (derived data stays off the
///   sync clock, same rule as spine colours).
/// - **Maintained by SQL triggers**, not by repository write paths — every
///   insert/update/delete on the source tables keeps `book_search` in sync
///   automatically, so there is nowhere for a new write method to forget to
///   update it.
/// - **A plain (non-contentless) FTS5 table.** A `content=''` table would be
///   smaller, but contentless FTS5 can't service a plain `DELETE` without
///   `contentless_delete=1` (SQLite >= 3.43) or the `'delete'`-command
///   insert form — easy to get subtly wrong from triggers. At
///   library-metadata scale the stored text is trivial; take the plain
///   table and keep deletion trivial too.
/// - **No FTS5-availability fallback.** `sqlite3_flutter_libs` compiles
///   FTS5 in; this is a framework guarantee, not a runtime maybe.
library;

/// `book_id` is `UNINDEXED` (stored but not tokenized/searched) so a match
/// can be resolved back to the book without a second lookup table.
const createBookSearchTable = '''
CREATE VIRTUAL TABLE book_search USING fts5(
  book_id UNINDEXED,
  title,
  subtitle,
  authors,
  genres,
  publisher,
  isbn,
  tokenize = 'unicode61 remove_diacritics 2'
)
''';

/// Recomputes `authors`/`genres` as a space-joined blob of names — FTS5
/// matches on token presence, so join order doesn't matter, only which
/// names are present.
const _authorsExpr = "SELECT COALESCE(group_concat(a.name, ' '), '') "
    'FROM book_authors ba JOIN authors a ON a.id = ba.author_id '
    'WHERE ba.book_id = ';
const _genresExpr = "SELECT COALESCE(group_concat(g.name, ' '), '') "
    'FROM book_genres bg JOIN genres g ON g.id = bg.genre_id '
    'WHERE bg.book_id = ';

/// One `CREATE TRIGGER` per statement — `customStatement` runs one
/// statement at a time, so this stays a list rather than one multi-statement
/// script. Keyed by name so callers can guard each one idempotently against
/// `sqlite_master`, matching the rest of `onUpgrade`.
final Map<String, String> bookSearchTriggers = {
  'book_search_books_ai': '''
CREATE TRIGGER book_search_books_ai AFTER INSERT ON books BEGIN
  INSERT INTO book_search (book_id, title, subtitle, authors, genres, publisher, isbn)
  VALUES (new.id, new.title, new.subtitle, '', '', new.publisher, new.isbn);
END
''',
  // OF-qualified: SQLite only fires this when the UPDATE's SET list actually
  // names one of these columns, so a reading-position write (which sets
  // reading_progress/last_read_page/last_read_at, not these) never touches
  // the FTS5 index — that write happens on every page turn, and an FTS5
  // UPDATE is a delete+reinsert internally (see docs/PERFORMANCE.md's
  // reading-position finding, plan 5 §A1).
  'book_search_books_au': '''
CREATE TRIGGER book_search_books_au AFTER UPDATE OF title, subtitle, publisher, isbn ON books BEGIN
  UPDATE book_search SET title = new.title, subtitle = new.subtitle,
    publisher = new.publisher, isbn = new.isbn
  WHERE book_id = new.id;
END
''',
  'book_search_books_ad': '''
CREATE TRIGGER book_search_books_ad AFTER DELETE ON books BEGIN
  DELETE FROM book_search WHERE book_id = old.id;
END
''',
  'book_search_book_authors_ai': '''
CREATE TRIGGER book_search_book_authors_ai AFTER INSERT ON book_authors BEGIN
  UPDATE book_search SET authors = ($_authorsExpr new.book_id)
  WHERE book_id = new.book_id;
END
''',
  'book_search_book_authors_ad': '''
CREATE TRIGGER book_search_book_authors_ad AFTER DELETE ON book_authors BEGIN
  UPDATE book_search SET authors = ($_authorsExpr old.book_id)
  WHERE book_id = old.book_id;
END
''',
  // Author renames don't touch book_authors, so they need their own trigger:
  // every book referencing the renamed author gets its authors text redone.
  'book_search_authors_au': '''
CREATE TRIGGER book_search_authors_au AFTER UPDATE OF name ON authors BEGIN
  UPDATE book_search SET authors = ($_authorsExpr book_search.book_id)
  WHERE book_id IN (SELECT book_id FROM book_authors WHERE author_id = new.id);
END
''',
  'book_search_book_genres_ai': '''
CREATE TRIGGER book_search_book_genres_ai AFTER INSERT ON book_genres BEGIN
  UPDATE book_search SET genres = ($_genresExpr new.book_id)
  WHERE book_id = new.book_id;
END
''',
  'book_search_book_genres_ad': '''
CREATE TRIGGER book_search_book_genres_ad AFTER DELETE ON book_genres BEGIN
  UPDATE book_search SET genres = ($_genresExpr old.book_id)
  WHERE book_id = old.book_id;
END
''',
  'book_search_genres_au': '''
CREATE TRIGGER book_search_genres_au AFTER UPDATE OF name ON genres BEGIN
  UPDATE book_search SET genres = ($_genresExpr book_search.book_id)
  WHERE book_id IN (SELECT book_id FROM book_genres WHERE genre_id = new.id);
END
''',
};

/// One-time backfill for a database that already had books when the index
/// was introduced (or a fresh install, which creates the table empty).
const backfillBookSearch = '''
INSERT INTO book_search (book_id, title, subtitle, authors, genres, publisher, isbn)
SELECT
  b.id, b.title, b.subtitle,
  COALESCE((${_authorsExpr}b.id), ''),
  COALESCE((${_genresExpr}b.id), ''),
  b.publisher, b.isbn
FROM books b
''';

/// Builds an FTS5 `MATCH` query from free-typed [text]: each whitespace-
/// separated token becomes a quoted prefix match, ANDed together, so typing
/// a prefix ("her") matches ("Herbert") and a multi-word query requires
/// every token present, in any order. [column], if given, restricts every
/// token to that column (used for the `genre:` shorthand). Quoting each
/// token makes arbitrary user input — including FTS5 query-syntax
/// characters like `-`, `:`, `(` — safe to embed literally.
///
/// This is FTS5 *prefix* matching, not the old Dart implementation's
/// arbitrary-substring matching (`"tok"*` won't match text where `tok`
/// appears mid-word) — an intentional, documented change, see
/// `docs/IMPROVEMENT_PLAN_5.md` §A2.
String? ftsMatchQuery(String text, {String? column}) {
  final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return null;
  final prefix = column == null ? '' : '$column:';
  return tokens
      .map((t) => '$prefix"${t.replaceAll('"', '""')}"*')
      .join(' AND ');
}

// ---------------------------------------------------------------------------
// Content index: the text *inside* books, not their catalogue entry.
// ---------------------------------------------------------------------------

/// FTS5 table holding one row per page (PDF) or spine section (EPUB).
///
/// Separate from `book_search` rather than another column on it, because the
/// grain is different: `book_search` is one row per book, this is thousands of
/// rows per book, and a search here has to report *where* the hit was to be
/// worth anything.
///
/// Unlike `book_search` there are **no triggers**: the source is a file on
/// disk, not a table, so nothing SQLite can observe tells it the text changed.
/// `book_text.status` is the queue instead, and `book_text_after_delete` sweeps
/// the rows when a file's row goes — a virtual table has no foreign keys, so
/// the cascade cannot do it.
const createBookTextFtsTable = '''
CREATE VIRTUAL TABLE book_text_fts USING fts5(
  body,
  page UNINDEXED,
  file_id UNINDEXED,
  book_id UNINDEXED,
  tokenize = 'unicode61 remove_diacritics 2'
)
''';

final Map<String, String> bookTextTriggers = {
  'book_text_after_delete': '''
CREATE TRIGGER book_text_after_delete AFTER DELETE ON book_text BEGIN
  DELETE FROM book_text_fts WHERE file_id = old.file_id;
END
''',
};

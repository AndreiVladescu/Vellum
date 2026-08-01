/// Which parts of a library a sync is allowed to touch (next features #8).
///
/// Sync used to be all-or-nothing per pass: one press moved books, covers,
/// files, shelves, copies, loans, copy photos and everyone's marks. The single
/// exception was reading position, which had its own opt-in because it is
/// per-device rather than per-library — and that exception is the shape this
/// generalises.
///
/// **Off means off in both directions.** A resource that stopped pushing but
/// kept pulling would look like it was still syncing; one that stopped pulling
/// but kept pushing would quietly publish what you asked it not to. So every
/// flag guards its pull pass *and* its push pass, and the tests pin that.
///
/// Reading position is deliberately not here: it already has
/// `AppSettingsStore.syncReadingPosition`, with a `forgetDevice` un-publish
/// that none of these have yet. Moving it would mean two settings for one
/// switch during the migration, for no gain.
library;

class SyncScope {
  const SyncScope({
    this.books = true,
    this.copies = true,
    this.loans = true,
    this.annotations = true,
    this.sessions = true,
    this.copyPhotos = true,
  });

  /// The catalogue itself: book rows, authors and genres, covers, book files,
  /// and the digital shelves they are arranged on. Turning this off leaves a
  /// sync that carries only what hangs off books it already has.
  final bool books;

  /// Physical copies — where a book lives, and the rooms it is placed in.
  final bool copies;

  /// Who has what, and the history of who had it before.
  final bool loans;

  /// Highlights, notes and bookmarks. Personal: scoped to the account
  /// server-side, so a shared library holds several people's marks in the same
  /// book without any of them seeing the others'.
  final bool annotations;

  /// Reading sittings — when you read, and for how long. Personal, like
  /// annotations, and separable because "sync my highlights" and "sync my
  /// reading habits" are different appetites.
  final bool sessions;

  /// Pictures of a shelf, hanging off a physical copy. Library data rather than
  /// personal — visible to whoever the book is shared with, like its covers —
  /// but by far the heaviest thing here, which is why it gets its own switch.
  final bool copyPhotos;

  /// Everything on, which is what a sync did before this existed and what a
  /// device that has never opened the screen still does.
  static const everything = SyncScope();

  bool get isEverything =>
      books && copies && loans && annotations && sessions && copyPhotos;

  /// The resources currently switched off, for a one-line summary.
  List<String> get excluded => [
        if (!books) 'books',
        if (!copies) 'physical copies',
        if (!loans) 'loans',
        if (!annotations) 'highlights and notes',
        if (!sessions) 'reading sittings',
        if (!copyPhotos) 'copy photos',
      ];

  SyncScope copyWith({
    bool? books,
    bool? copies,
    bool? loans,
    bool? annotations,
    bool? sessions,
    bool? copyPhotos,
  }) =>
      SyncScope(
        books: books ?? this.books,
        copies: copies ?? this.copies,
        loans: loans ?? this.loans,
        annotations: annotations ?? this.annotations,
        sessions: sessions ?? this.sessions,
        copyPhotos: copyPhotos ?? this.copyPhotos,
      );

  @override
  bool operator ==(Object other) =>
      other is SyncScope &&
      other.books == books &&
      other.copies == copies &&
      other.loans == loans &&
      other.annotations == annotations &&
      other.sessions == sessions &&
      other.copyPhotos == copyPhotos;

  @override
  int get hashCode =>
      Object.hash(books, copies, loans, annotations, sessions, copyPhotos);
}

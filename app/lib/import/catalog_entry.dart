import 'filename_metadata.dart';

/// One book as an *external catalogue* describes it (plan 5 #21c).
///
/// Where a folder import has to guess everything from a file name, Calibre, a
/// CSV export and an OPDS feed all state it outright. This is that statement,
/// in one shape, so the three readers converge before they reach the import
/// pipeline — the dry run, the duplicate check and the review table are then
/// the same code for all four sources.
///
/// [filePath] is what separates the sources that bring bytes (Calibre, a
/// downloaded OPDS acquisition) from the ones that bring only a record
/// (CSV/JSON). A metadata-only entry is a real import: a catalogue of physical
/// books, or a library whose files live on a server, is still a library.
class CatalogEntry {
  const CatalogEntry({
    required this.title,
    this.authors = const [],
    this.subtitle,
    this.isbn,
    this.publisher,
    this.description,
    this.series,
    this.seriesIndex,
    this.year,
    this.pageCount,
    this.genres = const [],
    this.filePath,
    this.coverPath,
    this.sourceId,
    this.status,
    this.rating,
    this.finishedAt,
    this.readCount,
    this.review,
  });

  final String title;
  final List<String> authors;
  final String? subtitle;
  final String? isbn;
  final String? publisher;
  final String? description;
  final String? series;
  final double? seriesIndex;
  final int? year;
  final int? pageCount;
  final List<String> genres;

  // ---- What *you* made of the book -----------------------------------------
  //
  // A Goodreads or StoryGraph export is mostly not catalogue data: it is years
  // of your ratings, your shelves and your reviews. Dropping those on import
  // and keeping only the titles throws away the part that took the time to
  // accumulate. Null throughout means "the export did not say", which is not
  // the same as zero — an unrated book is not a book rated nought.

  /// The exporter's shelf mapped onto our own vocabulary, e.g. Goodreads'
  /// `to-read` becomes [ReadingStatus.wishlist].
  final String? status;

  /// 1–5. Half stars are rounded: StoryGraph allows 4.5, this column does not.
  final int? rating;

  final DateTime? finishedAt;

  /// How many times it has been read, for re-reads.
  final int? readCount;

  /// Your review or private note.
  ///
  /// Goes to `readerNotes` and its own personal channel, never onto the book
  /// row — a shared library must not publish what you thought of a book to
  /// everyone it is shared with.
  final String? review;

  /// A readable file this entry brings with it, or null for metadata only.
  final String? filePath;

  /// A readable cover image, or null.
  final String? coverPath;

  /// The id this book had in its source catalogue — Calibre's row id, an OPDS
  /// entry id. Not stored; used to keep a review list stable and to report
  /// which row failed in terms the user can find again in the source.
  final String? sourceId;

  /// The filename-shaped view of this entry, so a [CatalogEntry] can flow
  /// through the parts of the pipeline that predate it without special cases.
  FilenameMeta get asFilenameMeta => FilenameMeta(
        title: title,
        authors: authors,
        publisher: publisher,
        year: year,
      );

  CatalogEntry copyWith({String? filePath, String? coverPath}) => CatalogEntry(
        title: title,
        authors: authors,
        subtitle: subtitle,
        isbn: isbn,
        publisher: publisher,
        description: description,
        series: series,
        seriesIndex: seriesIndex,
        year: year,
        pageCount: pageCount,
        genres: genres,
        filePath: filePath ?? this.filePath,
        coverPath: coverPath ?? this.coverPath,
        sourceId: sourceId,
      );
}

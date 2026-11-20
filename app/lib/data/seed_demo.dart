import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:xml/xml.dart';
import 'package:archive/archive.dart';

import '../audio/audiobook_import.dart';
import '../import/catalog_entry.dart';
import '../import/folder_import_service.dart';
import '../import/import_plan.dart';
import '../physical/bookcase_template.dart';
import '../physical/physical_metrics.dart';
import '../physical/room_prop.dart';
import '../reader/annotations/annotation_locator.dart';
import '../reader/annotations/highlight_palette.dart';
import '../reader/epub_book.dart';
import '../server/connection_store.dart';
import '../shelf/spine_style.dart';
import 'database.dart';
import 'demo_pdf.dart';
import 'library_repository.dart';

/// The demo library (`tool/demo_library.sh`): what the README, the store
/// listing and the promo clip show.
///
/// Unlike the profiling seeder, which writes rows straight in because it needs
/// four thousand of them, this goes through the **real import path** — the
/// folder importer for the books, the audiobook importer for the recording —
/// so covers, spine colours, series and genres are exactly what a user who
/// imported these files would get. Only the *history* is written directly:
/// two years of someone reading, which no import could produce.
///
/// Every book is public domain, every name is made up, and every date is
/// relative to [now], so "this week" and the current streak are never empty
/// whenever the library is built.

/// Written into the data directory when seeding finishes; the promo tour
/// refuses to run against a library without it.
const demoMarkerFile = 'demo-library.json';

/// The furnished room.
const demoRoomName = 'Living room'; // i18n-ignore: seeded demo data

/// The account the demo is "signed in" as on this device. Generic on purpose.
const demoProfileName = 'Sam'; // i18n-ignore: seeded demo data
const demoProfileEmail = 'demo@example.com';

/// What [seedDemoLibrary] made, for the marker file and the tool's report.
class DemoSummary {
  DemoSummary();

  int ebooks = 0;
  int pdfs = 0;
  int audiobooks = 0;
  int wishlist = 0;
  int finished = 0;
  int reading = 0;
  int sessions = 0;
  int annotations = 0;
  int copies = 0;
  int placed = 0;
  int loans = 0;
  int shelves = 0;
  final ids = <String, String>{};
  final warnings = <String>[];

  Map<String, Object> toJson() => {
        'ebooks': ebooks,
        'pdfs': pdfs,
        'audiobooks': audiobooks,
        'wishlist': wishlist,
        'finished': finished,
        'reading': reading,
        'sessions': sessions,
        'annotations': annotations,
        'physicalCopies': copies,
        'placedInRoom': placed,
        'loans': loans,
        'shelves': shelves,
        'warnings': warnings,
        // Manifest id -> book id, for the promo tour to find its scenes.
        'books': ids,
      };
}

/// Builds the demo library into [repository] (whose database must be empty)
/// from the files under [sources], as listed in [manifest]
/// (`tool/demo_library/manifest.json`). [work] is scratch space for the
/// typeset PDFs and extracted covers.
Future<DemoSummary> seedDemoLibrary(
  LibraryRepository repository, {
  required Map<String, dynamic> manifest,
  required Directory sources,
  required Directory work,
  DateTime? now,
  void Function(String message)? log,
}) async {
  // The demo's files are isolated by XDG_DATA_HOME; the OS keyring is not, and
  // it holds the real app's server token. Same rule as the profiling guard.
  if ((Platform.isLinux || Platform.isMacOS || Platform.isWindows) &&
      !ServerConnection.keyringDisabled) {
    throw StateError('Refusing to build the demo library: VELLUM_NO_KEYRING '
        'is not set. Run tool/demo_library.sh.');
  }
  final db = repository.db;
  final today = now ?? DateTime.now();
  final summary = DemoSummary();
  work.createSync(recursive: true);

  // ---- 1. Read every source's package file -----------------------------------
  final books = [
    for (final raw in manifest['books'] as List)
      _Source.fromManifest(raw as Map<String, dynamic>, sources),
  ];
  for (final b in books) {
    b.opf = _readOpf(b.file);
  }

  // ---- 2. Catalogue entries: EPUBs, typeset PDFs, wishlist covers ------------
  log?.call('typesetting ${books.where((b) => b.use == 'pdf').length} PDFs');
  final entries = <CatalogEntry>[];
  final byPath = <String, _Source>{};
  for (final b in books) {
    final opf = b.opf!;
    String? filePath;
    String? coverPath;
    var pages = (opf.words / 300).round();
    switch (b.use) {
      case 'library':
        filePath = b.file.path;
      case 'pdf':
        final pdf = await _typeset(b, work);
        filePath = pdf.path;
        pages = pdf.pages;
      case 'wishlist':
        break;
    }
    // A wishlist book has no file to take a cover from, and a PDF's would be
    // rendered from its first page — which needs PDFium, not available to a
    // seeding run. Both are given the Standard Ebooks cover art directly.
    if (b.use != 'library') {
      final cover = await EpubBook.coverBytes(b.file);
      if (cover != null) {
        final f = File(p.join(work.path, '${b.id}-cover.jpg'))
          ..writeAsBytesSync(cover);
        coverPath = f.path;
      }
    }
    final entry = CatalogEntry(
      title: opf.title,
      subtitle: opf.subtitle,
      authors: opf.authors,
      year: b.year,
      description: opf.description,
      publisher: 'Standard Ebooks', // i18n-ignore: a proper noun
      pageCount: pages,
      genres: b.genres,
      series: b.series,
      seriesIndex: b.seriesIndex,
      filePath: filePath,
      coverPath: coverPath,
      status: b.use == 'wishlist' ? 'wishlist' : null,
    );
    entries.add(entry);
    byPath[filePath ?? entry.title] = b;
  }

  // ---- 3. The import itself ---------------------------------------------------
  log?.call('importing ${entries.length} books');
  final importer = FolderImportService(repository);
  final candidates = await importer.scanEntries(entries);
  final fresh = [
    for (final c in candidates)
      if (c.status == ImportStatus.newBook) c,
  ];
  if (fresh.length != candidates.length) {
    throw StateError('the library is not empty: '
        '${candidates.length - fresh.length} books already there');
  }
  final report = await importer.import(fresh);
  final ids = <String, String>{};
  for (final o in report.outcomes) {
    final source = byPath[o.path];
    if (o.bookId == null || source == null) {
      throw StateError('import failed for ${o.path}: ${o.error}');
    }
    ids[source.id] = o.bookId!;
    switch (source.use) {
      case 'library':
        summary.ebooks++;
      case 'pdf':
        summary.pdfs++;
      case 'wishlist':
        summary.wishlist++;
    }
  }
  summary.ids.addAll(ids);
  String id(String key) =>
      ids[key] ?? (throw StateError('no book "$key" in the manifest'));

  // ---- 4. The audiobook, attached to its ebook --------------------------------
  final audioBookIds = <String>{};
  for (final raw in manifest['audio'] as List) {
    final a = raw as Map<String, dynamic>;
    final dir = Directory(p.join(sources.path, 'audio', a['id'] as String));
    final parts = [
      for (final f in a['files'] as List)
        p.join(dir.path, (f as Map<String, dynamic>)['file'] as String),
    ];
    log?.call('attaching the audiobook (${parts.length} parts)');
    final audio = AudiobookImporter(repository);
    final scan = await audio.scan(parts);
    final bookId = id(a['attachTo'] as String);
    await audio.attachTo(bookId, scan);
    audioBookIds.add(bookId);
    summary.audiobooks++;
  }

  // ---- 5. The reader's history ------------------------------------------------
  log?.call('writing two years of reading');
  final rng = Random(20261120);
  final rows = {for (final b in await db.select(db.books).get()) b.id: b};
  int pagesOf(String key) => rows[id(key)]!.pageCount ?? 250;
  DateTime daysAgo(num days, {int hour = 21, int minute = 0}) {
    final d = DateTime(today.year, today.month, today.day - days.floor());
    return d.add(Duration(hours: hour, minutes: minute));
  }

  final sessions = _SessionWriter(rng);
  final updates = <String, BooksCompanion>{};
  void update(String key, BooksCompanion c) => updates[id(key)] = c;

  final chaptersOf = <String, EpubBook>{};
  Future<EpubBook?> epubOf(String key) async {
    final source = books.firstWhere((b) => b.id == key);
    if (source.use != 'library') return null;
    return chaptersOf[key] ??= await EpubBook.open(source.file);
  }

  for (final f in _finished) {
    final finished = daysAgo(f.daysAgo, hour: 22, minute: rng.nextInt(50));
    final started = daysAgo(f.daysAgo + f.days, hour: 20);
    sessions.read(
      id(f.id),
      from: started,
      to: finished,
      startPage: 0,
      endPage: pagesOf(f.id),
    );
    update(
      f.id,
      BooksCompanion(
        status: const Value('finished'),
        rating: Value(f.rating),
        startedAt: Value(started),
        finishedAt: Value(finished),
        readCount: Value(f.readCount),
        readingProgress: const Value(1.0),
        // At the last chapter (EPUB) or page (PDF), as reading to the end
        // leaves it.
        lastReadPage:
            Value((await epubOf(f.id))?.chapters.length ?? pagesOf(f.id)),
        lastReadAt: Value(finished),
        statusUpdatedAt: Value(finished),
        ratingUpdatedAt: Value(finished),
      ),
    );
    summary.finished++;
  }

  // Read before this library existed: finished, rated, no dates.
  for (final e in _readBefore.entries) {
    update(
      e.key,
      BooksCompanion(
        status: const Value('finished'),
        rating: Value(e.value),
        readCount: const Value(1),
        readingProgress: const Value(1.0),
        statusUpdatedAt: Value(daysAgo(560)),
        ratingUpdatedAt: Value(daysAgo(560)),
      ),
    );
  }

  for (final r in _reading) {
    final started = daysAgo(r.startedDaysAgo, hour: 21);
    final last = today.subtract(Duration(hours: r.lastReadHoursAgo));
    final pages = pagesOf(r.id);
    sessions.read(
      id(r.id),
      from: started,
      to: last,
      startPage: 0,
      endPage: (pages * r.progress).round(),
      daily: r.daily,
      sparse: r.sparse,
    );
    final epub = await epubOf(r.id);
    final chapterCount = epub?.chapters.length ?? pages;
    // An EPUB reopens at the top of the chapter the reader is in, where the
    // newest highlight is; a PDF at its page.
    final chapter = (r.progress * chapterCount).floor();
    update(
      r.id,
      BooksCompanion(
        status: const Value('reading'),
        startedAt: Value(started),
        readingProgress: Value(
            epub == null ? r.progress : (chapter + 0.01) / chapterCount),
        // An EPUB keeps its 1-based chapter here, a PDF its page.
        lastReadPage: Value(
            epub == null ? (pages * r.progress).round() : chapter + 1),
        lastReadAt: Value(last),
        statusUpdatedAt: Value(started),
      ),
    );
    summary.reading++;
  }

  for (final a in _abandoned) {
    final started = daysAgo(a.startedDaysAgo, hour: 21);
    final stopped = daysAgo(a.stoppedDaysAgo, hour: 22);
    sessions.read(
      id(a.id),
      from: started,
      to: stopped,
      startPage: 0,
      endPage: (pagesOf(a.id) * a.progress).round(),
      sparse: true,
    );
    final epub = await epubOf(a.id);
    update(
      a.id,
      BooksCompanion(
        status: const Value('abandoned'),
        startedAt: Value(started),
        readingProgress: Value(a.progress),
        lastReadPage: Value(
            (a.progress * (epub?.chapters.length ?? 1)).floor() + 1),
        lastReadAt: Value(stopped),
        statusUpdatedAt: Value(stopped),
      ),
    );
  }

  // Listening, these last ten days: commutes and a couple of evenings.
  for (final bookId in audioBookIds) {
    final position = sessions.listen(bookId, today: today);
    final yesterday = DateTime(today.year, today.month, today.day - 1, 8, 20);
    updates[bookId] = (updates[bookId] ?? const BooksCompanion()).copyWith(
      listenPosition: Value(position.toDouble()),
      lastListenedAt: Value(yesterday),
    );
  }

  // Dates added: the books read in the window arrived shortly before they
  // were started, the rest over the two years before that.
  for (final b in books) {
    final bookId = ids[b.id];
    if (bookId == null) continue;
    final c = updates[bookId] ?? const BooksCompanion();
    final started = c.startedAt.present ? c.startedAt.value : null;
    final added = started != null
        ? started.subtract(Duration(days: 3 + rng.nextInt(40), hours: 2))
        : daysAgo(b.use == 'wishlist'
            ? 5 + rng.nextInt(90)
            : _toRead.contains(b.id)
                ? 10 + rng.nextInt(120)
                : 560 + rng.nextInt(200));
    // The import generates each spine before the page count is written, so
    // every spine came out one width; regenerate it from the page count, as
    // an edit to the page count would, keeping the cover colour.
    final row = rows[bookId]!;
    final spine = SpineStyle.generate(
      title: row.title,
      author: b.opf!.authors.firstOrNull,
      pageCount: row.pageCount,
    ).withCoverColor(
        SpineStyle.fromJson(row.spineStyle, title: row.title).coverColor);
    updates[bookId] = c.copyWith(
      spineStyle: Value(spine.toJson()),
      createdAt: Value(added),
      updatedAt: Value(added),
      needsPush: const Value(false),
      statusNeedsPush: const Value(false),
      readerNotesNeedsPush: const Value(false),
    );
  }
  await db.batch((batch) {
    for (final e in updates.entries) {
      batch.update(db.books, e.value, where: (b) => b.id.equals(e.key));
    }
  });
  await db.batch((batch) => batch.insertAll(db.readingSessions, sessions.rows));
  summary.sessions = sessions.rows.length;

  // ---- 6. Reader notes (private reviews) --------------------------------------
  for (final e in _readerNotes.entries) {
    await repository.setReaderNotes(id(e.key), e.value);
  }
  await (db.update(db.books)).write(
    const BooksCompanion(readerNotesNeedsPush: Value(false)),
  );

  // ---- 7. Highlights, notes and a bookmark in two books ----------------------
  log?.call('marking passages');
  final marks = <AnnotationsCompanion>[];
  Future<void> mark(
    String key,
    String quote, {
    required DateTime at,
    HighlightColor colour = HighlightColor.yellow,
    String? note,
  }) async {
    final epub = (await epubOf(key))!;
    for (var c = 0; c < epub.chapters.length; c++) {
      final hit = resolveOffsets(text: epub.chapters[c].plainText, quote: quote);
      if (hit == null) continue;
      marks.add(AnnotationsCompanion.insert(
        id: const Uuid().v4(),
        bookId: id(key),
        kind: note == null ? 'highlight' : 'note',
        chapter: Value(c),
        page: Value(c + 1),
        locator: Value(
          EpubTextLocator(chapter: c, start: hit.start, end: hit.end).encode(),
        ),
        quotedText: Value(quote),
        note: Value(note),
        color: Value(colour.argb),
        createdAt: Value(at),
        updatedAt: Value(at),
        needsPush: const Value(false),
      ));
      return;
    }
    summary.warnings.add('quote not found in $key: ${quote.substring(0, 30)}…');
  }

  for (final h in _prideHighlights) {
    await mark('pride-and-prejudice', h.quote,
        at: daysAgo(h.daysAgo, hour: 22), colour: h.colour, note: h.note);
  }
  for (final h in _middlemarchHighlights) {
    await mark('middlemarch', h.quote,
        at: daysAgo(h.daysAgo, hour: 22), colour: h.colour, note: h.note);
  }
  // One on the page the reader is on now, so opening the book shows a mark.
  final middlemarch = (await epubOf('middlemarch'))!;
  final current = rows[id('middlemarch')]!;
  final reading = _reading.firstWhere((r) => r.id == 'middlemarch');
  final chapter =
      (reading.progress * middlemarch.chapters.length).floor();
  await mark('middlemarch', _middlemarchToday,
      at: today.subtract(const Duration(hours: 20)),
      colour: HighlightColor.green,
      note: 'Here it comes.'); // i18n-ignore
  marks.add(AnnotationsCompanion.insert(
    id: const Uuid().v4(),
    bookId: current.id,
    kind: 'bookmark',
    chapter: Value(chapter),
    page: Value(chapter + 1),
    locator: Value(EpubScrollLocator(chapter: chapter, fraction: 0).encode()),
    createdAt: Value(today.subtract(const Duration(hours: 20))),
    updatedAt: Value(today.subtract(const Duration(hours: 20))),
    needsPush: const Value(false),
  ));
  await db.batch((batch) => batch.insertAll(db.annotations, marks));
  summary.annotations = marks.length;

  // ---- 8. Shelves ---------------------------------------------------------
  for (final e in _shelves.entries) {
    final shelfId = await repository.createShelf(e.key);
    for (final key in e.value) {
      await repository.addToShelf(id(key), shelfId);
    }
    summary.shelves++;
  }
  await db.update(db.shelves).write(const ShelvesCompanion(needsPush: Value(false)));

  // ---- 9. The room, its two bookcases and what stands on them ----------------
  log?.call('furnishing the room');
  final placed = await _furnish(repository, id, rows: {
    for (final b in await db.select(db.books).get()) b.id: b,
  });
  summary.placed = placed.length;

  // ---- 10. Copies away from the room, and the lending history ---------------
  final copies = <String, String>{...placed};
  for (final key in _looseCopies) {
    copies[key] = await repository.addPhysicalCopy(id(key),
        location: demoRoomName);
  }
  final loanRows = <LoansCompanion>[];
  for (final l in _loans) {
    final copyId = copies[l.id];
    if (copyId == null) {
      summary.warnings.add('no copy of ${l.id} to lend');
      continue;
    }
    final out = daysAgo(l.outDaysAgo, hour: 18);
    loanRows.add(LoansCompanion.insert(
      id: const Uuid().v4(),
      copyId: copyId,
      borrower: l.borrower,
      loanedAt: Value(out),
      dueAt: Value(l.dueDaysAgo == null ? null : daysAgo(l.dueDaysAgo!, hour: 12)),
      returnedAt: Value(
          l.backDaysAgo == null ? null : daysAgo(l.backDaysAgo!, hour: 19)),
      notes: Value(l.note),
      updatedAt: Value(out),
      needsPush: const Value(false),
    ));
  }
  await db.batch((batch) => batch.insertAll(db.loans, loanRows));
  await db.update(db.physicalCopies).write(
        const PhysicalCopiesCompanion(needsPush: Value(false)),
      );
  summary.loans = loanRows.length;
  summary.copies = copies.length;

  // Covers were set during the import; make sure every colour is extracted
  // now rather than on the app's first start.
  await repository.backfillCoverColors();
  log?.call('done');
  return summary;
}

/// The preferences a demo session starts with: past the first-run sheet, a
/// reading goal, a (generic) profile. Theme and language stay at their
/// defaults unless [language] asks otherwise. Written as the
/// `shared_preferences.json` the Linux plugin keeps beside the database.
Map<String, Object> demoPreferences({String? language}) => {
      'flutter.settings.hasSeenFirstRun': true,
      'flutter.settings.readingGoalBooks': 24,
      'flutter.settings.readingGoalMinutes': 30,
      'flutter.profile.name': demoProfileName,
      'flutter.profile.email': demoProfileEmail,
      if (language != null && language.isNotEmpty)
        'flutter.settings.language': language,
    };

// ---------------------------------------------------------------------------
// The story. Days are counted back from the day the library is built.

typedef _Finish = ({String id, int daysAgo, int days, int rating, int readCount});

/// Books finished inside the window: a year and a half, at about the pace of
/// someone with a job — summer holiday bursts, an autumn of gothic novels, a
/// lean November, a long winter Russian.
const List<_Finish> _finished = [
  (id: 'the-time-machine', daysAgo: 541, days: 4, rating: 4, readCount: 1),
  (id: 'a-study-in-scarlet', daysAgo: 529, days: 6, rating: 4, readCount: 1),
  (id: 'the-sign-of-the-four', daysAgo: 516, days: 7, rating: 4, readCount: 1),
  (id: 'the-great-gatsby', daysAgo: 501, days: 5, rating: 5, readCount: 2),
  (id: 'treasure-island', daysAgo: 482, days: 9, rating: 4, readCount: 1),
  (id: 'the-adventures-of-sherlock-holmes', daysAgo: 463, days: 14, rating: 5, readCount: 1),
  (id: 'a-princess-of-mars', daysAgo: 441, days: 5, rating: 4, readCount: 1),
  (id: 'the-gods-of-mars', daysAgo: 433, days: 7, rating: 3, readCount: 1),
  (id: 'the-call-of-the-wild', daysAgo: 425, days: 3, rating: 4, readCount: 1),
  (id: 'around-the-world-in-eighty-days', daysAgo: 418, days: 6, rating: 4, readCount: 1),
  (id: 'jane-eyre', daysAgo: 396, days: 19, rating: 5, readCount: 1),
  (id: 'dracula', daysAgo: 385, days: 15, rating: 4, readCount: 1),
  (id: 'frankenstein', daysAgo: 371, days: 10, rating: 5, readCount: 1),
  (id: 'a-christmas-carol', daysAgo: 334, days: 6, rating: 5, readCount: 2),
  (id: 'the-wind-in-the-willows', daysAgo: 327, days: 6, rating: 4, readCount: 1),
  (id: 'the-hound-of-the-baskervilles', daysAgo: 309, days: 8, rating: 5, readCount: 1),
  (id: 'anne-of-green-gables', daysAgo: 291, days: 12, rating: 5, readCount: 1),
  (id: 'pride-and-prejudice', daysAgo: 274, days: 15, rating: 5, readCount: 3),
  (id: 'anne-of-avonlea', daysAgo: 258, days: 14, rating: 4, readCount: 1),
  (id: 'crime-and-punishment', daysAgo: 229, days: 27, rating: 5, readCount: 1),
  (id: 'the-mysterious-affair-at-styles', daysAgo: 219, days: 5, rating: 4, readCount: 1),
  (id: 'the-art-of-war', daysAgo: 208, days: 3, rating: 4, readCount: 1),
  (id: 'persuasion', daysAgo: 196, days: 10, rating: 5, readCount: 2),
  (id: 'the-picture-of-dorian-gray', daysAgo: 184, days: 8, rating: 4, readCount: 1),
  (id: 'mrs-dalloway', daysAgo: 171, days: 7, rating: 3, readCount: 1),
  (id: 'the-thirty-nine-steps', daysAgo: 160, days: 3, rating: 4, readCount: 1),
  (id: 'the-secret-garden', daysAgo: 150, days: 7, rating: 4, readCount: 1),
  (id: 'the-memoirs-of-sherlock-holmes', daysAgo: 134, days: 11, rating: 4, readCount: 1),
  (id: 'king-solomons-mines', daysAgo: 119, days: 4, rating: 3, readCount: 1),
  (id: 'the-lost-world', daysAgo: 112, days: 5, rating: 4, readCount: 1),
  (id: 'the-warlord-of-mars', daysAgo: 104, days: 6, rating: 3, readCount: 1),
  (id: 'the-age-of-innocence', daysAgo: 87, days: 13, rating: 4, readCount: 1),
  (id: 'the-scarlet-pimpernel', daysAgo: 69, days: 8, rating: 4, readCount: 1),
  (id: 'the-invisible-man', daysAgo: 57, days: 4, rating: 3, readCount: 1),
  (id: 'wuthering-heights', daysAgo: 38, days: 15, rating: 4, readCount: 1),
  (id: 'the-island-of-doctor-moreau', daysAgo: 24, days: 4, rating: 3, readCount: 1),
  (id: 'the-adventures-of-tom-sawyer', daysAgo: 11, days: 8, rating: 4, readCount: 1),
];

/// Read long before, rated from memory.
const _readBefore = {
  'little-women': 4,
  'alices-adventures-in-wonderland': 5,
  'emma': 4,
  'great-expectations': 4,
  'a-tale-of-two-cities': 3,
  'the-jungle-book': 4,
  'sense-and-sensibility': 4,
};

typedef _Reading = ({
  String id,
  double progress,
  int startedDaysAgo,
  int lastReadHoursAgo,
  bool daily,
  bool sparse,
});

/// On the go now. Middlemarch is the nightly book (and the current streak).
const List<_Reading> _reading = [
  (id: 'middlemarch', progress: 0.58, startedDaysAgo: 31, lastReadHoursAgo: 20, daily: true, sparse: false),
  (id: 'the-count-of-monte-cristo', progress: 0.34, startedDaysAgo: 74, lastReadHoursAgo: 150, daily: false, sparse: true),
  (id: 'to-the-lighthouse', progress: 0.14, startedDaysAgo: 4, lastReadHoursAgo: 3, daily: false, sparse: false),
  (id: 'meditations', progress: 0.41, startedDaysAgo: 47, lastReadHoursAgo: 60, daily: false, sparse: true),
];

typedef _Abandoned = ({
  String id,
  double progress,
  int startedDaysAgo,
  int stoppedDaysAgo,
});

const List<_Abandoned> _abandoned = [
  (id: 'moby-dick', progress: 0.31, startedDaysAgo: 262, stoppedDaysAgo: 236),
  (id: 'don-quixote', progress: 0.22, startedDaysAgo: 452, stoppedDaysAgo: 430),
];

/// Unread, and meant to be read soon.
const _toRead = {
  'war-and-peace', 'anna-karenina', 'the-three-musketeers',
  'tess-of-the-durbervilles', 'a-room-with-a-view', 'the-awakening',
  'walden', 'the-prince',
};

const _shelves = <String, List<String>>{
  'To read': [ // i18n-ignore: seeded demo data
    'war-and-peace', 'anna-karenina', 'the-three-musketeers',
    'tess-of-the-durbervilles', 'a-room-with-a-view', 'the-awakening',
    'walden', 'the-prince',
  ],
  'Favourites': [ // i18n-ignore: seeded demo data
    'pride-and-prejudice', 'jane-eyre', 'frankenstein', 'the-great-gatsby',
    'a-christmas-carol', 'crime-and-punishment', 'persuasion',
    'the-hound-of-the-baskervilles', 'anne-of-green-gables',
    'the-adventures-of-sherlock-holmes', 'alices-adventures-in-wonderland',
  ],
  'Adventure': [ // i18n-ignore: seeded demo data
    'treasure-island', 'kidnapped', 'a-princess-of-mars', 'the-gods-of-mars',
    'the-warlord-of-mars', 'tarzan-of-the-apes', 'the-call-of-the-wild',
    'around-the-world-in-eighty-days', 'king-solomons-mines',
    'the-lost-world', 'the-prisoner-of-zenda', 'the-scarlet-pimpernel',
    'the-three-musketeers', 'the-count-of-monte-cristo', 'robinson-crusoe',
  ],
  'Book club': [ // i18n-ignore: seeded demo data
    'the-age-of-innocence', 'mrs-dalloway', 'wuthering-heights',
    'to-the-lighthouse', 'the-awakening',
  ],
};

const _readerNotes = {
  'crime-and-punishment':
      'The fever chapters are the best thing I read all year. Reread part six '
          'before the book club meets.',
  'persuasion': 'Captain Wentworth’s letter. That is the whole review.',
  'moby-dick': 'Stopped at the cetology chapters. Back to it in winter, '
      'with the audiobook maybe.',
  'the-age-of-innocence': 'Book club pick, March. Ana loved it, Mihai did not.',
};

typedef _Mark = ({String quote, int daysAgo, HighlightColor colour, String? note});

const List<_Mark> _prideHighlights = [
  (
    quote: 'It is a truth universally acknowledged, that a single man in '
        'possession of a good fortune, must be in want of a wife.',
    daysAgo: 288,
    colour: HighlightColor.yellow,
    note: null,
  ),
  (
    quote: 'I could easily forgive his pride, if he had not mortified mine.',
    daysAgo: 286,
    colour: HighlightColor.pink,
    note: null,
  ),
  (
    quote: 'I declare after all there is no enjoyment like reading!',
    daysAgo: 284,
    colour: HighlightColor.yellow,
    note: 'Says Caroline Bingley, who is not reading.',
  ),
  (
    quote: 'In vain have I struggled.',
    daysAgo: 281,
    colour: HighlightColor.blue,
    note: null,
  ),
  (
    quote: 'Till this moment, I never knew myself.',
    daysAgo: 278,
    colour: HighlightColor.green,
    note: 'Third time through and this still lands.',
  ),
];

const List<_Mark> _middlemarchHighlights = [
  (
    quote: 'Miss Brooke had that kind of beauty which seems to be thrown into '
        'relief by poor dress.',
    daysAgo: 30,
    colour: HighlightColor.yellow,
    note: null,
  ),
  (
    quote: 'Plain women he regarded as he did the other severe facts of life, '
        'to be faced with philosophy and investigated by science.',
    daysAgo: 26,
    colour: HighlightColor.pink,
    note: 'Lydgate, ladies and gentlemen.',
  ),
  (
    quote: 'If we had a keen vision and feeling of all ordinary human life, it '
        'would be like hearing the grass grow and the squirrel’s heart beat, '
        'and we should die of that roar which lies on the other side of '
        'silence.',
    daysAgo: 21,
    colour: HighlightColor.yellow,
    note: null,
  ),
  (
    quote: 'We are all of us born in moral stupidity, taking the world as an '
        'udder to feed our supreme selves',
    daysAgo: 20,
    colour: HighlightColor.blue,
    note: null,
  ),
];

/// The opening of the chapter the reader is in now (chapter L), so the page
/// the book reopens on carries a fresh mark.
const _middlemarchToday = 'Dorothea had been safe at Freshitt Hall nearly a '
    'week before she had asked any dangerous questions.';

/// Copies that are not in the room — both out on loan.
const _looseCopies = ['the-hound-of-the-baskervilles', 'little-women'];

typedef _Loan = ({
  String id,
  String borrower,
  int outDaysAgo,
  int? dueDaysAgo,
  int? backDaysAgo,
  String? note,
});

/// Two out now (Ana's is overdue), three that came back.
const List<_Loan> _loans = [
  (id: 'the-hound-of-the-baskervilles', borrower: 'Ana', outDaysAgo: 46, dueDaysAgo: 16, backDaysAgo: null, note: 'For her train trip.'),
  (id: 'little-women', borrower: 'Mihai', outDaysAgo: 9, dueDaysAgo: -19, backDaysAgo: null, note: null),
  (id: 'treasure-island', borrower: 'Ioana', outDaysAgo: 214, dueDaysAgo: 184, backDaysAgo: 179, note: null),
  (id: 'dracula', borrower: 'Tom', outDaysAgo: 330, dueDaysAgo: 300, backDaysAgo: 288, note: null),
  (id: 'anne-of-green-gables', borrower: 'Ana', outDaysAgo: 250, dueDaysAgo: 220, backDaysAgo: 226, note: null),
];

// ---------------------------------------------------------------------------
// The room.

/// One shelf's contents, left to right: a book id standing (`'id'`), a book
/// lying flat in a stack (`'_id'`, stacked onto the previous flat book), a
/// prop (`'@plant'`, `'@plant!'` for in front of the books), or a gap in
/// centimetres (`'+4'`).
const _roomShelves = <List<String>>[
  // Left bookcase, bottom to top.
  [
    'war-and-peace', 'the-count-of-monte-cristo', 'don-quixote',
    'anna-karenina', 'middlemarch', '@bookend',
  ],
  [
    'a-study-in-scarlet', 'the-sign-of-the-four',
    'the-adventures-of-sherlock-holmes', 'the-memoirs-of-sherlock-holmes',
    'the-return-of-sherlock-holmes', 'the-valley-of-fear', 'the-lost-world',
    'the-mysterious-affair-at-styles', 'the-innocence-of-father-brown', '+2',
    '@statuette', '+2', '_crime-and-punishment', '_great-expectations',
    '_a-tale-of-two-cities',
  ],
  [
    'pride-and-prejudice', 'sense-and-sensibility', 'emma', 'persuasion',
    'northanger-abbey', 'mansfield-park', '+2', '@vase', '+2', 'jane-eyre',
    'wuthering-heights', 'the-picture-of-dorian-gray',
  ],
  // Right bookcase.
  [
    '@boxes', '+2', 'the-origin-of-species', 'walden', 'robinson-crusoe',
    'leaves-of-grass', 'gullivers-travels', '@bookend',
  ],
  [
    'dracula', 'frankenstein', 'dr-jekyll-and-mr-hyde', 'a-christmas-carol',
    'treasure-island', 'anne-of-green-gables', 'anne-of-avonlea',
    'anne-of-the-island', '+3', '_moby-dick', '_the-war-of-the-worlds',
  ],
  [
    'alices-adventures-in-wonderland', 'through-the-looking-glass',
    'the-wind-in-the-willows', 'the-secret-garden', 'peter-and-wendy',
    'the-jungle-book', 'black-beauty', '+4', '@clock', '+4', '@plant!',
  ],
];

/// Trim formats, so the shelves are not one uniform height.
const _formats = {
  'war-and-peace': 'hardcover', 'the-count-of-monte-cristo': 'hardcover',
  'don-quixote': 'hardcover', 'anna-karenina': 'hardcover',
  'middlemarch': 'hardcover', 'pride-and-prejudice': 'mass',
  'sense-and-sensibility': 'mass', 'emma': 'mass', 'persuasion': 'mass',
  'northanger-abbey': 'mass', 'mansfield-park': 'mass',
  'the-origin-of-species': 'hardcover', 'leaves-of-grass': 'a5',
  'anne-of-green-gables': 'a5', 'anne-of-avonlea': 'a5',
  'anne-of-the-island': 'a5', 'alices-adventures-in-wonderland': 'b5soft',
  'through-the-looking-glass': 'b5soft',
};

/// Builds the room and returns manifest id -> physical copy id for every book
/// placed in it.
Future<Map<String, String>> _furnish(
  LibraryRepository repository,
  String Function(String key) id, {
  required Map<String, Book> rows,
}) async {
  final db = repository.db;
  final layout = repository.layout;
  final roomId = await layout.createEnvironment(demoRoomName);
  // Two narrow three-shelf bookcases side by side: narrow, so a few dozen
  // books fill them the way a few dozen books fill a real one.
  const style = BookcaseStyle.low;
  const width = 0.55, height = 0.95, gap = 0.10;
  final cases = [0.0, width + gap];
  for (final x in cases) {
    await layout.addBookcase(
      roomId,
      bookcaseSegments(
          style: style, x: x, y: 0, width: width, height: height),
    );
  }
  final spacing = height / style.shelves;

  final copies = <String, String>{};
  final copyRows = <PhysicalCopiesCompanion>[];
  final placementRows = <BookPlacementsCompanion>[];
  for (var s = 0; s < _roomShelves.length; s++) {
    final left = cases[s ~/ style.shelves] + 0.012;
    final y = (s % style.shelves) * spacing;
    var x = left;
    double? stackX;
    var stackY = y;
    for (final item in _roomShelves[s]) {
      if (item.startsWith('+')) {
        x += int.parse(item.substring(1)) / 100;
        stackX = null;
        continue;
      }
      if (item.startsWith('@')) {
        final front = item.endsWith('!');
        final kind = PropKind.values
            .byName(item.substring(1, front ? item.length - 1 : null));
        final propId = await layout.addProp(roomId, kind: kind, x: x, y: y);
        if (front) await layout.setPropInFront(propId, true);
        // A plant's leaves overhang its pot: books may tuck under them.
        x += kind.width * kind.solidWidthFraction + 0.004;
        stackX = null;
        continue;
      }
      final flat = item.startsWith('_');
      final key = flat ? item.substring(1) : item;
      final book = rows[id(key)]!;
      final format = BookFormat.byKey(_formats[key] ?? 'trade');
      final thick = PhysicalMetrics.thickness(book, format: format);
      final tall = PhysicalMetrics.height(book, format: format);
      final copyId = const Uuid().v4();
      copies[key] = copyId;
      copyRows.add(PhysicalCopiesCompanion.insert(
        id: copyId,
        bookId: book.id,
        location: const Value(demoRoomName),
        needsPush: const Value(false),
      ));
      double px, py;
      if (flat) {
        // Lying down: as wide as the book is tall, as high as it is thick.
        if (stackX == null) {
          stackX = x;
          stackY = y;
          x += tall + 0.004;
        }
        px = stackX;
        py = stackY;
        stackY += thick;
      } else {
        px = x;
        py = y;
        x += thick + 0.0015;
        stackX = null;
      }
      placementRows.add(BookPlacementsCompanion.insert(
        id: const Uuid().v4(),
        environmentId: roomId,
        copyId: copyId,
        x: px,
        y: py,
        rotation: Value(flat ? 90 : 0),
        format: Value(format?.key),
      ));
    }
  }
  await db.batch((batch) {
    batch.insertAll(db.physicalCopies, copyRows);
    batch.insertAll(db.bookPlacements, placementRows);
  });
  return copies;
}

// ---------------------------------------------------------------------------
// Reading sittings.

/// Makes sittings shaped like a person's: most evenings, more at weekends, now
/// and then a commute or a lunch break, long Sunday afternoons, and the pages
/// of a book spread across its sittings in proportion to their length.
class _SessionWriter {
  _SessionWriter(this.r);

  final Random r;
  final rows = <ReadingSessionsCompanion>[];

  /// Per day, the minutes already taken, so two books never share a sitting.
  final _busy = <DateTime, List<(DateTime, DateTime)>>{};
  var _n = 0;

  static const _devices = ['Tablet', 'Phone', 'Laptop']; // i18n-ignore: data

  void read(
    String bookId, {
    required DateTime from,
    required DateTime to,
    required int startPage,
    required int endPage,
    bool daily = false,
    bool sparse = false,
  }) {
    final sittings = <(DateTime, DateTime, String)>[];
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    for (var day = first;
        !day.isAfter(last);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final weekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      final edge = day == first || day == last;
      var chance = weekend ? 0.85 : 0.62;
      if (daily) chance = 1;
      if (sparse) chance = weekend ? 0.45 : 0.25;
      if (!edge && r.nextDouble() > chance) continue;

      // The evening sitting, in bed or on the sofa.
      final evening = weekend && r.nextDouble() < 0.55
          ? _at(day, 14 + r.nextInt(4), r.nextInt(60))
          : _at(day, 21 + r.nextInt(2), r.nextInt(60));
      final long = weekend ? 35 + r.nextInt(80) : 14 + r.nextInt(38);
      sittings.add((evening, evening.add(Duration(minutes: long)),
          evening.hour < 18 ? 'Laptop' : _devices[r.nextInt(2) == 0 ? 0 : 2]));
      // Sometimes a commute or a lunch break as well.
      if (!weekend && r.nextDouble() < 0.28) {
        final morning = r.nextBool()
            ? _at(day, 8, 5 + r.nextInt(20))
            : _at(day, 12, 30 + r.nextInt(15));
        sittings.add((morning,
            morning.add(Duration(minutes: 8 + r.nextInt(18))), 'Phone'));
      }
    }
    // A sitting cannot end after the moment the story says reading stopped.
    final kept = <(DateTime, DateTime, String)>[];
    for (final s in sittings) {
      var (start, end, device) = s;
      if (end.isAfter(to)) {
        end = to;
        start = to.subtract(Duration(minutes: 10 + r.nextInt(25)));
      }
      final day = DateTime(start.year, start.month, start.day);
      final taken = _busy.putIfAbsent(day, () => []);
      if (taken.any((t) => start.isBefore(t.$2) && t.$1.isBefore(end))) {
        // Already reading something else then: an hour later instead.
        start = start.add(const Duration(minutes: 70));
        end = end.add(const Duration(minutes: 70));
        if (taken.any((t) => start.isBefore(t.$2) && t.$1.isBefore(end))) {
          continue;
        }
      }
      taken.add((start, end));
      kept.add((start, end, device));
    }
    if (kept.isEmpty) return;
    kept.sort((a, b) => a.$1.compareTo(b.$1));

    // Pages in proportion to minutes, with a little pace noise.
    final weights = [
      for (final s in kept)
        s.$2.difference(s.$1).inMinutes * (0.75 + r.nextDouble() * 0.5),
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    var page = startPage;
    var acc = 0.0;
    for (var i = 0; i < kept.length; i++) {
      acc += weights[i];
      final next = i == kept.length - 1
          ? endPage
          : startPage + ((endPage - startPage) * acc / total).round();
      rows.add(ReadingSessionsCompanion.insert(
        id: 'demo-session-${_n++}',
        bookId: bookId,
        startedAt: kept[i].$1,
        endedAt: kept[i].$2,
        startPage: Value(page),
        endPage: Value(next),
        deviceLabel: Value(kept[i].$3),
        needsPush: const Value(false),
      ));
      page = next;
    }
  }

  /// Ten days of listening ending yesterday: (days ago, hour, minute,
  /// minutes) per sitting, at normal speed. Returns where it stopped, in
  /// seconds from the start of the book.
  int listen(String bookId, {required DateTime today}) {
    const plan = [
      (10, 8, 6, 24), (9, 8, 2, 21), (8, 19, 40, 14), (6, 8, 9, 19),
      (5, 8, 4, 16), (3, 21, 15, 23), (1, 8, 3, 17),
    ];
    var at = 0;
    for (final (daysAgo, hour, minute, long) in plan) {
      final start = DateTime(today.year, today.month, today.day - daysAgo,
          hour, minute);
      final end = start.add(Duration(minutes: long));
      final next = at + long * 60;
      rows.add(ReadingSessionsCompanion.insert(
        id: 'demo-session-${_n++}',
        bookId: bookId,
        startedAt: start,
        endedAt: end,
        kind: const Value('listen'),
        startSecond: Value(at),
        endSecond: Value(next),
        deviceLabel: const Value('Phone'), // i18n-ignore: data
        needsPush: const Value(false),
      ));
      at = next;
    }
    return at;
  }

  static DateTime _at(DateTime day, int hour, int minute) =>
      DateTime(day.year, day.month, day.day, hour, minute);
}

// ---------------------------------------------------------------------------
// Sources.

class _Source {
  _Source({
    required this.id,
    required this.use,
    required this.file,
    this.year,
    this.genres = const [],
    this.series,
    this.seriesIndex,
  });

  factory _Source.fromManifest(Map<String, dynamic> m, Directory sources) =>
      _Source(
        id: m['id'] as String,
        use: m['use'] as String,
        file: File(p.join(sources.path, 'epub', m['file'] as String)),
        year: m['year'] as int?,
        genres: [for (final g in (m['genres'] as List? ?? const [])) g as String],
        series: m['series'] as String?,
        seriesIndex: (m['seriesIndex'] as num?)?.toDouble(),
      );

  final String id;

  /// 'library' (an EPUB on the shelf), 'pdf' (typeset into a PDF) or
  /// 'wishlist' (wanted, not owned: only its cover is used).
  final String use;
  final File file;
  final int? year;
  final List<String> genres;
  final String? series;
  final double? seriesIndex;
  _Opf? opf;
}

class _Opf {
  _Opf({
    required this.title,
    required this.authors,
    required this.words,
    this.subtitle,
    this.description,
    this.translator,
  });

  final String title;
  final String? subtitle;
  final List<String> authors;
  final String? translator;
  final String? description;
  final int words;
}

/// Title, authors, description and word count from a Standard Ebooks
/// package file.
_Opf _readOpf(File epub) {
  if (!epub.existsSync()) {
    throw StateError('missing source ${epub.path} — run tool/demo_library.sh');
  }
  final archive = ZipDecoder().decodeBytes(epub.readAsBytesSync());
  String text(String name) {
    final f = archive.findFile(name);
    if (f == null) throw FormatException('$name missing in ${epub.path}');
    return utf8.decode(f.content);
  }

  final container = XmlDocument.parse(text('META-INF/container.xml'));
  final opfPath = container
      .findAllElements('rootfile')
      .first
      .getAttribute('full-path')!;
  final opf = XmlDocument.parse(text(opfPath));
  String? first(String tag) =>
      opf.findAllElements(tag).map((e) => e.innerText.trim()).firstOrNull;
  final roles = <String, String>{
    for (final m in opf.findAllElements('meta'))
      if (m.getAttribute('property') == 'role' &&
          m.getAttribute('refines') != null)
        m.getAttribute('refines')!.substring(1): m.innerText.trim(),
  };
  String? translator;
  for (final c in opf.findAllElements('dc:contributor')) {
    if (roles[c.getAttribute('id')] == 'trl') {
      translator ??= c.innerText.trim();
    }
  }
  String? subtitle;
  for (final t in opf.findAllElements('dc:title')) {
    final tid = t.getAttribute('id');
    final type = opf.findAllElements('meta').where((m) =>
        m.getAttribute('refines') == '#$tid' &&
        m.getAttribute('property') == 'title-type');
    if (type.any((m) => m.innerText.trim() == 'subtitle')) {
      subtitle = t.innerText.trim();
    }
  }
  final words = opf
      .findAllElements('meta')
      .where((m) => m.getAttribute('property') == 'schema:wordCount')
      .map((m) => int.tryParse(m.innerText.trim()))
      .firstOrNull;
  final description = first('dc:description');
  return _Opf(
    title: first('dc:title')!,
    subtitle: subtitle,
    authors: [
      for (final c in opf.findAllElements('dc:creator')) c.innerText.trim(),
    ],
    translator: translator,
    description: description == null ? null : stripHtml(description),
    words: words ?? 60000,
  );
}

/// Typesets [b]'s text as a PDF in [work], once: the bytes are deterministic,
/// so a cached file from an earlier run is the same file.
Future<({String path, int pages})> _typeset(_Source b, Directory work) async {
  final out = File(p.join(work.path, '${b.id}.pdf'));
  final epub = await EpubBook.open(b.file);
  final chapters = <DemoPdfChapter>[];
  final skip = RegExp(
    r'epub:type="[^"]*\b(titlepage|imprint|colophon|copyright-page|'
    r'halftitlepage|endnotes|loi|dedication)\b',
  );
  final block = RegExp(r'<(h[1-6]|p)\b[^>]*>(.*?)</\1>', dotAll: true);
  for (final c in epub.chapters) {
    if (skip.hasMatch(c.html)) continue;
    String? title;
    final paragraphs = <String>[];
    for (final m in block.allMatches(c.html)) {
      final t = stripHtml(m.group(2)!);
      if (t.isEmpty) continue;
      if (m.group(1)!.startsWith('h') && title == null) {
        title = t;
      } else {
        paragraphs.add(t);
      }
    }
    if (paragraphs.isEmpty) continue;
    chapters.add(DemoPdfChapter(
      title: title ?? (c.title.isEmpty ? '' : c.title),
      paragraphs: paragraphs,
    ));
  }
  final opf = b.opf!;
  final pdf = typesetDemoPdf(DemoPdfBook(
    title: opf.title,
    author: opf.authors.join(', '),
    translator: opf.translator,
    coverJpeg: await EpubBook.coverBytes(b.file),
    colophon: 'Typeset for the Vellum demo library from the Standard Ebooks '
        'edition, which is dedicated to the public domain (CC0 1.0).',
    chapters: chapters,
  ));
  if (!out.existsSync() || out.lengthSync() != pdf.bytes.length) {
    out.writeAsBytesSync(pdf.bytes);
  }
  return (path: out.path, pages: pdf.pages);
}


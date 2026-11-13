import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../physical/physical_metrics.dart';
import '../shelf/spine_style.dart';
import 'background_work.dart';
import 'database.dart';
import 'seed_library.dart';

/// The shape of the library the profiling run (`tool/perf_run.sh`,
/// docs/PERFORMANCE.md) measures against.
///
/// [seedLibrary] alone makes books with no covers, no files and no history —
/// which is why every benchmark before the October 2026 round missed where the
/// costs were. This adds what a library that has been *used* for years has:
/// covers (some of them the large PNG page renders old PDF imports left
/// behind), files, a reading history, highlights, lent copies and a room with
/// books on its shelves.
class ProfilingLibrary {
  const ProfilingLibrary({
    this.books = 4000,
    this.coverShare = 0.65,
    this.pngCoverShare = 0.1,
    this.fileShare = 0.5,
    this.sessions = 4000,
    this.annotations = 2000,
    this.looseCopies = 300,
    this.loans = 150,
    this.placed = 400,
    this.seed = 1,
    this.jpegSources = 40,
    this.pngSources = 6,
  });

  /// Reads the shape from `PERF_*` environment variables, for the seeding
  /// tool; anything unset keeps the default above.
  factory ProfilingLibrary.fromEnvironment(Map<String, String> env) {
    int i(String key, int fallback) =>
        int.tryParse(env[key] ?? '') ?? fallback;
    double d(String key, double fallback) =>
        double.tryParse(env[key] ?? '') ?? fallback;
    const base = ProfilingLibrary();
    return ProfilingLibrary(
      books: i('PERF_BOOKS', base.books),
      coverShare: d('PERF_COVER_SHARE', base.coverShare),
      pngCoverShare: d('PERF_PNG_COVER_SHARE', base.pngCoverShare),
      fileShare: d('PERF_FILE_SHARE', base.fileShare),
      sessions: i('PERF_SESSIONS', base.sessions),
      annotations: i('PERF_ANNOTATIONS', base.annotations),
      looseCopies: i('PERF_COPIES', base.looseCopies),
      loans: i('PERF_LOANS', base.loans),
      placed: i('PERF_PLACED', base.placed),
      seed: i('PERF_SEED', base.seed),
    );
  }

  final int books;

  /// Share of books with a cover, and of those, the share that is a large PNG
  /// (a rendered PDF page, as imports made before covers became JPEG).
  final double coverShare;
  final double pngCoverShare;

  /// Share of books with one attached file.
  final double fileShare;

  /// Reading sittings, spread over the last three years.
  final int sessions;
  final int annotations;

  /// Physical copies that are not in the room (the room mints its own).
  final int looseCopies;
  final int loans;

  /// Books standing on the room's shelves.
  final int placed;
  final int seed;

  /// How many distinct cover images the covered books share (see
  /// [seedProfilingLibrary]). Only a test has a reason to want fewer.
  final int jpegSources;
  final int pngSources;

  Map<String, Object> toJson() => {
        'books': books,
        'coverShare': coverShare,
        'pngCoverShare': pngCoverShare,
        'fileShare': fileShare,
        'sessions': sessions,
        'annotations': annotations,
        'looseCopies': looseCopies,
        'loans': loans,
        'placed': placed,
        'seed': seed,
      };
}

/// The one room [seedProfilingLibrary] builds.
const profilingRoomId = 'seed-room-1';
const profilingRoomName = 'Living room'; // i18n-ignore: seeded test data


/// Fills [db] and [dataDir] with a [ProfilingLibrary]. The database must be
/// empty. [epub] is the bytes of a real EPUB (a bundled sample), used for every
/// EPUB file so the reader has something it can open.
///
/// With [linkDuplicates] each book's cover and file is a symbolic link to one
/// of a few dozen source files kept under [sourcesDir] rather than a copy, so
/// a 4,000-book library costs a few megabytes of disk instead of half a
/// gigabyte. The app reads through a link like any file; only the operating
/// system's page cache sees the difference, which is why the profiling run
/// treats every measurement as warm-cache.
///
/// Dates are relative to [now] so the insights' "this week" and streaks have
/// something in them whenever the library is seeded.
Future<void> seedProfilingLibrary(
  VellumDatabase db,
  Directory dataDir, {
  ProfilingLibrary spec = const ProfilingLibrary(),
  required Uint8List epub,
  Directory? sourcesDir,
  bool linkDuplicates = true,
  DateTime? now,
  void Function(String message)? log,
}) async {
  final today = now ?? DateTime.now();
  // Distinct cover images; every covered book gets one of these. Real covers
  // differ byte for byte, but what a spine costs to draw depends on the size
  // and format of its cover, not on what is in it.
  final jpegSources = spec.jpegSources;
  final pngSources = spec.pngSources;
  final sources =
      sourcesDir ?? Directory(p.join(dataDir.path, '..', 'seed-sources'));
  for (final dir in ['covers', 'files']) {
    Directory(p.join(dataDir.path, dir)).createSync(recursive: true);
  }
  sources.createSync(recursive: true);

  // ---- Source images, in the background (they are a few seconds of pixels).
  log?.call('making ${jpegSources + pngSources} source covers');
  final palette = [
    for (var k = 0; k < jpegSources + pngSources; k++)
      _sourceColor(spec.seed * 31 + k),
  ];
  final sourceBytes = await Future.wait([
    for (var k = 0; k < jpegSources + pngSources; k++)
      _sourceInBackground(
        png: k >= jpegSources,
        argb: palette[k].toARGB32(),
        seed: spec.seed * 97 + k,
      ),
  ]);
  final sourcePaths = <String>[];
  for (var k = 0; k < sourceBytes.length; k++) {
    final ext = k < jpegSources ? 'jpg' : 'png';
    final f = File(p.join(sources.path, 'cover-$k.$ext'));
    f.writeAsBytesSync(sourceBytes[k]);
    sourcePaths.add(f.absolute.path);
  }
  final epubSource = File(p.join(sources.path, 'book.epub'))
    ..writeAsBytesSync(epub);
  final pdfBytes = _minimalPdf();
  final pdfSource = File(p.join(sources.path, 'book.pdf'))
    ..writeAsBytesSync(pdfBytes);
  final epubSha = sha256.convert(epub).toString();
  final pdfSha = sha256.convert(pdfBytes).toString();

  void place(String target, String source) {
    final dest = File(target);
    if (dest.existsSync()) dest.deleteSync();
    if (linkDuplicates) {
      Link(target).createSync(source);
    } else {
      File(source).copySync(target);
    }
  }

  // ---- Books (through the plain seeder), decorated as they are inserted.
  final plan = <int, _BookPlan>{};
  log?.call('seeding ${spec.books} books');
  await seedLibrary(
    db,
    count: spec.books,
    seed: spec.seed,
    decorate: (i, row) {
      final r = Random(spec.seed * 1000003 + i);
      final id = row.id.value;
      final title = row.title.value;
      final pages = row.pageCount.value;
      var style = SpineStyle.generate(title: title, pageCount: pages);
      String? coverPath;
      if (r.nextDouble() < spec.coverShare) {
        final png = r.nextDouble() < spec.pngCoverShare;
        final k = png
            ? jpegSources + r.nextInt(pngSources)
            : r.nextInt(jpegSources);
        coverPath = p.join('covers', '$id.${png ? 'png' : 'jpg'}');
        place(p.join(dataDir.path, coverPath), sourcePaths[k]);
        // As the startup backfill would have left it: a library that has
        // been opened before has every cover's colour already extracted.
        style = style.withCoverColor(palette[k]);
      }
      final created = today.subtract(Duration(days: r.nextInt(5 * 365)));
      final roll = r.nextDouble();
      final b = _BookPlan(id: id, pages: pages ?? 220);
      plan[i] = b;
      var out = row.copyWith(
        spineStyle: Value(style.toJson()),
        coverPath: Value(coverPath),
        description: Value(
          r.nextBool() ? _description(r) : null,
        ),
        createdAt: Value(created),
        updatedAt: Value(created),
        needsPush: const Value(false),
      );
      if (roll < 0.10) {
        final finished = today.subtract(Duration(days: r.nextInt(3 * 365)));
        b.status = 'finished';
        out = out.copyWith(
          status: const Value('finished'),
          startedAt: Value(finished.subtract(Duration(days: 3 + r.nextInt(40)))),
          finishedAt: Value(finished),
          rating: Value(1 + r.nextInt(5)),
          readCount: const Value(1),
          readingProgress: const Value(1.0),
          lastReadAt: Value(finished),
        );
      } else if (roll < 0.13) {
        b.status = 'reading';
        final page = 1 + r.nextInt(b.pages);
        out = out.copyWith(
          status: const Value('reading'),
          startedAt: Value(today.subtract(Duration(days: 1 + r.nextInt(60)))),
          readingProgress: Value(page / b.pages),
          lastReadPage: Value(page),
          lastReadAt: Value(today.subtract(Duration(hours: r.nextInt(24 * 30)))),
        );
      } else if (roll < 0.14) {
        out = out.copyWith(status: const Value('abandoned'));
      } else if (roll < 0.16) {
        out = out.copyWith(status: const Value('wishlist'));
      } else if (roll < 0.17) {
        // In the trash, recently enough that the sweep leaves it alone — so
        // every run of the same seed starts from the same library.
        out = out.copyWith(
          deletedAt: Value(today.subtract(Duration(days: r.nextInt(10)))),
        );
      }
      b.hasFile = r.nextDouble() < spec.fileShare;
      b.epub = r.nextDouble() < 0.7;
      return out;
    },
  );

  // ---- Files.
  log?.call('attaching files');
  final fileRows = <BookFilesCompanion>[];
  for (final b in plan.values) {
    if (!b.hasFile) continue;
    final ext = b.epub ? 'epub' : 'pdf';
    final fileId = 'seed-file-${b.id.substring('seed-book-'.length)}';
    final rel = p.join('files', '$fileId.$ext');
    place(
      p.join(dataDir.path, rel),
      (b.epub ? epubSource : pdfSource).absolute.path,
    );
    fileRows.add(BookFilesCompanion.insert(
      id: fileId,
      bookId: b.id,
      format: ext,
      path: rel,
      sizeBytes: b.epub ? epub.length : pdfBytes.length,
      sha256: b.epub ? epubSha : pdfSha,
    ));
  }
  await db.batch((batch) => batch.insertAll(db.bookFiles, fileRows));

  final rng = Random(spec.seed * 7 + 3);
  final shelfBooks = [
    for (final b in plan.values)
      if (b.status != 'wishlist') b,
  ];
  final readBooks = [
    for (final b in shelfBooks)
      if (b.status == 'finished' || b.status == 'reading') b,
  ];

  // ---- Reading sittings: most days of the last three years, evenings mostly.
  log?.call('seeding ${spec.sessions} reading sessions');
  const days = 3 * 365;
  const devices = ['Pixel 8', 'Desktop', 'Tablet']; // i18n-ignore: test data
  final sessionRows = <ReadingSessionsCompanion>[];
  final perDay = max(1.0, spec.sessions / (days * 0.6));
  var made = 0;
  // Newest first, so that however the count falls, the recent days are the
  // ones that have reading in them.
  for (var d = 0; d < days && made < spec.sessions; d++) {
    // The last fortnight always has reading in it, so "this week" and the
    // streak are never empty whatever the seed.
    if (d > 14 && rng.nextDouble() > 0.6) continue;
    final day = DateTime(today.year, today.month, today.day - d);
    final count = max(1, (perDay * (0.5 + rng.nextDouble())).round());
    for (var s = 0; s < count && made < spec.sessions; s++) {
      final book = readBooks.isEmpty
          ? shelfBooks[rng.nextInt(shelfBooks.length)]
          : readBooks[rng.nextInt(readBooks.length)];
      final hour = rng.nextDouble() < 0.6 ? 19 + rng.nextInt(5) : 6 + rng.nextInt(13);
      final start = day.add(Duration(hours: hour, minutes: rng.nextInt(60)));
      final minutes = 5 + rng.nextInt(85);
      final startPage = rng.nextInt(book.pages);
      sessionRows.add(ReadingSessionsCompanion.insert(
        id: 'seed-session-$made',
        bookId: book.id,
        startedAt: start,
        endedAt: start.add(Duration(minutes: minutes)),
        startPage: Value(startPage),
        endPage: Value(min(book.pages, startPage + (minutes * 0.7).round())),
        deviceLabel: Value(devices[rng.nextInt(devices.length)]),
        needsPush: const Value(false),
      ));
      made++;
    }
  }
  await db.batch((batch) => batch.insertAll(db.readingSessions, sessionRows));

  // ---- Highlights, notes and bookmarks, in books that have a file.
  log?.call('seeding ${spec.annotations} annotations');
  final withFiles = [
    for (final b in shelfBooks)
      if (b.hasFile) b,
  ];
  const kinds = ['highlight', 'highlight', 'highlight', 'note', 'bookmark'];
  await db.batch((batch) => batch.insertAll(db.annotations, [
        if (withFiles.isNotEmpty)
          for (var a = 0; a < spec.annotations; a++)
            () {
              final book = withFiles[rng.nextInt(min(250, withFiles.length))];
              final kind = kinds[rng.nextInt(kinds.length)];
              final at = today.subtract(Duration(hours: rng.nextInt(24 * 900)));
              return AnnotationsCompanion.insert(
                id: 'seed-annotation-$a',
                bookId: book.id,
                kind: kind,
                page: Value(rng.nextInt(book.pages)),
                quotedText: Value(kind == 'bookmark' ? null : _description(rng)),
                note: Value(kind == 'note' ? _description(rng) : null),
                color: Value(rng.nextBool() ? 0xFFFFEB3B : 0xFF81C784),
                createdAt: Value(at),
                updatedAt: Value(at),
                needsPush: const Value(false),
              );
            }(),
      ]));

  // ---- Loose physical copies, some of them lent out.
  log?.call('seeding ${spec.looseCopies} copies and ${spec.loans} loans');
  final copyIds = [
    for (var c = 0; c < spec.looseCopies; c++) 'seed-copy-$c',
  ];
  await db.batch((batch) {
    batch.insertAll(db.physicalCopies, [
      for (var c = 0; c < copyIds.length; c++)
        PhysicalCopiesCompanion.insert(
          id: copyIds[c],
          bookId: shelfBooks[rng.nextInt(shelfBooks.length)].id,
          location: Value('Shelf ${1 + rng.nextInt(9)}'), // i18n-ignore
          needsPush: const Value(false),
        ),
    ]);
    batch.insertAll(db.loans, [
      if (copyIds.isNotEmpty)
        for (var l = 0; l < spec.loans; l++)
          () {
            final out = today.subtract(Duration(days: 1 + rng.nextInt(700)));
            final active = l < spec.loans ~/ 4;
            return LoansCompanion.insert(
              id: 'seed-loan-$l',
              copyId: copyIds[l % copyIds.length],
              borrower: 'Friend ${l % 23}', // i18n-ignore: test data
              loanedAt: Value(out),
              returnedAt: Value(
                active ? null : out.add(Duration(days: 3 + rng.nextInt(60))),
              ),
              dueAt: Value(active ? out.add(const Duration(days: 30)) : null),
              needsPush: const Value(false),
            );
          }(),
    ]);
  });

  // ---- A room: three bookcases of five shelves, filled left to right.
  log?.call('building a room with ${spec.placed} books');
  await db.into(db.physicalEnvironments).insert(
        PhysicalEnvironmentsCompanion.insert(
          id: profilingRoomId,
          name: profilingRoomName,
        ),
      );
  final shelfRows = <PhysicalShelvesCompanion>[];
  final copyRows = <PhysicalCopiesCompanion>[];
  final placementRows = <BookPlacementsCompanion>[];
  var placedCount = 0;
  final bookRows = await (db.select(db.books)
        ..where((b) => b.deletedAt.isNull() & b.status.equals('wishlist').not())
        ..limit(max(1, spec.placed)))
      .get();
  outer:
  for (var caseIndex = 0;; caseIndex++) {
    final left = caseIndex * 1.0;
    final right = left + 0.9;
    for (var level = 0; level < 5; level++) {
      final y = 0.1 + level * 0.36;
      shelfRows.add(PhysicalShelvesCompanion.insert(
        id: 'seed-pshelf-$caseIndex-$level',
        environmentId: profilingRoomId,
        x1: left,
        y1: y,
        x2: right,
        y2: y,
      ));
      var x = left + 0.01;
      while (placedCount < spec.placed && placedCount < bookRows.length) {
        final book = bookRows[placedCount];
        final w = PhysicalMetrics.thickness(book);
        if (x + w > right) break;
        final copyId = 'seed-pcopy-$placedCount';
        copyRows.add(PhysicalCopiesCompanion.insert(
          id: copyId,
          bookId: book.id,
          needsPush: const Value(false),
        ));
        placementRows.add(BookPlacementsCompanion.insert(
          id: 'seed-placement-$placedCount',
          environmentId: profilingRoomId,
          copyId: copyId,
          x: x,
          y: y,
        ));
        x += w + 0.001;
        placedCount++;
      }
      if (placedCount >= spec.placed || placedCount >= bookRows.length) {
        break outer;
      }
    }
  }
  await db.batch((batch) {
    batch.insertAll(db.physicalShelves, shelfRows);
    batch.insertAll(db.physicalCopies, copyRows);
    batch.insertAll(db.bookPlacements, placementRows);
  });
  log?.call('done');
}

/// One source image, made in a background isolate. A function of its own so
/// the closure sent to the isolate captures three plain values and nothing
/// else — a closure written inline would carry the seeder's whole scope,
/// database connection included, which cannot cross an isolate boundary.
Future<Uint8List> _sourceInBackground({
  required bool png,
  required int argb,
  required int seed,
}) =>
    inBackground(
      () => png ? _pngPage(Color(argb), seed) : _jpegCover(Color(argb), seed),
    );

class _BookPlan {
  _BookPlan({required this.id, required this.pages});

  final String id;
  final int pages;
  String status = 'unread';
  bool hasFile = false;
  bool epub = true;
}

Color _sourceColor(int seed) {
  final r = Random(seed);
  return Color.fromARGB(
    255,
    40 + r.nextInt(200),
    40 + r.nextInt(200),
    40 + r.nextInt(200),
  );
}

img.ColorRgb8 _rgb(Color c) => img.ColorRgb8(
      (c.r * 255).round(),
      (c.g * 255).round(),
      (c.b * 255).round(),
    );

/// A 600×900 cover: a gradient in [base], a few shapes, and grain — enough
/// texture that it compresses to about what a real cover does (~100 KB).
Uint8List _jpegCover(Color base, int seed) {
  final r = Random(seed);
  final image = img.Image(width: 600, height: 900);
  final c = _rgb(base);
  for (var y = 0; y < image.height; y++) {
    final shade = 1.0 - 0.5 * y / image.height;
    for (var x = 0; x < image.width; x++) {
      final grain = r.nextInt(40) - 20;
      image.setPixelRgb(
        x,
        y,
        (c.r * shade + grain).clamp(0, 255).toInt(),
        (c.g * shade + grain).clamp(0, 255).toInt(),
        (c.b * shade + grain).clamp(0, 255).toInt(),
      );
    }
  }
  for (var s = 0; s < 6; s++) {
    img.fillRect(
      image,
      x1: r.nextInt(600),
      y1: r.nextInt(900),
      x2: r.nextInt(600),
      y2: r.nextInt(900),
      color: img.ColorRgb8(r.nextInt(256), r.nextInt(256), r.nextInt(256)),
    );
  }
  return img.encodeJpg(image, quality: 85);
}

/// A 908×1200 PNG of a "page": white, lines of grey text, a photo block —
/// the shape of the PDF first-page renders older imports stored as covers.
Uint8List _pngPage(Color accent, int seed) {
  final r = Random(seed);
  final image = img.Image(width: 908, height: 1200)
    ..clear(img.ColorRgb8(255, 255, 255));
  for (var line = 0; line < 50; line++) {
    final y = 80 + line * 22;
    var x = 80;
    while (x < 820) {
      final w = 10 + r.nextInt(60);
      img.fillRect(
        image,
        x1: x,
        y1: y,
        x2: min(828, x + w),
        y2: y + 9,
        color: img.ColorRgb8(60, 60, 60),
      );
      x += w + 8;
    }
  }
  final a = _rgb(accent);
  for (var y = 300; y < 700; y++) {
    for (var x = 150; x < 760; x++) {
      final grain = r.nextInt(90) - 45;
      image.setPixelRgb(
        x,
        y,
        (a.r + grain).clamp(0, 255).toInt(),
        (a.g + grain).clamp(0, 255).toInt(),
        (a.b + grain).clamp(0, 255).toInt(),
      );
    }
  }
  return img.encodePng(image);
}

/// A one-page PDF with a line of text, small enough to write by hand and
/// valid enough for PDFium to open.
Uint8List _minimalPdf() {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 595] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    null, // the content stream, below
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  const text = 'BT /F1 18 Tf 60 520 Td (Vellum profiling) Tj ET';
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var k = 0; k < objects.length; k++) {
    offsets.add(out.length);
    final body = objects[k] ??
        '<< /Length ${text.length} >>\nstream\n$text\nendstream';
    out.write('${k + 1} 0 obj\n$body\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    out.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(out.toString().codeUnits);
}

const _words = [
  'light', 'river', 'memory', 'winter', 'letters', 'quiet', 'harbour',
  'stone', 'garden', 'city', 'night', 'promise', 'distance', 'fire',
  'window', 'salt', 'iron', 'summer', 'voices', 'paper',
];

String _description(Random r) => [
      for (var w = 0; w < 20 + r.nextInt(40); w++)
        _words[r.nextInt(_words.length)],
    ].join(' ');

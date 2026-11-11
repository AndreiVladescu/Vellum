import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart' show ScaffoldMessengerState, SnackBarAction, Text;
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';
import '../data/library_repository.dart';
import '../import/catalog_entry.dart';
import '../import/folder_import_service.dart';
import '../import/import_plan.dart';
import '../l10n/gen/app_localizations.dart';
import '../snack_bars.dart';

/// One bundled book. The metadata is stated here rather than read back out of
/// the EPUB: an EPUB's `dc:date` is the *edition's* date (Standard Ebooks
/// stamps its own release), not the year the book came out.
class SampleBook {
  const SampleBook({
    required this.asset,
    required this.title,
    required this.author,
    required this.year,
    required this.description,
  });

  final String asset;
  final String title;
  final String author;
  final int year;
  final String description;
}

/// What [SampleLibrary.add] did.
class SampleAddResult {
  const SampleAddResult({required this.added, required this.alreadyThere});

  /// Books created by this call.
  final int added;

  /// Samples skipped because the library already held that file (or a book
  /// that looks like it) — what makes pressing the button twice harmless.
  final int alreadyThere;
}

/// A few bundled public-domain books, so a new install has spines to look at
/// (first-run sample library).
///
/// **No second import path.** Each EPUB is written to a temp file and goes
/// through [FolderImportService] — the same hash-based duplicate check, the
/// same `attachFile` (atomic copy, hash, embedded cover) that every other
/// import uses. The only thing added here is the metadata, passed as a
/// [CatalogEntry] exactly as a Calibre or OPDS import does.
///
/// **No schema change; the markers already exist.**
/// - The books go on a shelf called [shelfName] (ordinary shelf machinery), so
///   they are easy to see and to filter to.
/// - They are set `syncExcluded`, the existing per-device "keep this book on
///   this device only" switch. That is what keeps them from being pushed if a
///   server is connected later: sample books are not the user's library, and
///   publishing four copies of Frankenstein to a shared library would be rude.
///   It is also the second half of how a sample is *recognised* for removal
///   (see [remove]); the first half is the file hash.
class SampleLibrary {
  SampleLibrary(this.repository, {AssetBundle? bundle})
      : _bundle = bundle ?? rootBundle;

  final LibraryRepository repository;
  final AssetBundle _bundle;

  static const shelfName = 'Samples';

  /// Four books of clearly different lengths, so the spines differ in
  /// thickness. All from Standard Ebooks; see `assets/samples/README.md`.
  static const books = [
    SampleBook(
      asset: 'assets/samples/the-importance-of-being-earnest.epub',
      title: 'The Importance of Being Earnest', // i18n-ignore
      author: 'Oscar Wilde',
      year: 1895,
      description: 'A trivial comedy for serious people.',
    ),
    SampleBook(
      asset: 'assets/samples/the-time-machine.epub',
      title: 'The Time Machine', // i18n-ignore
      author: 'H. G. Wells',
      year: 1895,
      description: 'A Victorian inventor travels to the year 802,701.',
    ),
    SampleBook(
      asset: 'assets/samples/frankenstein.epub',
      title: 'Frankenstein', // i18n-ignore
      author: 'Mary Shelley',
      year: 1818,
      description: 'Or, the Modern Prometheus.',
    ),
    SampleBook(
      asset: 'assets/samples/the-adventures-of-sherlock-holmes.epub',
      title: 'The Adventures of Sherlock Holmes', // i18n-ignore
      author: 'Arthur Conan Doyle',
      year: 1892,
      description: 'Twelve cases from the consulting detective.',
    ),
  ];

  Future<List<String>>? _hashes;

  /// The sha256 of every bundled file, which is what ties a library book back
  /// to a sample. Computed once from the asset bytes.
  Future<List<String>> _sampleHashes() => _hashes ??= () async {
        return [
          for (final b in books)
            sha256
                .convert((await _bundle.load(b.asset)).buffer.asUint8List())
                .toString(),
        ];
      }();

  /// Adds the samples that are not already in the library, on the [shelfName]
  /// shelf. Safe to call repeatedly.
  Future<SampleAddResult> add() async {
    final temp = await Directory.systemTemp.createTemp('vellum_samples');
    try {
      final entries = <CatalogEntry>[];
      for (final b in books) {
        final bytes = await _bundle.load(b.asset);
        final file = File(p.join(temp.path, p.basename(b.asset)));
        await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
        entries.add(CatalogEntry(
          title: b.title,
          authors: [b.author],
          year: b.year,
          description: b.description,
          filePath: file.path,
        ));
      }

      final importer = FolderImportService(repository);
      final candidates = await importer.scanEntries(entries);
      // Only the certain-new ones. A "probable duplicate" is a book the user
      // already has under the same title and author; adding a second
      // Frankenstein next to theirs is the opposite of helpful.
      final fresh = [
        for (final c in candidates)
          if (c.status == ImportStatus.newBook) c,
      ];
      if (fresh.isEmpty) {
        return SampleAddResult(added: 0, alreadyThere: candidates.length);
      }

      final shelfId = await _shelfId();
      final report =
          await importer.import(fresh, shelfId: shelfId, localOnly: true);
      final ids = [
        for (final o in report.outcomes)
          if (o.bookId != null) o.bookId!,
      ];

      final db = repository.db;
      // Creating the shelf and filling it marked it dirty. It is a harmless
      // row, but nothing about it is worth pushing: its only members are
      // device-only books. A later rename or edit by the user marks it again.
      await (db.update(db.shelves)..where((s) => s.id.equals(shelfId)))
          .write(const ShelvesCompanion(needsPush: Value(false)));

      return SampleAddResult(
        added: ids.length,
        alreadyThere: candidates.length - fresh.length,
      );
    } finally {
      try {
        await temp.delete(recursive: true);
      } catch (_) {
        // Temp files; the OS sweeps them.
      }
    }
  }

  Future<String> _shelfId() async {
    final db = repository.db;
    final existing = await (db.select(db.shelves)
          ..where((s) => s.name.equals(shelfName))
          ..limit(1))
        .getSingleOrNull();
    return existing?.id ?? await repository.createShelf(shelfName);
  }

  JoinedSelectStatement<HasResultSet, dynamic> _presentQuery(
      List<String> hashes) {
    final db = repository.db;
    return db.select(db.books).join([
      innerJoin(db.bookFiles, db.bookFiles.bookId.equalsExp(db.books.id)),
    ])
      ..where(db.bookFiles.sha256.isIn(hashes) &
          db.books.syncExcluded.equals(true) &
          db.books.deletedAt.isNull());
  }

  /// The books currently in the library that are samples: a bundled file's
  /// hash **and** device-only. Requiring both means a user's own copy of the
  /// same EPUB (which they have chosen to sync) is never swept up.
  Future<List<Book>> _present() async {
    final hashes = await _sampleHashes();
    final query = _presentQuery(hashes);
    return [
      for (final row in await query.get()) row.readTable(repository.db.books),
    ];
  }

  /// Live count of samples in the library, for the settings tile.
  Stream<int> watchCount() async* {
    final hashes = await _sampleHashes();
    final query = _presentQuery(hashes);
    yield* query.watch().map((rows) => rows.length);
  }

  /// Deletes every sample book (and the now-empty [shelfName] shelf), and
  /// returns how many books went.
  ///
  /// Deleted for good rather than trashed: they were never the user's, they
  /// can be added again in one tap, and a trash full of Frankenstein is noise.
  /// No tombstone is recorded — device-only books were never pushed, so there
  /// is nothing on a server to delete.
  Future<int> remove() async {
    final present = await _present();
    for (final book in present) {
      await repository.deleteBook(book, recordTombstone: false);
    }
    final db = repository.db;
    final shelf = await (db.select(db.shelves)
          ..where((s) => s.name.equals(shelfName))
          ..limit(1))
        .getSingleOrNull();
    if (shelf != null) {
      final left = await (db.select(db.shelfBooks)
            ..where((sb) => sb.shelfId.equals(shelf.id)))
          .get();
      // Only if empty: if the user has put their own books on it, it has
      // become their shelf.
      if (left.isEmpty) {
        await repository.deleteShelf(shelf.id, recordTombstone: false);
      }
    }
    return present.length;
  }
}

/// Adds the samples and tells the user what happened, in one place so the
/// shelf's button, the first-run card and the Settings row all say the same
/// thing. Takes the messenger rather than a context so it is safe across the
/// awaits.
Future<void> addSamplesWithFeedback(
  ScaffoldMessengerState messenger,
  L10n l10n,
  SampleLibrary samples,
) async {
  final SampleAddResult result;
  try {
    result = await samples.add();
  } catch (e) {
    messenger.showSnackBar(
      appSnackBar(content: Text(l10n.samplesAddFailedSnack('$e'))),
    );
    return;
  }
  messenger.showSnackBar(appSnackBar(
    content: Text(result.added == 0
        ? l10n.samplesAlreadyThereSnack
        : l10n.samplesAddedSnack(result.added, SampleLibrary.shelfName)),
    action: SnackBarAction(label: l10n.samplesRemoveAction, onPressed: () => samples.remove()),
  ));
}

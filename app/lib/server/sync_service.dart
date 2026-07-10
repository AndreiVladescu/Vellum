import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../shelf/spine_style.dart';
import 'server_client.dart';

/// One thing that went wrong for a single book during a sync. Collected rather
/// than swallowed, so a half-synced library is diagnosable instead of looking
/// identical to a clean one.
class SyncIssue {
  SyncIssue({
    required this.bookId,
    required this.title,
    required this.stage,
    required this.message,
  });

  final String bookId;
  final String title;

  /// Where it failed: 'delete', 'cover', 'file', 'render', 'push', ...
  final String stage;
  final String message;
}

/// The outcome of a pull or push: counts plus any per-book failures.
class SyncReport {
  SyncReport({
    this.pulled = 0,
    this.pushed = 0,
    this.deletedLocally = 0,
    this.deletedRemotely = 0,
    this.issues = const [],
  });

  final int pulled;
  final int pushed;
  final int deletedLocally;
  final int deletedRemotely;
  final List<SyncIssue> issues;

  bool get hasIssues => issues.isNotEmpty;
}

/// Progress signal: [done] of [total] items processed in the named [phase].
typedef SyncProgress = void Function(int done, int total, String phase);

/// Two-way sync between the local library and a Vellum server. Owns no state of
/// its own beyond a re-entrancy guard; it operates on the [repository]'s
/// database and file store. Kept separate from [LibraryRepository] because sync
/// has distinct dependencies (a server client) and side effects (a "pull" also
/// pushes covers back). Reuse one instance so [pull]/[push] can't overlap.
class SyncService {
  SyncService(this.repository);

  final LibraryRepository repository;

  /// How many blob transfers (cover/file up/downloads) run at once. Independent
  /// transfers otherwise serialize into a sum-of-latencies; 4 keeps a personal
  /// server comfortable. DB writes still serialize inside drift.
  static const _blobConcurrency = 4;

  /// True while a pull or push is in flight; a second concurrent call throws.
  bool _running = false;

  /// Whether a pull/push/sync is currently in flight. Callers use this to
  /// disable actions (e.g. restore) that must not run concurrently with a sync.
  bool get isRunning => _running;

  VellumDatabase get _db => repository.db;
  Directory get _dataDir => repository.dataDir;

  /// Pulls the server library onto this device: applies the server's deletions,
  /// upserts book metadata (last-write-wins by `updatedAt`), downloads covers
  /// and files we don't already hold, and renders+pushes back covers for books
  /// the server has none for.
  ///
  /// [cursor] is the server clock from the previous pull; when set, only rows
  /// changed since it are fetched (delta pull). On success [onCursor] is called
  /// with the new server clock to persist for next time. [onProgress] reports
  /// blob-transfer progress. Returns a [SyncReport] with counts and any issues.
  Future<SyncReport> pull(
    VellumServerClient client, {
    String? cursor,
    void Function(String serverNow)? onCursor,
    SyncProgress? onProgress,
  }) async {
    if (_running) {
      throw StateError('a sync is already in progress');
    }
    _running = true;
    try {
      return await _pull(
        client,
        cursor: cursor,
        onCursor: onCursor,
        onProgress: onProgress,
      );
    } finally {
      _running = false;
    }
  }

  /// Full two-way sync in one guarded run: pull first (the server is the
  /// ground truth for anything edited elsewhere), then push whatever is still
  /// locally dirty. Returns the two phases' reports merged into one.
  Future<SyncReport> sync(
    VellumServerClient client, {
    String? cursor,
    void Function(String serverNow)? onCursor,
    SyncProgress? onProgress,
  }) async {
    if (_running) {
      throw StateError('a sync is already in progress');
    }
    _running = true;
    try {
      final pulled = await _pull(
        client,
        cursor: cursor,
        onCursor: onCursor,
        onProgress: onProgress,
      );
      final pushed = await _push(client, onProgress: onProgress);
      return SyncReport(
        pulled: pulled.pulled,
        pushed: pushed.pushed,
        deletedLocally: pulled.deletedLocally,
        deletedRemotely: pushed.deletedRemotely,
        issues: [...pulled.issues, ...pushed.issues],
      );
    } finally {
      _running = false;
    }
  }

  Future<SyncReport> _pull(
    VellumServerClient client, {
    String? cursor,
    void Function(String serverNow)? onCursor,
    SyncProgress? onProgress,
  }) async {
    final db = _db;
    final issues = <SyncIssue>[];
    final listed = await client.listBooks(cursor: cursor);
    final books = listed.books;

    // Apply the server's deletions locally. The server already knows, so pass
    // recordTombstone: false — otherwise we'd re-push this delete forever.
    var deletedLocally = 0;
    for (final id in await client.listDeletions(since: cursor)) {
      final row = await (db.select(
        db.books,
      )..where((b) => b.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      try {
        await repository.deleteBook(row, recordTombstone: false);
        deletedLocally++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: id,
          title: row.title,
          stage: 'delete',
          message: '$e',
        ));
      }
    }

    // Books deleted locally but not yet pushed: skip them below so a pull can't
    // revive a book the next push is about to delete on the server.
    final localTombstoned = {
      for (final d in await db.select(db.localDeletions).get()) d.bookId,
    };

    // Local timestamps (to avoid clobbering edits made on this device) and the
    // cover ETag we last stored per book (to revalidate covers cheaply below).
    final localRows = await db.select(db.books).get();
    final localUpdatedAt = {for (final row in localRows) row.id: row.updatedAt};
    final localCoverEtag = {for (final row in localRows) row.id: row.coverEtag};

    // Books whose metadata we actually applied this pull; their authors/genres
    // are replaced afterwards (outside the metadata transaction).
    final applied = <ServerBook>[];

    await db.transaction(() async {
      for (final b in books) {
        if (localTombstoned.contains(b.id)) continue;

        // Skip when we already hold a copy at least as new as the server's
        // (local edits win until pushed). Overwrite when the server is strictly
        // newer, when the row is new here, or when the server sent no timestamp
        // to compare (fall back to the old always-overwrite behavior).
        final local = localUpdatedAt[b.id];
        final server = b.updatedAt;
        if (local != null && server != null && !local.isBefore(server)) {
          continue;
        }
        applied.add(b);

        final spine =
            b.spineStyle ??
            SpineStyle.generate(title: b.title, pageCount: b.pageCount).toJson();
        await db
            .into(db.books)
            .insertOnConflictUpdate(
              BooksCompanion.insert(
                id: b.id,
                title: b.title,
                subtitle: Value(b.subtitle),
                description: Value(b.description),
                isbn: Value(b.isbn),
                publisher: Value(b.publisher),
                publishedYear: Value(b.publishedYear),
                pageCount: Value(b.pageCount),
                spineStyle: Value(spine),
                // Adopt the server's timestamp so this row isn't re-pulled every
                // time, but a later server edit (newer) still wins. Absent when
                // the server sent none, so the local default (now) applies.
                updatedAt: server == null ? const Value.absent() : Value(server),
              ),
            );
      }
    });

    // Replace authors/genres for the rows we adopted. Null means the server
    // didn't send them (old server) — leave the local joins untouched.
    // setAuthors/setGenres mark the row dirty; the needsPush clear below undoes
    // that, since adopting server state leaves nothing local to push.
    for (final b in applied) {
      if (b.authors != null) await repository.setAuthors(b.id, b.authors!);
      if (b.genres != null) await repository.setGenres(b.id, b.genres!);
    }

    // Fetch cover art outside the transaction; a failed cover never fails the
    // whole pull.
    final coverBooks = books.where((b) => b.hasCover).toList();
    var coverDone = 0;
    await _forEachBounded(coverBooks, (b) async {
      try {
        // Always revalidate with the stored ETag rather than trusting a local
        // file to be current: a cover changed on the server (console edit,
        // better art) must reach a device that already holds an old one. A 304
        // is cheap — the server's 304 path never opens the file.
        final res = await client.downloadCover(b.id, etag: localCoverEtag[b.id]);
        if (res.bytes != null) {
          final rel = p.join('covers', '${b.id}.jpg');
          await File(p.join(_dataDir.path, rel)).writeAsBytes(res.bytes!);
          await (db.update(db.books)..where((x) => x.id.equals(b.id))).write(
            BooksCompanion(coverPath: Value(rel), coverEtag: Value(res.etag)),
          );
          // Keep the dominant-colour spine in step with the new art.
          await repository.updateCoverColor(b.id, res.bytes!);
        }
      } catch (e) {
        // Leave this book cover-less; it still shows a generated spine.
        issues.add(SyncIssue(
          bookId: b.id,
          title: b.title,
          stage: 'cover',
          message: '$e',
        ));
      } finally {
        onProgress?.call(++coverDone, coverBooks.length, 'Downloading covers');
      }
    });

    // Download digital files the device doesn't already have. Dedup by content
    // hash, so a file pushed under a different id isn't downloaded twice.
    // Books run concurrently; a book's own files stay ordered (each row is
    // recorded only after its .part is renamed into place).
    var fileDone = 0;
    await _forEachBounded(books, (b) async {
      try {
        // Files come from the books-list enrichment, so no per-book round-trip.
        for (final f in b.files) {
          final have =
              await (db.select(db.bookFiles)..where(
                    (x) => x.bookId.equals(b.id) & x.sha256.equals(f.sha256),
                  ))
                  .getSingleOrNull();
          if (have != null) continue;
          final rel = p.join('files', '${f.id}.${f.format}');
          // Stream to a .part file first so an interrupted download isn't
          // mistaken for a complete one, then move it into place.
          final dest = File(p.join(_dataDir.path, rel));
          final part = File('${dest.path}.part');
          await client.downloadFileTo(f.id, part);
          await part.rename(dest.path);
          await db
              .into(db.bookFiles)
              .insertOnConflictUpdate(
                BookFilesCompanion.insert(
                  id: f.id,
                  bookId: b.id,
                  format: f.format,
                  path: rel,
                  sizeBytes: f.sizeBytes,
                  sha256: f.sha256,
                ),
              );
        }
      } catch (e) {
        // Metadata and cover are already pulled; skip files on error.
        issues.add(SyncIssue(
          bookId: b.id,
          title: b.title,
          stage: 'file',
          message: '$e',
        ));
      } finally {
        onProgress?.call(++fileDone, books.length, 'Downloading files');
      }
    });

    // For books the server has no cover for (e.g. PDFs uploaded on the server,
    // which can't render covers there): make sure we have a local cover
    // (rendering the first PDF page if needed) and push it back, so the
    // server/console shows the same cover the app does.
    for (final b in books) {
      if (b.hasCover) continue; // the server already has a cover
      final row = await (db.select(
        db.books,
      )..where((x) => x.id.equals(b.id))).getSingleOrNull();
      if (row == null) continue;
      var localCover = row.coverPath;
      if (localCover == null) {
        try {
          if (await repository.setCoverFromEmbedded(b.id)) {
            localCover = p.join('covers', '${b.id}.jpg');
          }
        } catch (e) {
          issues.add(SyncIssue(
            bookId: b.id,
            title: b.title,
            stage: 'render',
            message: '$e',
          ));
        }
      }
      if (localCover == null) continue;
      final coverFile = File(p.join(_dataDir.path, localCover));
      if (await coverFile.exists()) {
        try {
          await client.uploadCover(b.id, await coverFile.readAsBytes());
        } catch (e) {
          // View-only or offline — the cover stays local to this device.
          issues.add(SyncIssue(
            bookId: b.id,
            title: b.title,
            stage: 'cover',
            message: '$e',
          ));
        }
      }
    }

    // Everything we adopted now matches the server, so clear the dirty flag the
    // metadata/authors/genres writes set — there is nothing local to push for
    // these rows. Books we kept (local newer, not in `applied`) keep their flag.
    if (applied.isNotEmpty) {
      await (db.update(db.books)
            ..where((x) => x.id.isIn([for (final b in applied) b.id])))
          .write(const BooksCompanion(needsPush: Value(false)));
    }

    // Advance the cursor to the server's clock so the next pull is a delta.
    // Done last, so a mid-pull failure leaves the old cursor and the next pull
    // safely re-fetches this window.
    final serverNow = listed.serverNow;
    if (serverNow != null && onCursor != null) onCursor(serverNow);
    return SyncReport(
      pulled: applied.length,
      deletedLocally: deletedLocally,
      issues: issues,
    );
  }

  /// Pushes local books (and their covers/files) up to the server, propagating
  /// local deletes first and upserting by id so pull and push stay consistent.
  /// Only dirty books are sent. Books the caller can't write on the server (e.g.
  /// shared read-only) are recorded as issues and skipped. [onProgress] reports
  /// per-book progress. Returns a [SyncReport].
  Future<SyncReport> push(
    VellumServerClient client, {
    SyncProgress? onProgress,
  }) async {
    if (_running) {
      throw StateError('a sync is already in progress');
    }
    _running = true;
    try {
      return await _push(client, onProgress: onProgress);
    } finally {
      _running = false;
    }
  }

  Future<SyncReport> _push(
    VellumServerClient client, {
    SyncProgress? onProgress,
  }) async {
    final db = _db;
    final issues = <SyncIssue>[];

    // Propagate local deletes first, then stop tracking them regardless of the
    // outcome: 404 = already gone; 403 = we don't own the server copy (deleting
    // a shared book locally is a local-only act — it will legitimately return
    // on the next pull).
    var deletedRemotely = 0;
    for (final d in await db.select(db.localDeletions).get()) {
      try {
        await client.deleteBook(d.bookId);
      } on ServerException {
        // Already gone or not permitted — either way, drop the tombstone.
      }
      await (db.delete(
        db.localDeletions,
      )..where((t) => t.bookId.equals(d.bookId))).go();
      deletedRemotely++;
    }

    // Only push books changed since their last successful push. `needsPush`
    // defaults true, so a fresh library still pushes everything once; the
    // server's no-op guard keeps that first sweep from churning timestamps.
    final books =
        await (db.select(db.books)..where((b) => b.needsPush.equals(true))).get();

    // One list fetch gives the server's existing file hashes per book, so we
    // skip re-uploading files it already has without a `GET .../files` each.
    final remoteHashesByBook = <String, Set<String>>{};
    if (books.isNotEmpty) {
      for (final sb in (await client.listBooks()).books) {
        remoteHashesByBook[sb.id] = {for (final f in sb.files) f.sha256};
      }
    }

    var pushed = 0;
    var pushDone = 0;
    // Books push concurrently; the metadata upsert, cover, and files for one
    // book stay ordered within its task.
    await _forEachBounded(books, (b) async {
      try {
        final details = await repository.detailsFor(b.id);
        await client.pushBook(
          id: b.id,
          title: b.title,
          subtitle: b.subtitle,
          description: b.description,
          isbn: b.isbn,
          publisher: b.publisher,
          publishedYear: b.publishedYear,
          pageCount: b.pageCount,
          spineStyle: b.spineStyle,
          updatedAt: b.updatedAt,
          authors: details.authors,
          genres: details.genres,
        );
        final cover = repository.coverFileOf(b);
        if (cover != null && await cover.exists()) {
          await client.uploadCover(
            b.id,
            await cover.readAsBytes(),
            contentType: p.extension(cover.path).toLowerCase() == '.png'
                ? 'image/png'
                : 'image/jpeg',
          );
        }

        // Upload local files the server doesn't already have (dedup by hash).
        final localFiles = await (db.select(
          db.bookFiles,
        )..where((f) => f.bookId.equals(b.id))).get();
        if (localFiles.isNotEmpty) {
          final remoteHashes = remoteHashesByBook[b.id] ?? const {};
          for (final lf in localFiles) {
            if (remoteHashes.contains(lf.sha256)) continue;
            final file = repository.fileOf(lf);
            if (await file.exists()) {
              await client.uploadFileFrom(b.id, file, format: lf.format);
            }
          }
        }
        // Fully pushed: clear the dirty flag so the next sync skips this book
        // until it changes again.
        await (db.update(db.books)..where((x) => x.id.equals(b.id))).write(
          const BooksCompanion(needsPush: Value(false)),
        );
        pushed++;
      } catch (e) {
        // Read-only, rejected, or a blob error — leave it dirty and record it.
        issues.add(SyncIssue(
          bookId: b.id,
          title: b.title,
          stage: 'push',
          message: e is ServerException ? e.message : '$e',
        ));
      } finally {
        onProgress?.call(++pushDone, books.length, 'Pushing books');
      }
    });
    return SyncReport(
      pushed: pushed,
      deletedRemotely: deletedRemotely,
      issues: issues,
    );
  }

  /// Runs [action] over [items] with at most [_blobConcurrency] in flight at
  /// once, completing when all have finished. Each task owns its own error
  /// handling; a failure in one doesn't cancel the others.
  Future<void> _forEachBounded<T>(
    Iterable<T> items,
    Future<void> Function(T) action,
  ) async {
    final pool = Pool(_blobConcurrency);
    try {
      await Future.wait([
        for (final item in items) pool.withResource(() => action(item)),
      ]);
    } finally {
      await pool.close();
    }
  }
}

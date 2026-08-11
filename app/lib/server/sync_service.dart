import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';

import '../account/user_profile.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../shelf/spine_style.dart';
import 'server_client.dart';
import 'sync_scope.dart';

/// Whether a server-supplied id/format is safe to embed in a local file path.
/// A pull builds `covers/<id>.jpg` and `files/<id>.<format>` from values that
/// come off the wire; a malicious or compromised server must not be able to
/// smuggle a `../` and steer a write outside the data dir (path traversal). See
/// docs/SECURITY_AUDIT.md (M2).
bool _isSafeSegment(String s) =>
    s.isNotEmpty &&
    !s.contains('/') &&
    !s.contains(r'\') &&
    !s.contains('..') &&
    !s.contains('\u0000') &&
    s != '.';

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
  SyncService(this.repository, {this.profile});

  final LibraryRepository repository;

  /// The local profile, when there is one to keep in step with the account.
  /// Optional so background sync and tests can run without it — the library
  /// syncs perfectly well on its own; this only carries your name and photo.
  final UserProfileStore? profile;

  /// How many blob transfers (cover/file up/downloads) run at once. Independent
  /// transfers otherwise serialize into a sum-of-latencies; 4 keeps a personal
  /// server comfortable. DB writes still serialize inside drift.
  static const _blobConcurrency = 4;

  /// How many books go in one `POST /api/books:batch` (plan 5 #7). Must not
  /// exceed the server's own cap (`books.rs::batch_upsert`'s `MAX_BATCH`),
  /// which rejects an oversized batch outright rather than truncating it.
  static const _batchPushChunk = 200;

  /// Capabilities of the last server we probed, memoized so a push doesn't pay
  /// a handshake round trip every time. Keyed by base URL, because the same
  /// [SyncService] outlives a reconnect to a different server. A server
  /// up/downgraded mid-session is safe either way: a stale "no batch" only
  /// costs the per-book path, and a stale "has batch" 404s and falls back.
  Capabilities? _caps;
  String? _capsBaseUrl;

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
    SyncScope scope = SyncScope.everything,
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
        scope: scope,
      );
      final pushed = await _push(client, onProgress: onProgress, scope: scope);
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
    SyncScope scope = SyncScope.everything,
  }) async {
    final db = _db;
    final issues = <SyncIssue>[];
    final listed = await client.listBooks(cursor: cursor);
    final books = listed.books;

    // Apply the server's deletions locally. The server already knows, so pass
    // recordTombstone: false — otherwise we'd re-push this delete forever.
    var deletedLocally = 0;
    for (final id in await client.listDeletions(since: cursor, kind: 'book')) {
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

    // Books this device has opted out of. Off means off in *both* directions —
    // the rule SyncScope already follows — so a book excluded here is not
    // overwritten by whatever the server holds for it either.
    final syncExcluded = {
      for (final row in await (db.select(db.books)
            ..where((b) => b.syncExcluded.equals(true)))
          .get())
        row.id,
    };

    // Local timestamps (to avoid clobbering edits made on this device) and the
    // cover ETag we last stored per book (to revalidate covers cheaply below).
    final localRows = await db.select(db.books).get();
    final localUpdatedAt = {for (final row in localRows) row.id: row.updatedAt};
    final localCoverEtag = {for (final row in localRows) row.id: row.coverEtag};
    // Books with edits made here that haven't reached the server yet. If one of
    // those is overwritten below, the edit is gone — see the note there.
    final locallyEdited = {
      for (final row in localRows)
        if (row.needsPush) row.id: row.title,
    };

    // Books whose metadata we actually applied this pull; their authors/genres
    // are replaced afterwards (outside the metadata transaction).
    final applied = <ServerBook>[];
    // Collected inside the transaction, reported after it — adding to `issues`
    // from in here would be undone by a rollback.
    final overwritten = <SyncIssue>[];

    await db.transaction(() async {
      for (final b in books) {
        if (localTombstoned.contains(b.id)) continue;
        if (syncExcluded.contains(b.id)) continue;

        // Skip when we already hold a copy at least as new as the server's
        // (local edits win until pushed). Overwrite when the server is strictly
        // newer, when the row is new here, or when the server sent no timestamp
        // to compare (fall back to the old always-overwrite behavior).
        final local = localUpdatedAt[b.id];
        final server = b.updatedAt;
        if (local != null && server != null && !local.isBefore(server)) {
          continue;
        }
        // Last-write-wins is the rule and is not being reopened — field-level
        // merge was considered and rejected in plan 3. But *silence* is a
        // separate choice from last-write-wins, and it is the one worth
        // changing: an edit made here, never pushed, and now replaced by a
        // newer one from elsewhere used to vanish with nothing said anywhere.
        // The sync report already exists and already surfaces; use it.
        final pendingTitle = locallyEdited[b.id];
        if (pendingTitle != null) {
          overwritten.add(SyncIssue(
            bookId: b.id,
            title: pendingTitle,
            stage: 'overwritten',
            message: 'Your unsent changes to “$pendingTitle” were replaced by a '
                'newer version from another device.',
          ));
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
                // Who added it, cached for display. Absent — not null — when
                // the server didn't say: an older server has no answer, and
                // overwriting a name we already have with nothing would make
                // the label flicker away on every pull.
                addedBy: b.ownerName == null
                    ? const Value.absent()
                    : Value(b.ownerName),
                // Adopt the server's timestamp so this row isn't re-pulled every
                // time, but a later server edit (newer) still wins. Absent when
                // the server sent none, so the local default (now) applies.
                updatedAt: server == null ? const Value.absent() : Value(server),
              ),
            );
      }
    });
    // The transaction stuck, so the overwrites really happened.
    issues.addAll(overwritten);

    // Series membership for the adopted rows (plan 5 #17). Resolved by name, so
    // two devices converge on one series row; null means the server says the
    // book is in none, while a server that predates the feature sends nothing at
    // all and `series` stays null — indistinguishable, and harmless: the next
    // push re-asserts whatever this device knows.
    for (final b in applied) {
      await repository.seriesService
          .setSeries(b.id, b.series, b.seriesIndex, markDirty: false);
    }

    // Replace authors/genres for the rows we adopted. Null means the server
    // didn't send them (old server) — leave the local joins untouched.
    // setAuthors/setGenres mark the row dirty; the needsPush clear below undoes
    // that, since adopting server state leaves nothing local to push.
    for (final b in applied) {
      if (b.authors != null) await repository.setAuthors(b.id, b.authors!);
      if (b.genres != null) await repository.setGenres(b.id, b.genres!);
    }

    // Everything below writes *against* a local book row — a cover path onto
    // it, a `book_files` row referencing it. The upsert above deliberately
    // skips books that are trashed here, excluded from sync, or older on the
    // server than the copy we hold, so the server's list is not the set of
    // books this device actually has.
    //
    // Working from the full list anyway is how a pull ended with
    // `FOREIGN KEY constraint failed` inserting `book_files`: the parent row
    // had been skipped (a trashed book leaves a tombstone and no row), and the
    // file was fetched and recorded regardless. Ask the database which ids are
    // really here instead of assuming.
    final presentIds = {
      for (final row in await (db.selectOnly(db.books)
                ..addColumns([db.books.id])
                ..where(db.books.id.isIn([for (final b in books) b.id])))
              .get())
        row.read(db.books.id)!,
    };
    final local = books.where((b) => presentIds.contains(b.id)).toList();

    // Fetch cover art outside the transaction; a failed cover never fails the
    // whole pull.
    final coverBooks = local.where((b) => b.hasCover).toList();
    var coverDone = 0;
    await _forEachBounded(coverBooks, (b) async {
      if (!_isSafeSegment(b.id)) {
        issues.add(SyncIssue(
          bookId: b.id,
          title: b.title,
          stage: 'cover',
          message: 'server sent an unsafe book id; skipped',
        ));
        return;
      }
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
    await _forEachBounded(local, (b) async {
      try {
        // Files come from the books-list enrichment, so no per-book round-trip.
        for (final f in b.files) {
          final have =
              await (db.select(db.bookFiles)..where(
                    (x) => x.bookId.equals(b.id) & x.sha256.equals(f.sha256),
                  ))
                  .getSingleOrNull();
          if (have != null) continue;
          // Never let a server-chosen id/format escape the files/ dir.
          if (!_isSafeSegment(f.id) || !_isSafeSegment(f.format)) {
            issues.add(SyncIssue(
              bookId: b.id,
              title: b.title,
              stage: 'file',
              message: 'server sent an unsafe file id/format; skipped',
            ));
            continue;
          }
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
        onProgress?.call(++fileDone, local.length, 'Downloading files');
      }
    });

    // For books the server has no cover for (e.g. PDFs uploaded on the server,
    // which can't render covers there): make sure we have a local cover
    // (rendering the first PDF page if needed) and push it back, so the
    // server/console shows the same cover the app does.
    for (final b in books) {
      if (b.hasCover) continue; // the server already has a cover
      // b.id feeds a local cover path below; skip anything unsafe.
      if (!_isSafeSegment(b.id)) continue;
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

    // Shelves, copies, and loans ride the same cursor window as books; pulled
    // after books' metadata is applied above so a shelf/copy/loan naming a
    // book new this same pull finds it already present (see their FK-safety
    // filters). Loans run after copies for the same reason.
    const nothing = (pulled: 0, deletedLocally: 0);
    final shelfResult = scope.books
        ? await _pullShelves(client, cursor, issues)
        : nothing;
    final copyResult =
        scope.copies ? await _pullCopies(client, cursor, issues) : nothing;
    final loanResult =
        scope.loans ? await _pullLoans(client, cursor, issues) : nothing;
    // Personal data last: an annotation or a sitting names a book, and its
    // foreign key needs that book already applied above.
    final photoResult = scope.copyPhotos
        ? await _pullCopyPhotos(client, cursor, issues)
        : nothing;
    final personalPulled = await _pullPersonal(client, cursor, issues, scope);
    await _syncProfile(client, issues);

    // Advance the cursor to the server's clock so the next pull is a delta.
    // Done last, so a mid-pull failure leaves the old cursor and the next pull
    // safely re-fetches this window.
    final serverNow = listed.serverNow;
    if (serverNow != null && onCursor != null) onCursor(serverNow);
    return SyncReport(
      pulled: applied.length +
          shelfResult.pulled +
          copyResult.pulled +
          loanResult.pulled +
          photoResult.pulled +
          personalPulled,
      deletedLocally: deletedLocally +
          shelfResult.deletedLocally +
          copyResult.deletedLocally +
          loanResult.deletedLocally +
          photoResult.deletedLocally,
      issues: issues,
    );
  }

  /// Pulls shelves: applies the server's shelf tombstones, then upserts
  /// shelves LWW by `updatedAt` (same convention as books' metadata above).
  /// Incoming membership is filtered to book ids this device actually has —
  /// `shelf_books.book_id` has a foreign key, and a shared library or a book
  /// that failed its own pull must not make this throw. Adopted shelves have
  /// `needsPush` cleared, same as books' `applied` handling.
  Future<({int pulled, int deletedLocally})> _pullShelves(
    VellumServerClient client,
    String? cursor,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedLocally = 0;
    for (final id in await client.listDeletions(since: cursor, kind: 'shelf')) {
      final row = await (db.select(
        db.shelves,
      )..where((s) => s.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      try {
        await repository.deleteShelf(id, recordTombstone: false);
        deletedLocally++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: id,
          title: row.name,
          stage: 'delete',
          message: '$e',
        ));
      }
    }

    // Shelves deleted locally but not yet pushed: skip them below, same
    // reasoning as books' localTombstoned.
    final localTombstoned = {
      for (final d in await (db.select(db.localDeletions)
            ..where((d) => d.kind.equals('shelf')))
          .get())
        d.bookId,
    };

    final listed = await client.listShelves(cursor: cursor);
    final localShelves = await db.select(db.shelves).get();
    final localUpdatedAt = {for (final s in localShelves) s.id: s.updatedAt};
    final localBookIds = {for (final b in await db.select(db.books).get()) b.id};

    final adopted = <String>[];
    await db.transaction(() async {
      for (final s in listed.shelves) {
        if (localTombstoned.contains(s.id)) continue;

        final local = localUpdatedAt[s.id];
        final server = s.updatedAt;
        if (local != null && server != null && !local.isBefore(server)) {
          continue;
        }
        adopted.add(s.id);

        // `accepted` is this device's own answer about someone else's shelf,
        // so a pull must never write it: an upsert that set it would reset a
        // decision every time the shelf's name changed. A shelf arriving for
        // the first time simply has no answer yet (null), which the library
        // reads as "follow the preference".
        await db.into(db.shelves).insertOnConflictUpdate(
              ShelvesCompanion.insert(
                id: s.id,
                name: s.name,
                sortOrder: Value(s.sortOrder),
                updatedAt:
                    server == null ? const Value.absent() : Value(server),
                isPersonal: Value(s.personal),
                ownerId: Value(s.ownerId),
              ),
            );

        final filtered = s.bookIds.where(localBookIds.contains).toList();
        await (db.delete(
          db.shelfBooks,
        )..where((sb) => sb.shelfId.equals(s.id))).go();
        for (var i = 0; i < filtered.length; i++) {
          await db.into(db.shelfBooks).insert(ShelfBooksCompanion.insert(
                shelfId: s.id,
                bookId: filtered[i],
                position: Value(i),
              ));
        }
      }
    });

    if (adopted.isNotEmpty) {
      await (db.update(db.shelves)..where((s) => s.id.isIn(adopted)))
          .write(const ShelvesCompanion(needsPush: Value(false)));
    }
    return (pulled: adopted.length, deletedLocally: deletedLocally);
  }

  /// Pulls physical copies: applies the server's copy tombstones, then
  /// upserts copies LWW by `updatedAt`. A copy naming a book this device
  /// doesn't hold (a share that hasn't reached this book yet, or a book that
  /// failed its own pull) is skipped and recorded as an issue rather than
  /// adopted with a dangling `bookId` — `physical_copies.bookId` has a
  /// foreign key, and unlike a shelf's membership list a copy *is* its one
  /// book, so there is no partial form to fall back to. It must be an issue,
  /// not a silent skip: the cursor still advances past this pull window, so
  /// an unflagged copy would never be retried and would be lost on this
  /// device for good. Adopted copies have `needsPush` cleared, same as
  /// books'/shelves' handling.
  Future<({int pulled, int deletedLocally})> _pullCopies(
    VellumServerClient client,
    String? cursor,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedLocally = 0;
    for (final id in await client.listDeletions(since: cursor, kind: 'copy')) {
      final row = await (db.select(
        db.physicalCopies,
      )..where((c) => c.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      try {
        await repository.deletePhysicalCopy(id, recordTombstone: false);
        deletedLocally++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: id,
          title: row.location ?? id,
          stage: 'delete',
          message: '$e',
        ));
      }
    }

    // Copies deleted locally but not yet pushed: skip them below, same
    // reasoning as books'/shelves' localTombstoned.
    final localTombstoned = {
      for (final d in await (db.select(db.localDeletions)
            ..where((d) => d.kind.equals('copy')))
          .get())
        d.bookId,
    };

    final listed = await client.listCopies(cursor: cursor);
    final localCopies = await db.select(db.physicalCopies).get();
    final localUpdatedAt = {for (final c in localCopies) c.id: c.updatedAt};
    final localBookIds = {for (final b in await db.select(db.books).get()) b.id};

    final adopted = <String>[];
    await db.transaction(() async {
      for (final c in listed.copies) {
        if (localTombstoned.contains(c.id)) continue;
        if (!localBookIds.contains(c.bookId)) {
          // Recorded as an issue, not silently dropped: the cursor still
          // advances past this pull window, so an un-flagged skip here would
          // never be retried and the copy would be lost on this device for
          // good (unlike a shelf's per-book-id filter, a copy *is* its one
          // book — there's no partial form to keep retrying towards).
          issues.add(SyncIssue(
            bookId: c.id,
            title: c.location ?? c.id,
            stage: 'copy',
            message: "book ${c.bookId} isn't present on this device yet",
          ));
          continue;
        }

        final local = localUpdatedAt[c.id];
        final server = c.updatedAt;
        if (local != null && server != null && !local.isBefore(server)) {
          continue;
        }
        adopted.add(c.id);

        await db.into(db.physicalCopies).insertOnConflictUpdate(
              PhysicalCopiesCompanion.insert(
                id: c.id,
                bookId: c.bookId,
                location: Value(c.location),
                condition: Value(c.condition),
                notes: Value(c.notes),
                updatedAt:
                    server == null ? const Value.absent() : Value(server),
              ),
            );
      }
    });

    if (adopted.isNotEmpty) {
      await (db.update(db.physicalCopies)..where((c) => c.id.isIn(adopted)))
          .write(const PhysicalCopiesCompanion(needsPush: Value(false)));
    }
    return (pulled: adopted.length, deletedLocally: deletedLocally);
  }

  /// Pulls loans: applies the server's loan tombstones (rare in practice — a
  /// loan is normally removed only via its copy's cascade, not its own
  /// delete), then upserts loans LWW by `updatedAt`. A loan naming a copy
  /// this device doesn't hold is skipped and recorded as an issue, same
  /// FK-safety-with-visibility reasoning as `_pullCopies` (and the same
  /// permanent-loss risk a silent skip would create). Adopted loans have
  /// `needsPush` cleared, same as copies' handling.
  Future<({int pulled, int deletedLocally})> _pullLoans(
    VellumServerClient client,
    String? cursor,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedLocally = 0;
    for (final id in await client.listDeletions(since: cursor, kind: 'loan')) {
      final row = await (db.select(
        db.loans,
      )..where((l) => l.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      try {
        // Raw delete, not a service method: there is no deleteLoan, and this
        // must not record a tombstone (the server already knows) — same
        // contract as the recordTombstone: false calls in _pullShelves/
        // _pullCopies. If a deleteLoan is ever added, it must take the same
        // parameter and be called that way here.
        await (db.delete(db.loans)..where((l) => l.id.equals(id))).go();
        deletedLocally++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: id,
          title: row.borrower,
          stage: 'delete',
          message: '$e',
        ));
      }
    }

    // Loans deleted locally but not yet pushed: skip them below, same
    // reasoning as books'/shelves'/copies' localTombstoned. (No app code path
    // creates one of these today, but the pull side stays symmetric with push.)
    final localTombstoned = {
      for (final d in await (db.select(db.localDeletions)
            ..where((d) => d.kind.equals('loan')))
          .get())
        d.bookId,
    };

    final listed = await client.listLoans(cursor: cursor);
    final localLoans = await db.select(db.loans).get();
    final localUpdatedAt = {for (final l in localLoans) l.id: l.updatedAt};
    final localCopyIds = {
      for (final c in await db.select(db.physicalCopies).get()) c.id,
    };

    final adopted = <String>[];
    await db.transaction(() async {
      for (final l in listed.loans) {
        if (localTombstoned.contains(l.id)) continue;
        if (!localCopyIds.contains(l.copyId)) {
          issues.add(SyncIssue(
            bookId: l.id,
            title: l.borrower,
            stage: 'loan',
            message: "copy ${l.copyId} isn't present on this device yet",
          ));
          continue;
        }

        final local = localUpdatedAt[l.id];
        final server = l.updatedAt;
        if (local != null && server != null && !local.isBefore(server)) {
          continue;
        }
        adopted.add(l.id);

        await db.into(db.loans).insertOnConflictUpdate(
              LoansCompanion.insert(
                id: l.id,
                copyId: l.copyId,
                borrower: l.borrower,
                loanedAt: Value(l.loanedAt),
                returnedAt: Value(l.returnedAt),
                dueAt: Value(l.dueAt),
                borrowerContact: Value(l.borrowerContact),
                notes: Value(l.notes),
                reminderSentAt: Value(l.reminderSentAt),
                updatedAt:
                    server == null ? const Value.absent() : Value(server),
              ),
            );
      }
    });

    if (adopted.isNotEmpty) {
      await (db.update(db.loans)..where((l) => l.id.isIn(adopted)))
          .write(const LoansCompanion(needsPush: Value(false)));
    }
    return (pulled: adopted.length, deletedLocally: deletedLocally);
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
    SyncScope scope = SyncScope.everything,
  }) async {
    final db = _db;
    final issues = <SyncIssue>[];

    // Propagate local deletes first, then stop tracking them regardless of the
    // outcome: 404 = already gone; 403 = we don't own the server copy (deleting
    // a shared book locally is a local-only act — it will legitimately return
    // on the next pull).
    var deletedRemotely = 0;
    for (final d in await (db.select(db.localDeletions)
          ..where((d) => d.kind.equals('book')))
        .get()) {
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
    //
    // Trashed books (plan 5 #52) are excluded: they are neither dirty nor
    // deleted as far as the server is concerned, and won't be either way until
    // the grace period expires — at which point the real delete writes a
    // tombstone and the loop above pushes *that*. Pushing them meanwhile would
    // send edits the user has already taken back.
    // Books kept on this device only are skipped for the same reason trashed
    // ones are: the server is not owed them. An excluded book that was pushed
    // before stays on the server — stopping the traffic is not the same as
    // recalling what already went, and taking it back would remove it from
    // everyone the library is shared with.
    final books = await (db.select(db.books)
          ..where((b) =>
              b.needsPush.equals(true) &
              b.deletedAt.isNull() &
              b.syncExcluded.equals(false)))
        .get();

    // One list fetch gives the server's existing file hashes per book, so we
    // skip re-uploading files it already has without a `GET .../files` each.
    final remoteHashesByBook = <String, Set<String>>{};
    if (books.isNotEmpty) {
      for (final sb in (await client.listBooks()).books) {
        remoteHashesByBook[sb.id] = {for (final f in sb.files) f.sha256};
      }
    }

    // Batch-push metadata up front when the server supports it (plan 5 #7):
    // one or a few round trips instead of one PUT per book. Null (rather than
    // an empty map) means "use the per-book PUT below instead" -- an older
    // server, or the batch call itself failing outright, both fall back the
    // same way a missing capability would.
    Map<String, BatchPushResult>? batched;
    // One book is already one request: batching it would only add a handshake.
    if (books.length > 1) {
      try {
        if (await _supportsBatchPush(client)) {
          batched = await _pushBooksMetadataBatch(client, books);
        }
      } catch (_) {
        // Capability probe or the batch call failed outright -- fall back
        // silently to the per-book path below, same as an older server would.
        // Re-pushing a book the batch already applied is a no-op server-side
        // (upsert's unchanged-data guard), so the fallback is safe mid-way.
        batched = null;
      }
    }

    var pushed = 0;
    var pushDone = 0;
    // Books push concurrently; the metadata upsert, cover, and files for one
    // book stay ordered within its task.
    await _forEachBounded(books, (b) async {
      try {
        if (batched != null) {
          // Metadata already applied server-side by the batch call above;
          // an item missing from the response (shouldn't happen, but the
          // server is a separate process) is treated the same as an error.
          final result = batched[b.id];
          if (result == null || result.isError) {
            throw ServerException(
              result?.message ?? 'batch push did not report this book',
            );
          }
        } else {
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
            // '' rather than null clears the membership server-side; null would
            // mean "nothing to say" and leave a stale series in place.
            series: await repository.seriesService.nameOf(b.id) ?? '',
            seriesIndex: b.seriesIndex,
          );
        }
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

    // Shelves and copies before loans: either referencing a book pushed for
    // the first time just above must find that book already on the server,
    // or the server rejects/drops the reference (shelves.rs::
    // existing_book_ids; physical_copies.rs::upsert requires the book to
    // already exist). Loans go last for the same reason, one level down:
    // a loan for a copy pushed for the first time just above needs that
    // copy already on the server.
    const nothing = (pushed: 0, deletedRemotely: 0);
    final shelfResult =
        scope.books ? await _pushShelves(client, issues) : nothing;
    final copyResult =
        scope.copies ? await _pushCopies(client, issues) : nothing;
    final loanResult = scope.loans ? await _pushLoans(client, issues) : nothing;
    final photoPushed =
        scope.copyPhotos ? await _pushCopyPhotos(client, issues) : 0;
    final personalPushed = await _pushPersonal(client, issues, scope);

    return SyncReport(
      pushed: pushed +
          shelfResult.pushed +
          copyResult.pushed +
          loanResult.pushed +
          photoPushed +
          personalPushed,
      deletedRemotely: deletedRemotely +
          shelfResult.deletedRemotely +
          copyResult.deletedRemotely +
          loanResult.deletedRemotely,
      issues: issues,
    );
  }

  // ---- copy photos (plan 6 #4) --------------------------------------------
  //
  // Library data, so this is the blob pattern rather than the personal one: a
  // row, then its bytes. Photos ride *after* copies in both directions — a
  // photo names a copy, and the foreign key needs it there first.

  Future<({int pulled, int deletedLocally})> _pullCopyPhotos(
    VellumServerClient client,
    String? cursor,
    List<SyncIssue> issues,
  ) async {
    final db = _db;
    var pulled = 0;
    var deletedLocally = 0;
    try {
      for (final id
          in await client.listDeletions(since: cursor, kind: 'copy_photo')) {
        final rows = await (db.select(db.copyPhotos)
              ..where((ph) => ph.id.equals(id)))
            .get();
        for (final row in rows) {
          final file = File(p.join(_dataDir.path, row.path));
          if (file.existsSync()) {
            try {
              await file.delete();
            } catch (_) {
              // The row goes either way; a stray image is swept by Library
              // health rather than being worth failing a sync over.
            }
          }
        }
        deletedLocally +=
            await (db.delete(db.copyPhotos)..where((ph) => ph.id.equals(id)))
                .go();
      }

      final known = {
        for (final c in await db.select(db.physicalCopies).get()) c.id,
      };
      final remote = await client.listCopyPhotos(cursor: cursor);
      for (final photo in remote.entries) {
        // A copy this device doesn't have — a share it hasn't taken, or a copy
        // whose own pull failed. The foreign key would otherwise abort.
        if (!known.contains(photo.copyId)) continue;
        final local = await (db.select(db.copyPhotos)
              ..where((ph) => ph.id.equals(photo.id)))
            .getSingleOrNull();
        if (local != null &&
            photo.updatedAt != null &&
            !local.updatedAt.isBefore(photo.updatedAt!)) {
          continue;
        }
        // The id comes off the wire and is about to become a file path, so it
        // goes through the same check covers and book files use (M2).
        if (!_isSafeSegment(photo.id)) continue;
        final rel = p.join(CopyPhotoService.dirName, '${photo.id}.jpg');
        final file = File(p.join(_dataDir.path, rel));
        if (!file.existsSync()) {
          try {
            final bytes = await client.downloadCopyPhotoImage(photo.id);
            if (bytes != null) {
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
            }
          } catch (e) {
            issues.add(_personalIssue('file', 'A copy photo could not be '
                'downloaded: $e'));
            continue; // no row without its image — it would render as a gap
          }
        }
        await db.into(db.copyPhotos).insertOnConflictUpdate(
              CopyPhotosCompanion.insert(
                id: photo.id,
                copyId: photo.copyId,
                path: rel,
                caption: Value(photo.caption),
                takenAt: Value(photo.takenAt ?? DateTime.now()),
                updatedAt: Value(photo.updatedAt ?? DateTime.now()),
                needsPush: const Value(false),
              ),
            );
        pulled++;
      }
    } catch (e) {
      if (!_serverLacksPersonal(e)) {
        issues.add(_personalIssue('pull', 'Copy photos could not be pulled: $e'));
      }
    }
    return (pulled: pulled, deletedLocally: deletedLocally);
  }

  Future<int> _pushCopyPhotos(
    VellumServerClient client,
    List<SyncIssue> issues,
  ) async {
    final db = _db;
    var pushed = 0;

    final tombstones = await (db.select(db.localDeletions)
          ..where((d) => d.kind.equals('copy_photo')))
        .get();
    for (final t in tombstones) {
      try {
        await client.deleteCopyPhoto(t.bookId);
        await (db.delete(db.localDeletions)
              ..where((d) => d.bookId.equals(t.bookId)))
            .go();
        pushed++;
      } catch (e) {
        if (_serverLacksPersonal(e)) {
          await (db.delete(db.localDeletions)
                ..where((d) => d.bookId.equals(t.bookId)))
              .go();
        } else {
          issues.add(_personalIssue('delete', 'A copy photo deletion could '
              'not be sent: $e'));
        }
      }
    }

    final dirty = await (db.select(db.copyPhotos)
          ..where((ph) => ph.needsPush.equals(true)))
        .get();
    for (final photo in dirty) {
      try {
        await client.pushCopyPhoto(
          id: photo.id,
          copyId: photo.copyId,
          caption: photo.caption,
          takenAt: photo.takenAt,
          updatedAt: photo.updatedAt,
        );
        final file = File(p.join(_dataDir.path, photo.path));
        if (file.existsSync()) {
          await client.uploadCopyPhotoImage(photo.id, await file.readAsBytes());
        }
        await (db.update(db.copyPhotos)
              ..where((row) => row.id.equals(photo.id)))
            .write(const CopyPhotosCompanion(needsPush: Value(false)));
        pushed++;
      } catch (e) {
        // View-only, or a copy the server doesn't have yet. It stays dirty and
        // rides the next sync.
        issues.add(_personalIssue('push', 'A copy photo could not be sent: $e'));
      }
    }
    return pushed;
  }

  // ---- personal data ------------------------------------------------------
  //
  // Highlights, notes, bookmarks and reading sittings. Everything here is
  // scoped to the account server-side, so a shared library holds several
  // people's marks in the same book without any of them seeing the others'.
  //
  // Two shapes, handled differently on purpose:
  //
  // - **Annotations are mutable**, so they are last-write-wins on `updatedAt`
  //   with tombstones, exactly like books.
  // - **Sessions are immutable facts**, so the merge is a union keyed by id.
  //   Nothing is ever edited, so nothing can conflict — a re-push is the same
  //   fact arriving twice, and the server ignores it.

  /// Brings the local profile and the account's in step.
  ///
  /// Last-write-wins on the server's `profile_updated_at` against the local
  /// stamp, and the photo follows the name: whichever side is newer wins both,
  /// so a device never ends up with one person's name and another's face.
  ///
  /// Runs on the pull side and pushes as part of it, because the comparison
  /// needs both stamps in hand at once — splitting it across the two passes
  /// would mean fetching the profile twice to answer one question.
  Future<void> _syncProfile(
    VellumServerClient client,
    List<SyncIssue> issues,
  ) async {
    final local = profile;
    if (local == null) return;
    try {
      final remote = await client.fetchProfile();
      final localStamp = local.updatedAt;
      final remoteStamp = remote.updatedAt;
      final remoteIsNewer = localStamp == null ||
          (remoteStamp != null && remoteStamp.isAfter(localStamp));

      if (remoteIsNewer) {
        if (remote.displayName.isNotEmpty && remote.displayName != local.name) {
          await local.adopt(name: remote.displayName, at: remoteStamp);
        }
        final bytes = await client.fetchAvatar();
        if (bytes != null) {
          await local.adoptPhoto(bytes, at: remoteStamp);
        } else if (local.photoPath != null) {
          await local.clearPhoto();
        }
        return;
      }

      // Ours is newer (or the account has nothing yet): publish it.
      if (local.name.isNotEmpty && local.name != remote.displayName) {
        await client.pushDisplayName(local.name);
      }
      final path = local.photoPath;
      if (path != null) {
        final file = File(path);
        if (file.existsSync()) await client.pushAvatar(await file.readAsBytes());
      } else if (remote.hasAvatar) {
        await client.deleteAvatar();
      }
    } catch (e) {
      if (!_serverLacksPersonal(e)) {
        issues.add(
            _personalIssue('push', 'Your profile could not be synced: $e'));
      }
    }
  }

  /// Whether this failure is just an older server that predates personal data.
  ///
  /// A server without migration 0023 has no `/api/annotations` at all, and
  /// answers 404. That is not a problem to report on every sync forever — it is
  /// a server that hasn't been upgraded, and the library still syncs perfectly
  /// well without it. Same reasoning as the batch-push capability probe.
  ///
  /// Reads the status off the exception rather than matching on the message:
  /// a 404 whose body happens to spell out something else is still a 404, and
  /// a message containing "404" for another reason is not.
  bool _serverLacksPersonal(Object error) =>
      error is ServerException && error.statusCode == 404;

  /// Personal-data failures have no single book to name, so they report under
  /// the category rather than pretending to.
  SyncIssue _personalIssue(String stage, String message) => SyncIssue(
        bookId: '',
        title: 'Personal data',
        stage: stage,
        message: message,
      );

  Future<int> _pullPersonal(
    VellumServerClient client,
    String? cursor,
    List<SyncIssue> issues,
    SyncScope scope,
  ) async {
    if (!scope.annotations && !scope.sessions) return 0;
    final db = _db;
    var pulled = 0;
    // Books this device actually has. An annotation whose book failed its own
    // pull — or belongs to a share this device hasn't taken — would otherwise
    // violate the foreign key and abort the whole sync.
    final known = {
      for (final b in await db.select(db.books).get()) b.id,
    };

    // Annotations and reader notes travel together: a note *is* a
    // `book_note` row on the same personal channel, and "sync my highlights but
    // not my private note on the same book" is a distinction nobody asked for.
    if (scope.annotations) {
      try {
      final deletions = await client.listAnnotationDeletions(cursor: cursor);
      for (final tombstone in deletions.entries) {
        final removed = await (db.delete(db.annotations)
              ..where((a) => a.id.equals(tombstone.id)))
            .go();
        if (removed > 0) pulled++;
      }

      final remote = await client.listAnnotations(cursor: cursor);
      for (final a in remote.entries) {
        if (!known.contains(a.bookId)) continue;
        final local = await (db.select(db.annotations)
              ..where((row) => row.id.equals(a.id)))
            .getSingleOrNull();
        // Last-write-wins, and a tie keeps what is already here: re-applying
        // an identical row would only clear its `needsPush` for no reason.
        if (local != null &&
            a.updatedAt != null &&
            !local.updatedAt.isBefore(a.updatedAt!)) {
          continue;
        }
        await db.into(db.annotations).insertOnConflictUpdate(
              AnnotationsCompanion.insert(
                id: a.id,
                bookId: a.bookId,
                kind: a.kind,
                page: Value(a.page),
                chapter: Value(a.chapter),
                locator: Value(a.locator),
                quotedText: Value(a.quotedText),
                note: Value(a.note),
                color: Value(a.color),
                createdAt: Value(a.createdAt ?? DateTime.now()),
                updatedAt: Value(a.updatedAt ?? DateTime.now()),
                // It came *from* the server, so it is not waiting to go there.
                needsPush: const Value(false),
              ),
            );
        pulled++;
      }
    } catch (e) {
      if (!_serverLacksPersonal(e)) {
        issues.add(_personalIssue('pull', 'Annotations could not be pulled: $e'));
      }
    }
    }

    if (scope.sessions) {
      try {
      final remote = await client.listSessions(cursor: cursor);
      for (final s in remote.entries) {
        if (!known.contains(s.bookId)) continue;
        await db.into(db.readingSessions).insertOnConflictUpdate(
              ReadingSessionsCompanion.insert(
                id: s.id,
                bookId: s.bookId,
                startedAt: s.startedAt,
                endedAt: s.endedAt,
                startPage: Value(s.startPage),
                endPage: Value(s.endPage),
                deviceId: Value(s.deviceId),
                deviceLabel: Value(s.deviceLabel),
                needsPush: const Value(false),
              ),
            );
        pulled++;
      }
    } catch (e) {
      if (!_serverLacksPersonal(e)) {
        issues.add(
            _personalIssue('pull', 'Reading sessions could not be pulled: $e'));
      }
    }
    }

    if (scope.annotations) {
      try {
      final notes = await client.listBookNotes(cursor: cursor);
      for (final n in notes.entries) {
        if (!known.contains(n.bookId)) continue;
        await (db.update(db.books)..where((b) => b.id.equals(n.bookId))).write(
          BooksCompanion(
            readerNotes: Value(n.note.isEmpty ? null : n.note),
            readerNotesUpdatedAt: Value(n.updatedAt),
            readerNotesNeedsPush: const Value(false),
          ),
        );
        pulled++;
      }
    } catch (e) {
      if (!_serverLacksPersonal(e)) {
        issues.add(
            _personalIssue('pull', 'Reader notes could not be pulled: $e'));
      }
    }
    }
    return pulled;
  }

  Future<int> _pushPersonal(
    VellumServerClient client,
    List<SyncIssue> issues,
    SyncScope scope,
  ) async {
    if (!scope.annotations && !scope.sessions) return 0;
    final db = _db;
    var pushed = 0;

    // Deletions first, so a delete followed by a re-add in the same window
    // lands in that order rather than the reverse.
    final tombstones = scope.annotations
        ? await (db.select(db.localDeletions)
              ..where((d) => d.kind.equals('annotation')))
            .get()
        : const <LocalDeletion>[];
    for (final t in tombstones) {
      try {
        await client.deleteAnnotation(t.bookId);
        await (db.delete(db.localDeletions)
              ..where((d) => d.bookId.equals(t.bookId)))
            .go();
        pushed++;
      } catch (e) {
        // A 404 means the server never had it — the tombstone has done its job
        // either way, so it goes rather than being retried forever.
        if (e.toString().contains('404')) {
          await (db.delete(db.localDeletions)
                ..where((d) => d.bookId.equals(t.bookId)))
              .go();
        } else {
          issues.add(_personalIssue('delete', 'An annotation deletion could not be sent: $e'));
        }
      }
    }

    final dirty = scope.annotations
        ? await (db.select(db.annotations)..where((a) => a.needsPush.equals(true)))
            .get()
        : const <Annotation>[];
    for (final a in dirty) {
      try {
        await client.pushAnnotation(
          id: a.id,
          bookId: a.bookId,
          kind: a.kind,
          page: a.page,
          chapter: a.chapter,
          locator: a.locator,
          quotedText: a.quotedText,
          note: a.note,
          color: a.color,
          createdAt: a.createdAt,
          updatedAt: a.updatedAt,
        );
        await (db.update(db.annotations)..where((row) => row.id.equals(a.id)))
            .write(const AnnotationsCompanion(needsPush: Value(false)));
        pushed++;
      } catch (e) {
        // A book the server doesn't have (or won't share) is not an error worth
        // stopping for — the annotation stays dirty and rides the next sync,
        // once its book has been pushed.
        issues.add(_personalIssue('push', 'An annotation could not be sent: $e'));
      }
    }

    final sessions = scope.sessions
        ? await (db.select(db.readingSessions)
              ..where((s) => s.needsPush.equals(true)))
            .get()
        : const <ReadingSession>[];
    for (final s in sessions) {
      try {
        await client.pushSession(
          id: s.id,
          bookId: s.bookId,
          startedAt: s.startedAt,
          endedAt: s.endedAt,
          startPage: s.startPage,
          endPage: s.endPage,
          deviceId: s.deviceId,
          deviceLabel: s.deviceLabel,
        );
        await (db.update(db.readingSessions)
              ..where((row) => row.id.equals(s.id)))
            .write(const ReadingSessionsCompanion(needsPush: Value(false)));
        pushed++;
      } catch (e) {
        issues.add(_personalIssue('push', 'A reading session could not be sent: $e'));
      }
    }

    final notedBooks = scope.annotations
        ? await (db.select(db.books)
              ..where((b) => b.readerNotesNeedsPush.equals(true)))
            .get()
        : const <Book>[];
    for (final b in notedBooks) {
      try {
        await client.pushBookNote(
          bookId: b.id,
          note: b.readerNotes ?? '',
          updatedAt: b.readerNotesUpdatedAt,
        );
        await (db.update(db.books)..where((row) => row.id.equals(b.id)))
            .write(const BooksCompanion(readerNotesNeedsPush: Value(false)));
        pushed++;
      } catch (e) {
        issues.add(_personalIssue('push', 'A reader note could not be sent: $e'));
      }
    }
    return pushed;
  }

  /// Pushes local shelf deletions, then dirty (`needsPush`) shelves with
  /// their full membership in order — the server replaces the list wholesale,
  /// same convention as the pull side.
  Future<({int pushed, int deletedRemotely})> _pushShelves(
    VellumServerClient client,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedRemotely = 0;
    for (final d in await (db.select(db.localDeletions)
          ..where((d) => d.kind.equals('shelf')))
        .get()) {
      try {
        await client.deleteShelf(d.bookId);
      } on ServerException {
        // Already gone or not permitted — either way, drop the tombstone.
      }
      await (db.delete(
        db.localDeletions,
      )..where((t) => t.bookId.equals(d.bookId))).go();
      deletedRemotely++;
    }

    final dirty =
        await (db.select(db.shelves)..where((s) => s.needsPush.equals(true)))
            .get();
    var pushed = 0;
    for (final s in dirty) {
      try {
        final members = await (db.select(db.shelfBooks)
              ..where((sb) => sb.shelfId.equals(s.id))
              ..orderBy([(sb) => OrderingTerm.asc(sb.position)]))
            .get();
        await client.pushShelf(
          id: s.id,
          name: s.name,
          sortOrder: s.sortOrder,
          bookIds: [for (final m in members) m.bookId],
          updatedAt: s.updatedAt,
          personal: s.isPersonal,
        );
        await (db.update(db.shelves)..where((x) => x.id.equals(s.id))).write(
          const ShelvesCompanion(needsPush: Value(false)),
        );
        pushed++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: s.id,
          title: s.name,
          stage: 'push',
          message: e is ServerException ? e.message : '$e',
        ));
      }
    }
    return (pushed: pushed, deletedRemotely: deletedRemotely);
  }

  /// Pushes local copy deletions, then dirty (`needsPush`) copies — always
  /// after books, so a copy's book already exists server-side by the time it
  /// pushes (see `_push`'s ordering note).
  Future<({int pushed, int deletedRemotely})> _pushCopies(
    VellumServerClient client,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedRemotely = 0;
    for (final d in await (db.select(db.localDeletions)
          ..where((d) => d.kind.equals('copy')))
        .get()) {
      try {
        await client.deleteCopy(d.bookId);
      } on ServerException {
        // Already gone or not permitted — either way, drop the tombstone.
      }
      await (db.delete(
        db.localDeletions,
      )..where((t) => t.bookId.equals(d.bookId))).go();
      deletedRemotely++;
    }

    final dirty = await (db.select(
      db.physicalCopies,
    )..where((c) => c.needsPush.equals(true))).get();
    var pushed = 0;
    for (final c in dirty) {
      try {
        await client.pushCopy(
          id: c.id,
          bookId: c.bookId,
          location: c.location,
          condition: c.condition,
          notes: c.notes,
          updatedAt: c.updatedAt,
        );
        await (db.update(db.physicalCopies)..where((x) => x.id.equals(c.id)))
            .write(const PhysicalCopiesCompanion(needsPush: Value(false)));
        pushed++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: c.id,
          title: c.location ?? c.id,
          stage: 'push',
          message: e is ServerException ? e.message : '$e',
        ));
      }
    }
    return (pushed: pushed, deletedRemotely: deletedRemotely);
  }

  /// Pushes local loan deletions (rare -- see `_pullLoans`'s doc comment),
  /// then dirty (`needsPush`) loans -- always after copies, so a loan's copy
  /// already exists server-side by the time it pushes.
  Future<({int pushed, int deletedRemotely})> _pushLoans(
    VellumServerClient client,
    List<SyncIssue> issues,
  ) async {
    final db = _db;

    var deletedRemotely = 0;
    for (final d in await (db.select(db.localDeletions)
          ..where((d) => d.kind.equals('loan')))
        .get()) {
      try {
        await client.deleteLoan(d.bookId);
      } on ServerException {
        // Already gone or not permitted — either way, drop the tombstone.
      }
      await (db.delete(
        db.localDeletions,
      )..where((t) => t.bookId.equals(d.bookId))).go();
      deletedRemotely++;
    }

    // Returns before lends. The server allows one open loan per copy, so
    // lend → return → lend to someone else pushes a conflict if the new loan
    // arrives before the old one is known to be closed. Sorting by
    // `returnedAt` puts every closure first, which is the order the events
    // actually happened in. (A refused push keeps `needsPush`, so this is
    // about not making noise rather than about correctness.)
    final dirty = await (db.select(db.loans)
          ..where((l) => l.needsPush.equals(true))
          ..orderBy([(l) => OrderingTerm(expression: l.returnedAt.isNull())]))
        .get();
    var pushed = 0;
    for (final l in dirty) {
      try {
        await client.pushLoan(
          id: l.id,
          copyId: l.copyId,
          borrower: l.borrower,
          loanedAt: l.loanedAt,
          returnedAt: l.returnedAt,
          dueAt: l.dueAt,
          borrowerContact: l.borrowerContact,
          notes: l.notes,
          reminderSentAt: l.reminderSentAt,
          updatedAt: l.updatedAt,
        );
        await (db.update(db.loans)..where((x) => x.id.equals(l.id)))
            .write(const LoansCompanion(needsPush: Value(false)));
        pushed++;
      } catch (e) {
        issues.add(SyncIssue(
          bookId: l.id,
          title: l.borrower,
          stage: 'push',
          message: e is ServerException ? e.message : '$e',
        ));
      }
    }
    return (pushed: pushed, deletedRemotely: deletedRemotely);
  }

  /// Two-way sync of the *optional* cross-device reading position (plan 5 #5).
  ///
  /// Deliberately its own pass, not part of [pull]/[push]: reading state is not
  /// part of the book upsert and must not become part of it by accident, and the
  /// whole channel only runs when the user has opted in — the caller checks the
  /// preference and simply doesn't call this otherwise. Call it *after*
  /// [sync]/[push] returns, never inside: the re-entrancy guard is shared.
  ///
  /// [deviceId] identifies this install; rows keyed by it are this device's own,
  /// so pushing can only ever overwrite our own row and pulling deliberately
  /// skips it. Returns how many positions were published and how many remote
  /// rows were cached.
  Future<({int published, int cached})> syncReadingProgress(
    VellumServerClient client, {
    required String deviceId,
    String? deviceLabel,
    String? cursor,
    void Function(String serverNow)? onCursor,
  }) async {
    if (_running) {
      throw StateError('a sync is already in progress');
    }
    _running = true;
    try {
      return await _syncReadingProgress(
        client,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        cursor: cursor,
        onCursor: onCursor,
      );
    } finally {
      _running = false;
    }
  }

  Future<({int published, int cached})> _syncReadingProgress(
    VellumServerClient client, {
    required String deviceId,
    String? deviceLabel,
    String? cursor,
    void Function(String serverNow)? onCursor,
  }) async {
    final db = _db;
    final positions = repository.readingPositions;
    final isFullPull = cursor == null || cursor.isEmpty;

    // Pull first, so a position this device is about to publish wins on screen.
    final listed = await client.listReadingPositions(cursor: cursor);
    // A full pull replaces the cache outright. A delta pull can't: the server
    // has no tombstones for this table (a device that un-publishes just stops
    // being listed), so dropping stale rows is what the periodic full pull —
    // after each login, like books — is for.
    if (isFullPull) {
      await db.delete(db.remoteReadingPositions).go();
    }
    await positions.cacheRemotePositions(
      [
        for (final e in listed.entries)
          RemoteReadingPositionsCompanion.insert(
            bookId: e.bookId,
            deviceId: e.deviceId,
            deviceLabel: Value(e.deviceLabel),
            progress: Value(e.progress),
            page: Value(e.page),
            unit: Value(e.unit),
            scroll: Value(e.scroll),
            updatedAt: e.updatedAt ?? DateTime.now(),
          ),
      ],
      ownDeviceId: deviceId,
    );
    final serverNow = listed.serverNow;
    if (serverNow != null && onCursor != null) onCursor(serverNow);

    // Push this device's dirty positions. Each book's unit comes from the file
    // it opens in, so a device reading the EPUB doesn't claim PDF pages.
    var published = 0;
    for (final book in await positions.booksNeedingProgressPush()) {
      final formats = [
        for (final f in await (db.select(db.bookFiles)
              ..where((f) => f.bookId.equals(book.id)))
            .get())
          f.format,
      ];
      await client.pushReadingPosition(
        book.id,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        progress: book.readingProgress,
        page: book.lastReadPage,
        unit: readingUnitForFormats(formats),
        updatedAt: book.lastReadAt,
      );
      await positions.clearProgressDirty(book.id);
      published++;
    }
    return (published: published, cached: listed.entries.length);
  }

  /// Whether [client]'s server advertises the batch push endpoint (plan 5 #7).
  /// Memoized per base URL, including the negative: a server old enough to
  /// predate the handshake answers 404, and re-paying that probe on every push
  /// is exactly the cost the memoization exists to avoid.
  ///
  /// A *transient* failure (offline mid-push) is deliberately not cached — it
  /// propagates, the caller falls back for this push only, and the next one
  /// probes again rather than staying downgraded for the session.
  Future<bool> _supportsBatchPush(VellumServerClient client) async {
    if (_capsBaseUrl != client.baseUrl) {
      try {
        _caps = await client.capabilities();
      } on ServerException {
        // The server answered, just not with capabilities — a real negative.
        _caps = null;
      }
      _capsBaseUrl = client.baseUrl;
    }
    return _caps?.hasFeature('batch_push') ?? false;
  }

  /// Pushes every book's *metadata* in chunks of [_batchPushChunk], returning
  /// the merged per-book outcome keyed by book id (plan 5 #7). Covers, files and
  /// the `needsPush` clear stay in the per-book loop in [_push] — only the
  /// round trip per book's metadata is what this removes.
  ///
  /// Throws if a chunk fails as a whole; the caller then falls back to per-book
  /// PUTs for *all* books, including any earlier chunk that did apply. That
  /// re-push is deliberate and cheap: the server's unchanged-data guard makes
  /// it a no-op, and the alternative (reporting the un-attempted books as
  /// failures) would leave them dirty over a single transient error.
  Future<Map<String, BatchPushResult>> _pushBooksMetadataBatch(
    VellumServerClient client,
    List<Book> books,
  ) async {
    final results = <String, BatchPushResult>{};
    for (var start = 0; start < books.length; start += _batchPushChunk) {
      final chunk = books.skip(start).take(_batchPushChunk);
      final items = <BookPushItem>[];
      for (final b in chunk) {
        final details = await repository.detailsFor(b.id);
        items.add(BookPushItem(
          id: b.id,
          title: b.title,
          series: await repository.seriesService.nameOf(b.id) ?? '',
          seriesIndex: b.seriesIndex,
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
        ));
      }
      results.addAll(await client.pushBooksBatch(items));
    }
    return results;
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

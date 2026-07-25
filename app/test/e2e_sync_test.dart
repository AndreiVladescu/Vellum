@Tags(['e2e'])
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

/// End-to-end sync against a *real* running server, exercising the actual wire
/// format both sides speak — the one thing the fake-client unit tests can't
/// catch (mirrored bugs on both sides pass a fake-only suite). Skipped unless
/// `VELLUM_E2E_URL` points at a fresh Vellum server; `scripts/e2e_sync.sh`
/// launches one and sets it (see the `e2e` CI job).
void main() {
  final url = Platform.environment['VELLUM_E2E_URL'];
  final skip = url == null
      ? 'set VELLUM_E2E_URL to a running Vellum server (see scripts/e2e_sync.sh)'
      : false;

  // A fresh server accepts only the *first* registration (it becomes master),
  // so register once and share the authenticated client across cases. Guarded
  // so it's a no-op when the suite is skipped.
  late final VellumServerClient client;
  setUpAll(() async {
    if (url == null) return;
    final email = 'e2e+${DateTime.now().microsecondsSinceEpoch}@lib.test';
    final auth = await VellumServerClient(baseUrl: url)
        .register(email: email, displayName: 'E2E', password: 'password1');
    client = VellumServerClient(baseUrl: url, token: auth.token);
  });

  test('push on one device, pull on another: metadata, author, file, delete', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_e2e_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_e2e_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    // Device A: a book with an author and an attached file.
    final repoA =
        await LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dirA);
    final bookId =
        await repoA.createCustomBook(title: 'Dune', author: 'Frank Herbert');
    // A minimal EPUB (ZIP magic bytes) passes the server's magic-byte check
    // without needing a renderable PDF (which would trigger cover rendering).
    final epub = File('${dirA.path}/dune.epub')
      ..writeAsBytesSync([0x50, 0x4B, 0x03, 0x04, ...List.filled(64, 0)]);
    await repoA.attachFile(bookId, epub.path);
    final fileA = await (repoA.db.select(repoA.db.bookFiles)
          ..where((f) => f.bookId.equals(bookId)))
        .getSingle();

    final pushReport = await SyncService(repoA).push(client);
    expect(pushReport.issues, isEmpty, reason: 'push should not error');
    expect(pushReport.pushed, 1);

    // Device B: pull from the same server into a separate store.
    final repoB =
        await LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dirB);
    final pullReport = await SyncService(repoB).pull(client);
    expect(pullReport.issues, isEmpty, reason: 'pull should not error');

    final bookB = await repoB.watchBook(bookId).first;
    expect(bookB?.title, 'Dune');
    final detailsB = await repoB.detailsFor(bookId);
    expect(detailsB.authors, contains('Frank Herbert'),
        reason: 'authors must cross the wire');
    final fileB = await (repoB.db.select(repoB.db.bookFiles)
          ..where((f) => f.bookId.equals(bookId)))
        .getSingle();
    expect(fileB.sha256, fileA.sha256, reason: 'file content round-trips by hash');
    expect(File('${dirB.path}/${fileB.path}').existsSync(), true,
        reason: 'the blob was actually downloaded');

    // Delete on A, propagate, and confirm B removes it (tombstone round-trip).
    final bookA = await repoA.watchBook(bookId).first as Book;
    await repoA.deleteBook(bookA);
    await SyncService(repoA).push(client);
    await SyncService(repoB).pull(client);
    expect(await repoB.watchBook(bookId).first, isNull,
        reason: 'a delete on A must reach B');
  }, skip: skip);

  // The one-tap sync() (pull-then-push) is what users and the launch hook run;
  // exercise the full loop through the real wire format, both directions.
  test('one-tap sync carries a book each way between two devices', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_e2e_sync_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_e2e_sync_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    final repoA = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirA);
    final repoB = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirB);

    // A creates a book and pushes it up via the combined sync.
    final idA =
        await repoA.createCustomBook(title: 'Foundation', author: 'Isaac Asimov');
    await SyncService(repoA).sync(client);

    // B syncs and sees A's book (the pull half of B's sync).
    await SyncService(repoB).sync(client);
    expect((await repoB.watchBook(idA).first)?.title, 'Foundation',
        reason: "B's sync pulls A's pushed book");

    // B creates its own book and syncs it up (the push half of B's sync).
    final idB = await repoB.createCustomBook(
        title: 'Snow Crash', author: 'Neal Stephenson');
    await SyncService(repoB).sync(client);

    // A syncs again and sees B's book — the full loop is closed.
    await SyncService(repoA).sync(client);
    expect((await repoA.watchBook(idB).first)?.title, 'Snow Crash',
        reason: "A's next sync pulls B's pushed book");
  }, skip: skip);

  // Plan 5 #4: shelves sync too now, over the real wire, with their explicit
  // order preserved — the failure mode a set-replace could hide (books
  // present but scrambled) looks fine until compared against the sender's
  // intended order.
  test('shelf sync carries explicit book order between two devices', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_e2e_shelf_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_e2e_shelf_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    final repoA = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirA);
    final repoB = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirB);

    // A creates three books and a shelf in a deliberate (non-alphabetical,
    // non-insertion) order, then syncs.
    final c = await repoA.createCustomBook(title: 'Charlie');
    final aId = await repoA.createCustomBook(title: 'Alpha');
    final b = await repoA.createCustomBook(title: 'Bravo');
    final shelfId = await repoA.createShelf('Reading order');
    await repoA.addToShelf(c, shelfId);
    await repoA.addToShelf(aId, shelfId);
    await repoA.addToShelf(b, shelfId);
    await SyncService(repoA).sync(client);

    // B syncs and sees the shelf with the same order, once it has the books
    // to hold (both halves of one sync round — see SyncService._pullShelves).
    await SyncService(repoB).sync(client);
    final onShelfB = await repoB.watchBooksOnShelf(shelfId).first;
    expect([for (final book in onShelfB) book.id], [c, aId, b]);

    // B reorders and pushes; A pulls the new order back. The server's
    // updated_at is second-resolution and LWW treats a tie as "local wins"
    // (same convention as books), so without this gap B's reorder could land
    // in the same second as A's original push and get skipped as "not
    // strictly newer" — a real e2e timing edge, not a design flaw.
    await Future<void>.delayed(const Duration(seconds: 1));
    await repoB.removeFromShelf(c, shelfId);
    await repoB.addToShelf(c, shelfId);
    await SyncService(repoB).sync(client);
    await SyncService(repoA).sync(client);
    final onShelfA = await repoA.watchBooksOnShelf(shelfId).first;
    expect([for (final book in onShelfA) book.id], [aId, b, c],
        reason: "A's pull adopts B's reordered shelf");
  }, skip: skip);

  // Plan 5 #4, second of three: physical copies sync too now, over the real
  // wire, with no owner of their own (access derives from the book).
  test('physical copy sync carries a copy between two devices', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_e2e_copy_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_e2e_copy_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    final repoA = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirA);
    final repoB = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dirB);

    final bookId = await repoA.createCustomBook(title: 'Dune');
    final copyId =
        await repoA.addPhysicalCopy(bookId, location: 'Living room');
    await SyncService(repoA).sync(client);

    // B syncs and sees the copy, once it has the book to hold (both halves
    // of one sync round — see SyncService._pullCopies).
    await SyncService(repoB).sync(client);
    final copyB = await repoB.watchCopiesOf(bookId).first;
    expect(copyB, hasLength(1));
    expect(copyB.single.location, 'Living room');

    // Deleting on A propagates to B, including its (empty) loan history and
    // any dependent rows PhysicalService.deletePhysicalCopy must clear.
    await repoA.deletePhysicalCopy(copyId);
    await SyncService(repoA).sync(client);
    await SyncService(repoB).sync(client);
    expect(await repoB.watchCopiesOf(bookId).first, isEmpty,
        reason: 'a delete on A must reach B');
  }, skip: skip);
}

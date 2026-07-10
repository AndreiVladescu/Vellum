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

  test('push on one device, pull on another: metadata, author, file, delete', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_e2e_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_e2e_b');
    addTearDown(() {
      dirA.deleteSync(recursive: true);
      dirB.deleteSync(recursive: true);
    });

    // A fresh server accepts the first registration as master.
    final email = 'e2e+${DateTime.now().microsecondsSinceEpoch}@lib.test';
    final auth = await VellumServerClient(baseUrl: url!)
        .register(email: email, displayName: 'E2E', password: 'password1');
    final client = VellumServerClient(baseUrl: url, token: auth.token);

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
  },
      skip: url == null
          ? 'set VELLUM_E2E_URL to a running Vellum server (see scripts/e2e_sync.sh)'
          : false);
}

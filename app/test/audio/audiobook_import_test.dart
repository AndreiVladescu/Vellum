// Audiobook import (docs/AUDIOBOOKS.md §1 and §3): ordering, tags, cover,
// grouping, and what lands in the database — over the tiny fixtures in
// test/fixtures/audio/ (ffmpeg-made; a few KB in all).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/audio/audio_formats.dart';
import 'package:vellum/audio/audiobook_import.dart';
import 'package:vellum/audio/audiobook_scan.dart';
import 'package:vellum/audio/mp3_duration.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/import/folder_import_service.dart';
import 'package:vellum/import/import_plan.dart';

const _fixtures = 'test/fixtures/audio';

AudioPartScan _part(String path, {int? disc, int? track}) =>
    AudioPartScan(path: path, format: 'mp3', disc: disc, trackNo: track);

void main() {
  group('ordering', () {
    test('natural sort puts 2 before 10', () {
      final names = ['part 10', 'part 2', 'Part 1', 'part 2b'];
      names.sort(compareNatural);
      expect(names, ['Part 1', 'part 2', 'part 2b', 'part 10']);
    });

    test('disc and track decide when they are complete and unique', () {
      final ordered = orderParts([
        _part('/b/z.mp3', disc: 2, track: 1),
        _part('/b/y.mp3', disc: 1, track: 2),
        _part('/b/x.mp3', disc: 1, track: 1),
      ]);
      expect([for (final x in ordered) p.basename(x.path)], ['x.mp3', 'y.mp3', 'z.mp3']);
    });

    test('a rip that numbers every file "1" falls back to the names', () {
      final ordered = orderParts([
        _part('/b/10.mp3', track: 1),
        _part('/b/2.mp3', track: 1),
        _part('/b/1.mp3', track: 1),
      ]);
      expect([for (final x in ordered) p.basename(x.path)], ['1.mp3', '2.mp3', '10.mp3']);
    });

    test('disc folders sort in order and join their parent book', () {
      final groups = groupAudioByFolder([
        '/lib/Dune/CD2/01.mp3',
        '/lib/Dune/CD1/02.mp3',
        '/lib/Dune/CD1/01.mp3',
        '/lib/Emma/01.mp3',
      ]);
      expect(groups.keys, ['/lib/Dune', '/lib/Emma']);
      final ordered = orderParts([for (final x in groups['/lib/Dune']!) _part(x)]);
      expect([for (final x in ordered) x.path],
          ['/lib/Dune/CD1/01.mp3', '/lib/Dune/CD1/02.mp3', '/lib/Dune/CD2/01.mp3']);
    });
  });

  test('magic bytes decide, not just the extension', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_audio_magic');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fake = File(p.join(dir.path, 'fake.mp3'))..writeAsStringSync('%PDF-1.7');
    expect(await isImportableAudio(fake.path), isFalse);
    expect(await isImportableAudio('$_fixtures/tiny.m4b'), isTrue);
    expect(await isImportableAudio('$_fixtures/folder/part 1.mp3'), isTrue);
    expect(sniffAudio([0xFF, 0xFB, 0x90, 0x00]), AudioContainer.mp3);
  });

  test('a folder of mp3s: track order, album title, author, labels, durations',
      () async {
    final scan = await scanAudiobook([
      for (final name in ['part 10.mp3', 'part 1.mp3', 'part 2.mp3'])
        '$_fixtures/folder/$name',
    ]);
    expect([for (final x in scan.parts) x.label], ['Part 1', 'Part 2', 'Part 10']);
    expect(scan.title, 'Folder Book');
    expect(scan.author, 'Ann Author');
    for (final part in scan.parts) {
      expect(part.durationMs, isNotNull);
      expect(part.durationMs!, inInclusiveRange(950, 1150));
    }
    expect(scan.totalMs, isNotNull);
    expect(AudiobookScan.chaptersOf(scan.parts.first).single.title, 'Part 1',
        reason: 'an mp3 part is one chapter, named after it');
  });

  test('mp3 durations: Info header (MPEG-2), VBR Xing, and bitrate only', () async {
    expect(await mp3DurationMs('$_fixtures/folder/part 1.mp3'), inInclusiveRange(950, 1150));
    expect(await mp3DurationMs('$_fixtures/vbr.mp3'), inInclusiveRange(1950, 2150));
    expect(await mp3DurationMs('$_fixtures/no_xing.mp3'), inInclusiveRange(1900, 2150),
        reason: 'no header at all: estimated from the CBR bitrate');
    expect(await mp3DurationMs('$_fixtures/tiny.m4b'), isNull);
  });

  test('a single m4b: its own chapters, narrator and cover', () async {
    final scan = await scanAudiobook(['$_fixtures/tiny.m4b']);
    expect(scan.title, 'Tiny Book');
    expect(scan.author, 'Ann Author');
    expect(scan.narrator, 'Ned Narrator');
    expect(scan.cover, isNotNull);
    expect(scan.parts.single.chapters.length, 3);
  });

  group('into the library', () {
    late Directory dataDir;
    late LibraryRepository repo;

    setUp(() async {
      dataDir = Directory.systemTemp.createTempSync('vellum_audio_data');
      repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dataDir);
    });
    tearDown(() async {
      await repo.db.close();
      dataDir.deleteSync(recursive: true);
    });

    test('parts become book_files with order, label, duration and chapters',
        () async {
      final importer = AudiobookImporter(repo);
      final scan = await importer.scan([
        '$_fixtures/folder/part 2.mp3',
        '$_fixtures/folder/part 10.mp3',
        '$_fixtures/folder/part 1.mp3',
      ]);
      final bookId = await importer.importAsNewBook(scan);

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals(bookId)))
          .getSingle();
      expect(book.title, 'Folder Book');
      expect(book.needsPush, isTrue, reason: 'new files are synced data');

      final files = await importer.audioFilesOf(bookId);
      expect([for (final f in files) f.track], [1, 2, 3]);
      expect([for (final f in files) f.label], ['Part 1', 'Part 2', 'Part 10']);
      expect(files.every((f) => f.format == 'mp3' && f.present), isTrue);
      expect(files.every((f) => (f.durationMs ?? 0) > 0), isTrue);
      for (final f in files) {
        expect(repo.fileOf(f).existsSync(), isTrue);
      }

      final chapters = await importer.chaptersOf(files);
      expect(chapters[files.first.id]!.single.title, 'Part 1');
    });

    test('an m4b keeps its chapters and gives a cover-less book its cover',
        () async {
      final importer = AudiobookImporter(repo);
      final bookId = await importer
          .importAsNewBook(await importer.scan(['$_fixtures/tiny.m4b']));
      final files = await importer.audioFilesOf(bookId);
      expect(files.single.narrator, 'Ned Narrator');
      final chapters = (await importer.chaptersOf(files))[files.single.id]!;
      expect([for (final c in chapters) c.title], ['Opening', 'Middle', 'End']);
      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals(bookId)))
          .getSingle();
      expect(book.coverPath, isNotNull);
    });

    test('replacing the audio removes the old parts, chapters and blobs',
        () async {
      final importer = AudiobookImporter(repo);
      final bookId = await importer
          .importAsNewBook(await importer.scan(['$_fixtures/tiny.m4b']));
      final old = await importer.audioFilesOf(bookId);
      await importer.attachTo(
        bookId,
        await importer.scan(['$_fixtures/folder/part 1.mp3']),
        replace: true,
      );
      final now = await importer.audioFilesOf(bookId);
      expect(now.single.format, 'mp3');
      expect(repo.fileOf(old.single).existsSync(), isFalse);
      expect(
          await (repo.db.select(repo.db.audioChapters)
                ..where((c) => c.fileId.equals(old.single.id)))
              .get(),
          isEmpty,
          reason: 'chapters cascade with their file');
    });

    test('deleting the book takes its audio and chapters with it', () async {
      final importer = AudiobookImporter(repo);
      final bookId = await importer
          .importAsNewBook(await importer.scan(['$_fixtures/tiny.m4b']));
      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals(bookId)))
          .getSingle();
      await repo.deleteBook(book);
      expect(await repo.db.select(repo.db.bookFiles).get(), isEmpty);
      expect(await repo.db.select(repo.db.audioChapters).get(), isEmpty);
    });

    test('a folder import makes one book of a folder of mp3s', () async {
      final folder = Directory.systemTemp.createTempSync('vellum_audio_folder');
      addTearDown(() => folder.deleteSync(recursive: true));
      final book = Directory(p.join(folder.path, 'Folder Book'))..createSync();
      for (final f in Directory('$_fixtures/folder').listSync().whereType<File>()) {
        f.copySync(p.join(book.path, p.basename(f.path)));
      }
      // A lone short audio file elsewhere: music, not a book.
      File('$_fixtures/folder/part 1.mp3').copySync(p.join(folder.path, 'jingle.mp3'));
      File(p.join(folder.path, 'Ann Author - Text.pdf')).writeAsStringSync('pdf bytes');

      final service = FolderImportService(repo);
      final plan = await service.scan(folder);
      final audio = plan.where((c) => c.isAudiobook).toList();
      expect(audio, hasLength(1), reason: 'the jingle is under ten minutes');
      expect(audio.single.audioParts, hasLength(3));
      expect(audio.single.meta.title, 'Folder Book');
      expect(audio.single.status, ImportStatus.newBook);
      expect(plan.where((c) => !c.isAudiobook), hasLength(1));

      final report = await service.import(audio);
      expect(report.failures, isEmpty);
      final files = await AudiobookImporter(repo)
          .audioFilesOf(report.outcomes.single.bookId!);
      expect([for (final f in files) f.label], ['Part 1', 'Part 2', 'Part 10']);

      // Scanning again recognises the audiobook by its first part's hash.
      final again = await service.scan(folder);
      expect(again.firstWhere((c) => c.isAudiobook).status,
          ImportStatus.duplicateFile);
    });

    test('files picked on purpose are not skipped for being short', () async {
      final plan = await FolderImportService(repo)
          .scanFiles([File('$_fixtures/folder/part 1.mp3')]);
      expect(plan.single.isAudiobook, isTrue);
    });
  });
}

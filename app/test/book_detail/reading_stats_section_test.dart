// "Your reading" on the book page (v1.3.1): absent without a sitting, live when
// one is recorded, and honest about what each file format can measure.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/book_detail/reading_stats_section.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_reading_sec'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<LibraryRepository> pump(
    WidgetTester tester, {
    required String format,
    bool sitting = true,
    int? pageCount = 300,
    int? lastReadPage = 100,
  }) async {
    late LibraryRepository repo;
    late Book book;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'b1',
            title: 'Piranesi',
            pageCount: Value(pageCount),
            lastReadPage: Value(lastReadPage),
          ));
      await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: 'f1',
            bookId: 'b1',
            format: format,
            path: 'x.$format',
            sizeBytes: 1,
            sha256: 'x',
          ));
      if (sitting) {
        await db.into(db.readingSessions).insert(
              ReadingSessionsCompanion.insert(
                id: 's1',
                bookId: 'b1',
                startedAt: DateTime(2026, 7, 1, 9),
                endedAt: DateTime(2026, 7, 1, 9, 50),
                startPage: const Value(1),
                endPage: const Value(101),
              ),
            );
      }
      book = await (db.select(db.books)..where((b) => b.id.equals('b1')))
          .getSingle();
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReadingStatsSection(book: book, repository: repo),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  // Drift schedules a zero-length timer when a watched stream loses its last
  // listener; unmount and let it fire so the test ends with none pending.
  Future<void> finish(WidgetTester tester, LibraryRepository repo) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(repo.db.close);
  }

  testWidgets('shown only once there is a sitting', (tester) async {
    final repo = await pump(tester, format: 'pdf', sitting: false);
    expect(find.text('Your reading'), findsNothing);
    await finish(tester, repo);
  });

  testWidgets('a PDF shows time, sittings, dates, pace and an estimate',
      (tester) async {
    final repo = await pump(tester, format: 'pdf');
    expect(find.text('Your reading'), findsOneWidget);
    expect(find.text('50m'), findsOneWidget);
    expect(find.text('Jul 1, 2026'), findsNWidgets(2));
    expect(find.text('2.0 pages a minute'), findsOneWidget);
    // 200 pages left at 2 a minute.
    expect(find.text('Estimated time left'), findsOneWidget);
    expect(find.text('About 1h 40m'), findsOneWidget);
    await finish(tester, repo);
  });

  testWidgets('an EPUB shows no pace or estimate: its unit is chapters',
      (tester) async {
    final repo = await pump(tester, format: 'epub');
    expect(find.text('Your reading'), findsOneWidget);
    expect(find.text('Time spent'), findsOneWidget);
    expect(find.text('Pace'), findsNothing);
    expect(find.text('Estimated time left'), findsNothing);
    await finish(tester, repo);
  });

  testWidgets('no page count means no estimate, but pace stays',
      (tester) async {
    final repo = await pump(tester, format: 'pdf', pageCount: null);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Estimated time left'), findsNothing);
    await finish(tester, repo);
  });

  testWidgets('updates when a sitting is recorded', (tester) async {
    final repo = await pump(tester, format: 'pdf', sitting: false);
    expect(find.text('Your reading'), findsNothing);
    await tester.runAsync(() async {
      await repo.db.into(repo.db.readingSessions).insert(
            ReadingSessionsCompanion.insert(
              id: 's9',
              bookId: 'b1',
              startedAt: DateTime(2026, 7, 2, 9),
              endedAt: DateTime(2026, 7, 2, 9, 10),
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Your reading'), findsOneWidget);
    await finish(tester, repo);
  });
}

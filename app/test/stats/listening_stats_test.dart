// Listening time in Insights (docs/AUDIOBOOKS.md section 5). The risk this
// guards is the one the design note names: one query missing its
// `kind = 'read'` and listening quietly turning into reading time. So the
// reading figures are computed with and without listening sittings present,
// and must not move; the listening figures are pinned on their own.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/stats/book_reading_stats.dart';
import 'package:vellum/stats/insights_page.dart';
import 'package:vellum/stats/insights_range.dart';
import 'package:vellum/stats/insights_summary.dart';
import 'package:vellum/stats/month_review.dart';
import 'package:vellum/stats/year_review.dart';
import 'dart:io';

final _today = DateTime(2026, 11, 20, 21);

Book _book(String id, {DateTime? finishedAt}) => Book(
      id: id,
      title: 'Book $id',
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
      finishedAt: finishedAt,
      status: finishedAt == null ? 'reading' : 'finished',
      readCount: finishedAt == null ? 0 : 1,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false,
      syncExcluded: false,
      needsProgressPush: false,
    );

ReadingSession _read(String id, DateTime start, int minutes,
        {String book = 'r', int from = 1, int to = 11}) =>
    ReadingSession(
      id: id,
      bookId: book,
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      startPage: from,
      endPage: to,
      deviceLabel: 'Phone',
      needsPush: false,
      kind: 'read',
      open: false,
    );

ReadingSession _listen(String id, DateTime start, int minutes,
        {String book = 'a'}) =>
    ReadingSession(
      id: id,
      bookId: book,
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      startSecond: 0,
      endSecond: minutes * 90, // 1.5x
      deviceLabel: 'Phone',
      needsPush: false,
      kind: 'listen',
      open: false,
    );

void main() {
  final reads = [
    _read('r1', DateTime(2026, 11, 20, 20), 30),
    _read('r2', DateTime(2026, 11, 19, 21), 45, from: 11, to: 40),
    _read('r3', DateTime(2026, 10, 2, 9), 20, from: 40, to: 50),
  ];
  final listens = [
    _listen('l1', DateTime(2026, 11, 20, 7), 60),
    _listen('l2', DateTime(2026, 11, 18, 22), 90),
    _listen('l3', DateTime(2026, 11, 17, 22), 15, book: 'b2'),
    _listen('l4', DateTime(2026, 5, 1, 8), 40),
  ];
  final books = [
    _book('r', finishedAt: DateTime(2026, 11, 1)),
    _book('a', finishedAt: DateTime(2026, 11, 10)),
    _book('b2'),
    _book('p', finishedAt: DateTime(2026, 11, 12)), // read in print
  ];

  InsightsInput input({required bool withListening}) => InsightsInput(
        sessions: reads,
        listening: withListening ? listens : const [],
        books: books,
        genresByBook: const {},
        formatsByBook: const {},
      );

  group('reading figures do not move when listening is present', () {
    for (final range in InsightsRange.values) {
      test('insights, ${range.name}', () {
        final without = InsightsSummary(input(withListening: false), range, _today);
        final withL = InsightsSummary(input(withListening: true), range, _today);
        expect(withL.totalMinutes, without.totalMinutes);
        expect(withL.totalPages, without.totalPages);
        expect(withL.totalFinished, without.totalFinished);
        expect(withL.readingDays, without.readingDays);
        expect(withL.allReadingDays, without.allReadingDays);
        expect(withL.currentStreak, without.currentStreak);
        expect(withL.longestStreak, without.longestStreak);
        expect(withL.hourSeries, without.hourSeries);
        expect(withL.deviceSeries, without.deviceSeries);
        expect(withL.allMinutesPerDay, without.allMinutesPerDay);
        expect(withL.pagesSeries, without.pagesSeries);
        expect(withL.averagePages, without.averagePages);
        expect(withL.best, without.best);
        expect(withL.thisWeekPages, without.thisWeekPages);
      });
    }

    test('the month and year reviews', () {
      final mixed = [...reads, ...listens];
      final month = MonthReviews.review(
          sessions: mixed, books: books, month: DateTime(2026, 11), today: _today);
      final plain = MonthReviews.review(
          sessions: reads, books: books, month: DateTime(2026, 11), today: _today);
      expect(month.minutes, plain.minutes);
      expect(month.pages, plain.pages);
      expect(month.readingDays, plain.readingDays);
      expect(month.longestSitting, plain.longestSitting);
      expect(month.minutesByDay, plain.minutesByDay);
      expect(month.best, plain.best);
      final prevMixed =
          MonthReviews.previousFigures(sessions: mixed, review: month);
      final prevPlain =
          MonthReviews.previousFigures(sessions: reads, review: plain);
      expect(prevMixed, prevPlain);

      final year = YearReviews.review(sessions: mixed, books: books, year: 2026);
      final plainYear =
          YearReviews.review(sessions: reads, books: books, year: 2026);
      expect(year.minutes, plainYear.minutes);
      expect(year.pages, plainYear.pages);
      expect(year.readingDays, plainYear.readingDays);
      expect(year.longestStreak, plainYear.longestStreak);
      expect(year.bestMonth, plainYear.bestMonth);
      expect(year.minutesByMonth, plainYear.minutesByMonth);
      expect(YearReviews.previousFigures(sessions: mixed, books: books, year: 2027),
          YearReviews.previousFigures(sessions: reads, books: books, year: 2027));
    });

    test('the book page reading line', () {
      final mixed = [reads.first, ...listens];
      final r = BookReading.of(mixed)!;
      expect(r.minutes, 30);
      expect(r.sittings, 1);
      expect(BookReading.of(listens), isNull,
          reason: 'listening alone is not "your reading"');
    });
  });

  group('the listening figures', () {
    ListeningFigures figures(InsightsRange range) =>
        InsightsSummary(input(withListening: true), range, _today).listen;

    test('time, days, sittings and streaks', () {
      final all = figures(InsightsRange.allTime);
      expect(all.totalMinutes, 60 + 90 + 15 + 40);
      expect(all.sittings, 4);
      expect(all.days.length, 4);
      // 20 Nov (today), 18 and 17 Nov: today only, as 19 Nov has none.
      expect(all.currentStreak, 1);
      expect(all.longestStreak, 2);
      expect(all.hourSeries[7], 60);
      expect(all.hourSeries[22], 105);
      expect(all.isEmpty, isFalse);
    });

    test('the range applies to time but not to the streaks', () {
      final month = figures(InsightsRange.last30Days);
      expect(month.totalMinutes, 165, reason: 'the May sitting is outside');
      expect(month.longestStreak, 2);
    });

    test('this week and last week, by wall-clock minutes', () {
      final f = figures(InsightsRange.allTime);
      expect(f.thisWeekMinutes, 165);
      expect(f.lastWeekMinutes, 0);
    });

    test('books finished by listening only counts listened books', () {
      final f = figures(InsightsRange.allTime);
      expect([for (final b in f.finished) b.id], ['a']);
    });

    test('no listening is an empty view, not a crash', () {
      final f = InsightsSummary(input(withListening: false),
              InsightsRange.allTime, _today)
          .listen;
      expect(f.isEmpty, isTrue);
      expect(f.totalMinutes, 0);
      expect(f.finished, isEmpty);
    });
  });

  group('month and year count listening on its own', () {
    test('month', () {
      final m = MonthReviews.review(
          sessions: [...reads, ...listens],
          books: books,
          month: DateTime(2026, 11),
          today: _today);
      expect(m.listenMinutes, 165);
      expect(m.listenDays, 3);
      expect(m.minutes, 75, reason: 'reading time stays reading time');
      expect(m.pages, 10 + 29);
      final onlyListening = MonthReviews.review(
          sessions: listens,
          books: const [],
          month: DateTime(2026, 5),
          today: _today);
      expect(onlyListening.isEmpty, isFalse,
          reason: 'a month of listening is not an empty month');
      expect(onlyListening.pages, 0);
    });

    test('year', () {
      final y = YearReviews.review(
          sessions: [...reads, ...listens], books: books, year: 2026);
      expect(y.listenMinutes, 205);
      expect(y.listenDays, 4);
      expect(y.pages, 10 + 29 + 10);
    });
  });

  test('the book page listening line', () {
    final l = BookListening.of([...reads, ...listens])!;
    expect(l.minutes, 205);
    expect(l.last, DateTime(2026, 11, 20));
    expect(BookListening.of(reads), isNull);
  });

  group('the page', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vellum_listen_ui'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pump(WidgetTester tester,
        {required bool withReading, required bool withListening}) async {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late LibraryRepository repo;
      late AppSettingsStore settings;
      await tester.runAsync(() async {
        SharedPreferences.setMockInitialValues({});
        settings = await AppSettingsStore.load();
        await settings.setInsightsRange(InsightsRange.allTime);
        repo = await LibraryRepository.forTesting(
            VellumDatabase(NativeDatabase.memory()), dir);
        final db = repo.db;
        await db.into(db.books).insert(BooksCompanion.insert(id: 'a', title: 'Dune'));
        if (withReading) {
          await db.into(db.readingSessions).insert(ReadingSessionsCompanion.insert(
                id: 'r1',
                bookId: 'a',
                startedAt: DateTime(2026, 7, 19, 21),
                endedAt: DateTime(2026, 7, 19, 21, 40),
                startPage: const Value(1),
                endPage: const Value(30),
              ));
        }
        if (withListening) {
          await db.into(db.readingSessions).insert(ReadingSessionsCompanion.insert(
                id: 'l1',
                bookId: 'a',
                startedAt: DateTime(2026, 7, 20, 7),
                endedAt: DateTime(2026, 7, 20, 8, 15),
                kind: const Value('listen'),
              ));
        }
      });
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: InsightsPage(repository: repo, settings: settings),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('switching shows listening time, and reading is unchanged',
        (tester) async {
      await pump(tester, withReading: true, withListening: true);
      expect(find.text('Time reading'), findsOneWidget);
      expect(find.text('40m'), findsWidgets, reason: 'only the reading sitting');
      expect(find.text('Time listening'), findsNothing);

      await tester.tap(find.text('Listening'));
      await tester.pumpAndSettle();
      expect(find.text('Time listening'), findsOneWidget);
      expect(find.text('1h 15m'), findsWidgets);
      expect(find.text('Time reading'), findsNothing);
      expect(find.text('Pages read'), findsNothing);

      await tester.tap(find.text('Reading'));
      await tester.pumpAndSettle();
      expect(find.text('Time reading'), findsOneWidget);
    });

    testWidgets('no switch without listening', (tester) async {
      await pump(tester, withReading: true, withListening: false);
      expect(find.text('Listening'), findsNothing);
    });

    testWidgets('a listening-only history opens on Listening', (tester) async {
      await pump(tester, withReading: false, withListening: true);
      expect(find.text('Time listening'), findsOneWidget);
    });
  });
}

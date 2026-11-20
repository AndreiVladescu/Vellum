// Continue listening (v1.5.2): the strip next to Continue reading. A book with
// text and audio has a reading position and a listening position, and each
// strip follows its own.
import 'package:drift/drift.dart' show Value;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/audio/continue_listening.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/l10n/delegates.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/shelf/library_header.dart';

const _hour = 3600 * 1000;

Book _book(
  String id,
  String title, {
  double? at,
  DateTime? heard,
  double? progress,
  DateTime? read,
  String status = 'reading',
  DateTime? created,
}) =>
    Book(
      id: id,
      title: title,
      readingProgress: progress,
      lastReadAt: read,
      listenPosition: at,
      lastListenedAt: heard,
      createdAt: created ?? DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false,
      syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
      needsProgressPush: false,
      status: status,
      readCount: 0,
    );

LibraryView _view(List<(Book, int?)> books) => LibraryView(
      entries: [
        for (final (b, ms) in books)
          LibraryEntry(
              book: b,
              authors: const [],
              genres: const [],
              hasFile: true,
              audioMs: ms),
      ],
      shelves: const [],
      allGenres: const [],
      scopeEmpty: books.isEmpty,
    );

void main() {
  group('what counts as on the go', () {
    test('played, not near the end, not finished', () {
      final b = _book('a', 'A', at: 600, heard: DateTime(2026));
      expect(isListeningOnTheGo(b, 10 * _hour), isTrue);
      expect(isListeningOnTheGo(b, null), isFalse, reason: 'no audio');
      expect(isListeningOnTheGo(_book('a', 'A'), 10 * _hour), isFalse,
          reason: 'never played');
      expect(isListeningOnTheGo(b.copyWith(status: 'finished'), 10 * _hour),
          isFalse);
    });

    test('the last 30 seconds are the end', () {
      final nearEnd =
          _book('a', 'A', at: 3600 - 29, heard: DateTime(2026));
      expect(isListeningOnTheGo(nearEnd, _hour), isFalse);
      final before = _book('a', 'A', at: 3600 - 31, heard: DateTime(2026));
      expect(isListeningOnTheGo(before, _hour), isTrue);
    });

    test('unknown length cannot judge the end, so it stays on the go', () {
      final b = _book('a', 'A', at: 99999, heard: DateTime(2026));
      expect(isListeningOnTheGo(b, 0), isTrue);
      expect(listenFraction(b, 0), isNull);
    });

    test('fraction through the audio', () {
      final b = _book('a', 'A', at: 1800, heard: DateTime(2026));
      expect(listenFraction(b, _hour), 0.5);
      expect(listenFraction(b.copyWith(listenPosition: const Value(9999)), _hour), 1.0);
    });
  });

  group('selection', () {
    test('most recently listened first, limited, apart from reading', () {
      final view = _view([
        (_book('old', 'Old', at: 100, heard: DateTime(2026, 1)), _hour),
        (_book('new', 'New', at: 100, heard: DateTime(2026, 3)), _hour),
        (_book('mid', 'Mid', at: 100, heard: DateTime(2026, 2)), _hour),
        (_book('4th', 'Fourth', at: 100, heard: DateTime(2025, 12)), _hour),
        (_book('text', 'Text', progress: 0.4, read: DateTime(2026, 4)), null),
      ]);
      final h = LibraryHighlights.from(view);
      expect([for (final l in h.continueListening) l.book.id],
          ['new', 'mid', 'old']);
      expect([for (final b in h.continueReading) b.id], ['text']);
    });

    test('a book with both positions is in both strips', () {
      final both = _book('both', 'Both',
          progress: 0.3,
          read: DateTime(2026, 2),
          at: 600,
          heard: DateTime(2026, 3));
      final h = LibraryHighlights.from(_view([(both, 5 * _hour)]));
      expect(h.continueReading.map((b) => b.id), ['both']);
      expect(h.continueListening.map((l) => l.book.id), ['both']);
    });

    test('audio that is gone, or finished, is not offered', () {
      final h = LibraryHighlights.from(_view([
        (_book('gone', 'Gone', at: 600, heard: DateTime(2026)), null),
        (_book('done', 'Done', at: 600, heard: DateTime(2026), status: 'finished'),
            _hour),
      ]));
      expect(h.continueListening, isEmpty);
    });

    test('it is not also "recently added"', () {
      final h = LibraryHighlights.from(_view([
        (_book('a', 'A', at: 600, heard: DateTime(2026), created: DateTime(2026, 9)),
            _hour),
      ]));
      expect(h.recentlyAdded, isEmpty);
      expect(h.isEmpty, isFalse);
    });
  });

  group('the strip', () {
    Widget host(LibraryHighlights h,
            {void Function(Book)? onOpen,
            void Function(Book)? onListen,
            Size? size,
            double textScale = 1.0}) =>
        MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
                size: size ?? const Size(400, 900),
                textScaler: TextScaler.linear(textScale)),
            child: Scaffold(
              body: LibraryHeader(
                highlights: h,
                onOpen: onOpen ?? (_) {},
                onListen: onListen,
              ),
            ),
          ),
        );

    final h = LibraryHighlights.from(_view([
      (_book('read', 'Halfway', progress: 0.5, read: DateTime(2026, 6)), null),
      (_book('heard', 'Heard Book', at: 3723, heard: DateTime(2026, 7)),
          10 * _hour),
    ]));

    testWidgets('sits next to Continue reading, same card, own subtitle',
        (tester) async {
      await tester.pumpWidget(host(h));
      await tester.pump();
      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Continue listening'), findsOneWidget);
      expect(find.text('Heard Book'), findsOneWidget);
      expect(find.text('10% · at 1:02:03'), findsOneWidget);
      expect(find.byIcon(Icons.headphones), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
    });

    testWidgets('tapping it opens the player, not the book page',
        (tester) async {
      Book? opened, listened;
      await tester.pumpWidget(
          host(h, onOpen: (b) => opened = b, onListen: (b) => listened = b));
      await tester.pump();
      await tester.tap(find.text('Heard Book'));
      expect(listened?.id, 'heard');
      expect(opened, isNull);
      await tester.tap(find.text('Halfway'));
      expect(opened?.id, 'read');
    });

    testWidgets('without a player callback it opens the book', (tester) async {
      Book? opened;
      await tester.pumpWidget(host(h, onOpen: (b) => opened = b));
      await tester.pump();
      await tester.tap(find.text('Heard Book'));
      expect(opened?.id, 'heard');
    });

    testWidgets('on a short screen both survive in the compact row',
        (tester) async {
      await tester.pumpWidget(host(h, size: const Size(880, 400)));
      await tester.pump();
      expect(find.text('Halfway'), findsOneWidget);
      expect(find.text('Heard Book'), findsOneWidget);
      expect(find.text('Continue listening'), findsNothing,
          reason: 'headings go first on a short screen');
    });

    testWidgets('and at large text it does not overflow', (tester) async {
      await tester.pumpWidget(host(h, textScale: 2.0));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

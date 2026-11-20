// The Read / Resume row on the book page must fit a narrow phone at normal
// text size (reported once as an ~81 px overflow at 400 px wide).
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/book_detail/read_button.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/delegates.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_read_btn'));
  tearDown(() => dir.deleteSync(recursive: true));

  for (final width in [360.0, 400.0]) {
    for (final formats in [
      ['epub'],
      ['pdf', 'epub'],
    ]) {
      testWidgets('resume row fits $width px, ${formats.join('+')}',
          (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late LibraryRepository repo;
        late Book book;
        await tester.runAsync(() async {
          repo = await LibraryRepository.forTesting(
            VellumDatabase(NativeDatabase.memory()),
            dir,
          );
          final db = repo.db;
          await db.into(db.books).insert(BooksCompanion.insert(
                id: 'b',
                title: 'Piranesi',
                readingProgress: const Value(0.42),
                lastReadPage: const Value(214),
              ));
          for (final f in formats) {
            await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
                  id: f,
                  bookId: 'b',
                  format: f,
                  path: 'x.$f',
                  sizeBytes: 1,
                  sha256: f,
                ));
          }
          book = await (db.select(db.books)..where((b) => b.id.equals('b')))
              .getSingle();
        });

        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ReadButton(book: book, repository: repo),
            ),
          ),
        ));
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.play_arrow), findsOneWidget);

        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      });
    }
  }
}
